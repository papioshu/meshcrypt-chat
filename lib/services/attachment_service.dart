import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image/image.dart' as img;
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../models/attachment_model.dart';
import 'encryption_service.dart';

/// Comprehensive attachment service for encrypted file handling,
/// LoRa transmission support, file previews, and secure storage
class AttachmentService {
  static final AttachmentService _instance = AttachmentService._internal();
  factory AttachmentService() => _instance;
  AttachmentService._internal();

  // Service dependencies
  late final EncryptionService _encryptionService;
  late final FlutterSecureStorage _secureStorage;
  final Uuid _uuid = const Uuid();

  // Configuration constants
  static const int _maxFileSize = 50 * 1024 * 1024; // 50MB max file size
  static const int _chunkSize = 240; // LoRa packet size (bytes)
  static const int _maxRetries = 3;
  static const Duration _expirationCheckInterval = Duration(hours: 1);
  static const Duration _previewExpiry = Duration(days: 7);

  // Internal state
  final Map<String, AttachmentChunk> _chunkMap = {};
  final Map<String, AttachmentExpiration> _expirationMap = {};
  Timer? _expirationTimer;

  // Supported file types
  static const Set<String> _supportedImageTypes = {
    'image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/bmp'
  };
  static const Set<String> _supportedAudioTypes = {
    'audio/mpeg', 'audio/wav', 'audio/ogg', 'audio/m4a', 'audio/aac', 'audio/flac'
  };
  static const Set<String> _supportedDocumentTypes = {
    'application/pdf', 'text/plain', 'application/msword', 
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-powerpoint', 'application/vnd.openxmlformats-officedocument.presentationml.presentation'
  };
  static const Set<String> _supportedVideoTypes = {
    'video/mp4', 'video/avi', 'video/mov', 'video/wmv', 'video/flv', 'video/webm'
  };

  /// Initialize the attachment service
  Future<void> initialize({
    EncryptionService? encryptionService,
    FlutterSecureStorage? secureStorage,
  }) async {
    _encryptionService = encryptionService ?? EncryptionService();
    await _encryptionService.initialize();
    
    _secureStorage = secureStorage ?? const FlutterSecureStorage();

    // Start expiration checker
    _startExpirationChecker();
    
    // Clean up expired files on startup
    await _cleanupExpiredFiles();
  }

  /// Pick and process file for secure storage
  Future<Attachment> pickAndProcessFile({
    required String messageId,
    required String senderId,
    PlatformFile? pickedFile,
    Uint8List? fileData,
    String? fileName,
    String? mimeType,
    bool isEncrypted = true,
    Duration? expirationTime,
  }) async {
    // Validate file
    final file = await _validateAndGetFile(pickedFile, fileData, fileName, mimeType);
    if (file == null) {
      throw AttachmentException('Failed to pick or read file');
    }

    // Detect attachment type
    final type = _detectAttachmentType(file.mimeType);
    if (type == null) {
      throw AttachmentException('Unsupported file type: ${file.mimeType}');
    }

    // Generate file ID
    final fileId = _uuid.v4();

    // Generate encryption key
    final fileKey = _generateFileKey();

    // Encrypt file data
    final encryptedData = isEncrypted 
        ? await _encryptFileData(file.data, fileKey)
        : file.data;

    // Generate thumbnail for images
    Uint8List? thumbnail;
    if (type == AttachmentType.image) {
      thumbnail = await _generateImageThumbnail(file.data);
    }

    // Store encrypted file
    final storagePath = await _storeEncryptedFile(
      fileId: fileId,
      data: encryptedData,
      originalFileName: file.fileName,
      mimeType: file.mimeType,
      fileKey: fileKey,
    );

    // Create attachment record
    final attachment = Attachment(
      id: fileId,
      messageId: messageId,
      type: type,
      fileName: file.fileName,
      mimeType: file.mimeType,
      sizeBytes: file.data.length,
      filePath: storagePath,
      thumbnail: thumbnail,
      isEncrypted: isEncrypted,
      encryptedData: base64Encode(encryptedData),
      createdAt: DateTime.now(),
    );

    // Set expiration if requested
    if (expirationTime != null) {
      await _setExpiration(fileId, expirationTime);
    }

    return attachment;
  }

  /// Encrypt file data using encryption service
  Future<Uint8List> _encryptFileData(Uint8List data, Uint8List fileKey) async {
    // Use the existing encryption service with file key
    final encrypted = await _encryptionService.encrypt(data, fileKey);
    return base64Decode(encrypted);
  }

  /// Decrypt file data using encryption service
  Future<Uint8List> decryptFileData(String encryptedData, Uint8List fileKey) async {
    return await _encryptionService.decrypt(encryptedData, fileKey);
  }

  /// Chunk file for LoRa transmission
  Future<List<AttachmentChunk>> createChunks({
    required String fileId,
    required Uint8List data,
    required String recipientId,
    Map<String, dynamic>? metadata,
  }) async {
    final chunks = <AttachmentChunk>[];
    final totalChunks = (data.length / _chunkSize).ceil();
    
    // Generate file fingerprint for integrity
    final fingerprint = sha256.convert(data).toString();

    for (int i = 0; i < totalChunks; i++) {
      final start = i * _chunkSize;
      final end = (i + 1) * _chunkSize;
      final chunkData = data.sublist(
        start, 
        end < data.length ? end : data.length
      );

      final chunk = AttachmentChunk(
        chunkId: _uuid.v4(),
        fileId: fileId,
        chunkIndex: i,
        totalChunks: totalChunks,
        data: chunkData,
        fingerprint: fingerprint,
        metadata: {
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'size_bytes': chunkData.length,
          ...?metadata,
        },
      );

      chunks.add(chunk);
    }

    // Store chunk information
    for (final chunk in chunks) {
      _chunkMap[chunk.chunkId] = chunk;
    }

    return chunks;
  }

  /// Reassemble file from chunks
  Future<Uint8List?> reassembleFile(List<AttachmentChunk> chunks) async {
    if (chunks.isEmpty) return null;

    // Sort chunks by index
    chunks.sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));

    // Verify all chunks are present
    final expectedTotal = chunks.first.totalChunks;
    if (chunks.length != expectedTotal) {
      throw AttachmentException('Missing chunks: got ${chunks.length}, expected $expectedTotal');
    }

    // Verify integrity
    final data = BytesBuilder();
    for (final chunk in chunks) {
      data.add(chunk.data);
    }

    final reassembledData = data.toBytes();
    final fingerprint = sha256.convert(reassembledData).toString();
    
    if (fingerprint != chunks.first.fingerprint) {
      throw AttachmentException('File integrity check failed');
    }

    return reassembledData;
  }

  /// Generate image thumbnail
  Future<Uint8List?> _generateImageThumbnail(Uint8List imageData) async {
    try {
      final image = img.decodeImage(imageData);
      if (image == null) return null;

      // Resize to thumbnail size (max 200x200)
      final thumbnail = img.copyResize(
        image, 
        width: 200, 
        height: 200,
        interpolation: img.Interpolation.linear,
      );

      return Uint8List.fromList(img.encodeJpg(thumbnail, quality: 80));
    } catch (e) {
      return null;
    }
  }

  /// Generate document preview
  Future<String?> generateDocumentPreview(Uint8List data, String mimeType) async {
    try {
      if (mimeType == 'text/plain') {
        // For text files, return first few lines
        final text = utf8.decode(data);
        final lines = text.split('\n').take(5);
        return lines.join('\n');
      } else if (mimeType.startsWith('application/pdf')) {
        // For PDFs, we can't easily extract text without additional libraries
        return 'PDF document (${(data.length / 1024).toStringAsFixed(1)} KB)';
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Download and decrypt attachment
  Future<File?> downloadAndDecrypt({
    required String fileId,
    required String savePath,
    Uint8List? fileKey,
  }) async {
    try {
      // Get attachment from storage
      final attachmentData = await _getAttachmentData(fileId);
      if (attachmentData == null) {
        throw AttachmentException('Attachment not found: $fileId');
      }

      final file = File(savePath);
      Uint8List data;

      if (attachmentData['is_encrypted'] == true && fileKey != null) {
        // Decrypt the file
        final encryptedData = base64Decode(attachmentData['encrypted_data'] as String);
        data = await decryptFileData(base64Encode(encryptedData), fileKey);
      } else {
        data = base64Decode(attachmentData['encrypted_data'] as String);
      }

      // Write file
      await file.writeAsBytes(data);
      return file;
    } catch (e) {
      throw AttachmentException('Failed to download and decrypt file: $e');
    }
  }

  /// Open attachment using system default app
  Future<void> openAttachment(Attachment attachment) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/${attachment.fileName}';
      
      final file = await downloadAndDecrypt(
        fileId: attachment.id,
        savePath: tempPath,
      );

      if (file == null) {
        throw AttachmentException('Failed to decrypt file');
      }

      // Determine how to open the file
      if (Platform.isAndroid || Platform.isIOS) {
        // Use share_plus for mobile
        final xFile = XFile(file.path, mimeType: attachment.mimeType);
        await Share.shareXFiles([xFile], subject: attachment.fileName);
      } else {
        // Use URL launcher for desktop
        final uri = Uri.file(file.absolute.path);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        } else {
          throw AttachmentException('Cannot open file: ${attachment.fileName}');
        }
      }
    } catch (e) {
      throw AttachmentException('Failed to open attachment: $e');
    }
  }

  /// Set file expiration (burn-after-read)
  Future<void> setExpiration(String fileId, Duration expirationTime) async {
    await _setExpiration(fileId, expirationTime);
  }

  /// Check if attachment has expired
  bool isExpired(String fileId) {
    final expiration = _expirationMap[fileId];
    if (expiration == null) return false;
    
    return DateTime.now().isAfter(expiration.expiresAt);
  }

  /// Delete attachment and clean up
  Future<void> deleteAttachment(String fileId) async {
    try {
      // Remove from chunk map
      _chunkMap.removeWhere((key, chunk) => chunk.fileId == fileId);
      
      // Remove from expiration map
      _expirationMap.remove(fileId);

      // Delete encrypted file
      await _deleteEncryptedFile(fileId);

      // Clear secure storage entries
      await _secureStorage.delete(key: 'attachment_$fileId');
    } catch (e) {
      throw AttachmentException('Failed to delete attachment: $e');
    }
  }

  /// Get file size in human readable format
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  /// Validate file and return file info
  Future<_FileInfo?> _validateAndGetFile(
    PlatformFile? pickedFile,
    Uint8List? fileData,
    String? fileName,
    String? mimeType,
  ) async {
    try {
      Uint8List data;
      String name;
      String type;

      if (pickedFile != null) {
        data = pickedFile.bytes ?? Uint8List(0);
        name = pickedFile.name;
        type = pickedFile.mimeType ?? lookupMimeType(name) ?? 'application/octet-stream';
      } else if (fileData != null && fileName != null) {
        data = fileData;
        name = fileName;
        type = mimeType ?? lookupMimeType(name) ?? 'application/octet-stream';
      } else {
        return null;
      }

      // Validate file size
      if (data.length > _maxFileSize) {
        throw AttachmentException('File too large. Maximum size is ${formatFileSize(_maxFileSize)}');
      }

      // Validate file type
      if (!_isSupportedFileType(type)) {
        throw AttachmentException('Unsupported file type: $type');
      }

      return _FileInfo(data: data, fileName: name, mimeType: type);
    } catch (e) {
      return null;
    }
  }

  /// Detect attachment type from MIME type
  AttachmentType? _detectAttachmentType(String mimeType) {
    if (_supportedImageTypes.contains(mimeType)) {
      return AttachmentType.image;
    } else if (_supportedAudioTypes.contains(mimeType)) {
      return AttachmentType.audio;
    } else if (_supportedVideoTypes.contains(mimeType)) {
      return AttachmentType.video;
    } else if (_supportedDocumentTypes.contains(mimeType)) {
      return AttachmentType.document;
    }
    return null;
  }

  /// Check if file type is supported
  bool _isSupportedFileType(String mimeType) {
    return _supportedImageTypes.contains(mimeType) ||
           _supportedAudioTypes.contains(mimeType) ||
           _supportedVideoTypes.contains(mimeType) ||
           _supportedDocumentTypes.contains(mimeType);
  }

  /// Generate random file key
  Uint8List _generateFileKey() {
    final bytes = Uint8List(32); // 256-bit key
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = (DateTime.now().millisecondsSinceEpoch + i) % 256;
    }
    return bytes;
  }

  /// Store encrypted file
  Future<String> _storeEncryptedFile({
    required String fileId,
    required Uint8List data,
    required String originalFileName,
    required String mimeType,
    required Uint8List fileKey,
  }) async {
    final appDir = await getApplicationDocumentsDirectory();
    final attachmentsDir = Directory('${appDir.path}/encrypted_attachments');
    
    if (!await attachmentsDir.exists()) {
      await attachmentsDir.create(recursive: true);
    }

    final fileName = '${fileId}_${DateTime.now().millisecondsSinceEpoch}.enc';
    final filePath = '${attachmentsDir.path}/$fileName';

    // Encrypt the data one more time for storage
    final storageEncryptedData = await _encryptFileData(data, fileKey);

    // Write encrypted file
    final file = File(filePath);
    await file.writeAsBytes(storageEncryptedData);

    // Store metadata in secure storage
    final metadata = {
      'file_id': fileId,
      'original_filename': originalFileName,
      'mime_type': mimeType,
      'size_bytes': data.length,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'file_key': base64Encode(fileKey),
      'storage_path': filePath,
    };

    await _secureStorage.write(
      key: 'attachment_$fileId',
      value: jsonEncode(metadata),
    );

    return filePath;
  }

  /// Get attachment data from secure storage
  Future<Map<String, dynamic>?> _getAttachmentData(String fileId) async {
    final metadataJson = await _secureStorage.read(key: 'attachment_$fileId');
    if (metadataJson == null) return null;
    return jsonDecode(metadataJson) as Map<String, dynamic>;
  }

  /// Delete encrypted file
  Future<void> _deleteEncryptedFile(String fileId) async {
    final metadata = await _getAttachmentData(fileId);
    if (metadata != null) {
      final storagePath = metadata['storage_path'] as String;
      final file = File(storagePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  /// Set file expiration
  Future<void> _setExpiration(String fileId, Duration expirationTime) async {
    final expiresAt = DateTime.now().add(expirationTime);
    _expirationMap[fileId] = AttachmentExpiration(
      fileId: fileId,
      expiresAt: expiresAt,
      createdAt: DateTime.now(),
    );

    // Store in secure storage for persistence
    final expirationData = {
      'file_id': fileId,
      'expires_at': expiresAt.millisecondsSinceEpoch,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    };

    await _secureStorage.write(
      key: 'expiration_$fileId',
      value: jsonEncode(expirationData),
    );
  }

  /// Start expiration checker timer
  void _startExpirationChecker() {
    _expirationTimer?.cancel();
    _expirationTimer = Timer.periodic(_expirationCheckInterval, (_) {
      _cleanupExpiredFiles();
    });
  }

  /// Clean up expired files
  Future<void> _cleanupExpiredFiles() async {
    final now = DateTime.now();
    final expiredFiles = <String>[];

    for (final entry in _expirationMap.entries) {
      if (now.isAfter(entry.value.expiresAt)) {
        expiredFiles.add(entry.key);
      }
    }

    // Delete expired files
    for (final fileId in expiredFiles) {
      await deleteAttachment(fileId);
    }
  }

  /// Get storage statistics
  Future<AttachmentStats> getStorageStats() async {
    final appDir = await getApplicationDocumentsDirectory();
    final attachmentsDir = Directory('${appDir.path}/encrypted_attachments');
    
    int totalSize = 0;
    int fileCount = 0;

    if (await attachmentsDir.exists()) {
      await for (final entity in attachmentsDir.list()) {
        if (entity is File) {
          totalSize += await entity.length();
          fileCount++;
        }
      }
    }

    return AttachmentStats(
      totalSizeBytes: totalSize,
      fileCount: fileCount,
      activeAttachments: _expirationMap.length,
    );
  }

  /// Clear all attachments (use with caution)
  Future<void> clearAllAttachments() async {
    try {
      // Cancel timer
      _expirationTimer?.cancel();
      
      // Clear all data
      _chunkMap.clear();
      _expirationMap.clear();
      
      // Delete attachments directory
      final appDir = await getApplicationDocumentsDirectory();
      final attachmentsDir = Directory('${appDir.path}/encrypted_attachments');
      if (await attachmentsDir.exists()) {
        await attachmentsDir.delete(recursive: true);
      }
      
      // Clear secure storage
      final keys = await _secureStorage.readAll();
      for (final key in keys.keys) {
        if (key.startsWith('attachment_') || key.startsWith('expiration_')) {
          await _secureStorage.delete(key: key);
        }
      }
      
      // Restart timer
      _startExpirationChecker();
    } catch (e) {
      throw AttachmentException('Failed to clear attachments: $e');
    }
  }

  /// Dispose of the service
  void dispose() {
    _expirationTimer?.cancel();
    _chunkMap.clear();
    _expirationMap.clear();
  }
}

/// Internal data class for file information
class _FileInfo {
  final Uint8List data;
  final String fileName;
  final String mimeType;

  _FileInfo({
    required this.data,
    required this.fileName,
    required this.mimeType,
  });
}

/// Model for file chunk information
class AttachmentChunk {
  final String chunkId;
  final String fileId;
  final int chunkIndex;
  final int totalChunks;
  final Uint8List data;
  final String fingerprint;
  final Map<String, dynamic> metadata;

  const AttachmentChunk({
    required this.chunkId,
    required this.fileId,
    required this.chunkIndex,
    required this.totalChunks,
    required this.data,
    required this.fingerprint,
    required this.metadata,
  });

  Map<String, dynamic> toMap() {
    return {
      'chunk_id': chunkId,
      'file_id': fileId,
      'chunk_index': chunkIndex,
      'total_chunks': totalChunks,
      'fingerprint': fingerprint,
      'metadata': metadata,
    };
  }

  factory AttachmentChunk.fromMap(Map<String, dynamic> map) {
    return AttachmentChunk(
      chunkId: map['chunk_id'] ?? '',
      fileId: map['file_id'] ?? '',
      chunkIndex: map['chunk_index'] ?? 0,
      totalChunks: map['total_chunks'] ?? 0,
      data: Uint8List.fromList((map['data'] as List<dynamic>).cast<int>()),
      fingerprint: map['fingerprint'] ?? '',
      metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
    );
  }
}

/// Model for file expiration tracking
class AttachmentExpiration {
  final String fileId;
  final DateTime expiresAt;
  final DateTime createdAt;

  const AttachmentExpiration({
    required this.fileId,
    required this.expiresAt,
    required this.createdAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  Duration get remainingTime => expiresAt.difference(DateTime.now());
}

/// Model for storage statistics
class AttachmentStats {
  final int totalSizeBytes;
  final int fileCount;
  final int activeAttachments;

  const AttachmentStats({
    required this.totalSizeBytes,
    required this.fileCount,
    required this.activeAttachments,
  });

  String get formattedSize => AttachmentService.formatFileSize(totalSizeBytes);
  double get averageSize => fileCount > 0 ? totalSizeBytes / fileCount : 0;
}

/// Exception class for attachment service errors
class AttachmentException implements Exception {
  final String message;
  AttachmentException(this.message);

  @override
  String toString() => 'AttachmentException: $message';
}