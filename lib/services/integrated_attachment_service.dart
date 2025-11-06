import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

import '../services/attachment_service.dart';
import '../services/database_service.dart';
import '../services/encryption_service.dart';
import '../models/attachment_model.dart';
import '../models/message_model.dart';

/// Integrated attachment service that combines attachment handling with database storage
/// This service provides seamless integration between the attachment service and database service
class IntegratedAttachmentService {
  static final IntegratedAttachmentService _instance = IntegratedAttachmentService._internal();
  factory IntegratedAttachmentService() => _instance;
  IntegratedAttachmentService._internal();

  late final AttachmentService _attachmentService;
  late final DatabaseService _databaseService;
  late final EncryptionService _encryptionService;

  /// Initialize all services
  Future<void> initialize() async {
    // Initialize individual services
    await DatabaseService.initialize();
    _databaseService = DatabaseService.instance;
    
    _encryptionService = EncryptionService();
    await _encryptionService.initialize();
    
    _attachmentService = AttachmentService();
    await _attachmentService.initialize(
      encryptionService: _encryptionService,
    );
  }

  /// Create and store an attachment with database integration
  Future<Attachment> createAttachment({
    required Message message,
    required PlatformFile? pickedFile,
    Uint8List? fileData,
    String? fileName,
    String? mimeType,
    bool isEncrypted = true,
    Duration? expirationTime,
  }) async {
    try {
      // Create attachment using attachment service
      final attachment = await _attachmentService.pickAndProcessFile(
        messageId: message.id,
        senderId: message.senderId,
        pickedFile: pickedFile,
        fileData: fileData,
        fileName: fileName,
        mimeType: mimeType,
        isEncrypted: isEncrypted,
        expirationTime: expirationTime,
      );

      // Store attachment metadata in database
      final attachmentData = {
        'id': attachment.id,
        'message_id': attachment.messageId,
        'type': _getAttachmentTypeString(attachment.type),
        'file_name': attachment.fileName,
        'mime_type': attachment.mimeType,
        'size_bytes': attachment.sizeBytes,
        'file_path': attachment.filePath,
        'thumbnail': attachment.thumbnail != null ? attachment.thumbnail!.toList() : null,
        'metadata': attachment.metadata != null ? jsonEncode(attachment.metadata) : null,
        'is_encrypted': attachment.isEncrypted ? 1 : 0,
        'encrypted_data': attachment.encryptedData,
        'created_at': attachment.createdAt.millisecondsSinceEpoch,
      };

      await _databaseService.insertAttachment(attachmentData);

      return attachment;
    } catch (e) {
      throw AttachmentIntegrationException('Failed to create attachment: $e');
    }
  }

  /// Get attachment from database
  Future<Attachment?> getAttachment(String attachmentId) async {
    try {
      final attachmentData = await _databaseService.getAttachment(attachmentId);
      if (attachmentData == null) return null;

      return _convertDatabaseToAttachment(attachmentData);
    } catch (e) {
      throw AttachmentIntegrationException('Failed to get attachment: $e');
    }
  }

  /// Get all attachments for a message
  Future<List<Attachment>> getMessageAttachments(String messageId) async {
    try {
      final attachmentsData = await _databaseService.getAttachmentsForMessage(messageId);
      return attachmentsData
          .map((data) => _convertDatabaseToAttachment(data))
          .toList();
    } catch (e) {
      throw AttachmentIntegrationException('Failed to get message attachments: $e');
    }
  }

  /// Delete attachment from both file system and database
  Future<void> deleteAttachment(String attachmentId) async {
    try {
      // Delete from attachment service (file system)
      await _attachmentService.deleteAttachment(attachmentId);

      // Delete from database
      await _databaseService.deleteAttachment(attachmentId);
    } catch (e) {
      throw AttachmentIntegrationException('Failed to delete attachment: $e');
    }
  }

  /// Download and decrypt attachment
  Future<File?> downloadAttachment({
    required String attachmentId,
    required String savePath,
    Uint8List? fileKey,
  }) async {
    try {
      return await _attachmentService.downloadAndDecrypt(
        fileId: attachmentId,
        savePath: savePath,
        fileKey: fileKey,
      );
    } catch (e) {
      throw AttachmentIntegrationException('Failed to download attachment: $e');
    }
  }

  /// Open attachment using system default app
  Future<void> openAttachment(Attachment attachment) async {
    try {
      await _attachmentService.openAttachment(attachment);
    } catch (e) {
      throw AttachmentIntegrationException('Failed to open attachment: $e');
    }
  }

  /// Set attachment expiration
  Future<void> setAttachmentExpiration(String attachmentId, Duration expirationTime) async {
    try {
      await _attachmentService.setExpiration(attachmentId, expirationTime);
    } catch (e) {
      throw AttachmentIntegrationException('Failed to set expiration: $e');
    }
  }

  /// Check if attachment is expired
  bool isAttachmentExpired(String attachmentId) {
    return _attachmentService.isExpired(attachmentId);
  }

  /// Create file chunks for LoRa transmission
  Future<List<AttachmentChunk>> createTransmissionChunks({
    required String attachmentId,
    required String recipientId,
  }) async {
    try {
      // Get attachment from database
      final attachment = await getAttachment(attachmentId);
      if (attachment == null) {
        throw AttachmentIntegrationException('Attachment not found: $attachmentId');
      }

      // Download and decrypt file
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/${attachment.fileName}';
      
      final file = await downloadAttachment(
        attachmentId: attachmentId,
        savePath: tempPath,
        fileKey: Uint8List.fromList([]), // Use appropriate key from secure storage
      );

      if (file == null) {
        throw AttachmentIntegrationException('Failed to decrypt file');
      }

      final fileData = await file.readAsBytes();

      // Create chunks for transmission
      return await _attachmentService.createChunks(
        fileId: attachmentId,
        data: fileData,
        recipientId: recipientId,
        metadata: {
          'filename': attachment.fileName,
          'mime_type': attachment.mimeType,
          'size_bytes': attachment.sizeBytes,
          'type': _getAttachmentTypeString(attachment.type),
        },
      );
    } catch (e) {
      throw AttachmentIntegrationException('Failed to create transmission chunks: $e');
    }
  }

  /// Reassemble file from received chunks
  Future<Uint8List?> reassembleFileFromChunks(List<AttachmentChunk> chunks) async {
    try {
      return await _attachmentService.reassembleFile(chunks);
    } catch (e) {
      throw AttachmentIntegrationException('Failed to reassemble file: $e');
    }
  }

  /// Create attachment from received file data
  Future<Attachment> createAttachmentFromReceivedData({
    required Message message,
    required Uint8List fileData,
    required String fileName,
    required String mimeType,
    Map<String, dynamic>? metadata,
    bool isEncrypted = true,
    Duration? expirationTime,
  }) async {
    try {
      // Create attachment using attachment service
      final attachment = await _attachmentService.pickAndProcessFile(
        messageId: message.id,
        senderId: message.senderId,
        fileData: fileData,
        fileName: fileName,
        mimeType: mimeType,
        isEncrypted: isEncrypted,
        expirationTime: expirationTime,
      );

      // Store attachment metadata in database
      final attachmentData = {
        'id': attachment.id,
        'message_id': attachment.messageId,
        'type': _getAttachmentTypeString(attachment.type),
        'file_name': attachment.fileName,
        'mime_type': attachment.mimeType,
        'size_bytes': attachment.sizeBytes,
        'file_path': attachment.filePath,
        'thumbnail': attachment.thumbnail?.toList(),
        'metadata': metadata != null ? jsonEncode(metadata) : null,
        'is_encrypted': attachment.isEncrypted ? 1 : 0,
        'encrypted_data': attachment.encryptedData,
        'created_at': attachment.createdAt.millisecondsSinceEpoch,
      };

      await _databaseService.insertAttachment(attachmentData);

      return attachment;
    } catch (e) {
      throw AttachmentIntegrationException('Failed to create attachment from received data: $e');
    }
  }

  /// Get storage statistics
  Future<AttachmentStats> getStorageStats() async {
    try {
      return await _attachmentService.getStorageStats();
    } catch (e) {
      throw AttachmentIntegrationException('Failed to get storage stats: $e');
    }
  }

  /// Clean up expired attachments
  Future<void> cleanupExpiredAttachments() async {
    try {
      await _attachmentService.cleanupExpiredFiles();
    } catch (e) {
      throw AttachmentIntegrationException('Failed to cleanup expired attachments: $e');
    }
  }

  /// Convert database attachment data to Attachment model
  Attachment _convertDatabaseToAttachment(Map<String, dynamic> data) {
    return Attachment(
      id: data['id'] as String,
      messageId: data['message_id'] as String,
      type: _parseAttachmentType(data['type'] as String),
      fileName: data['file_name'] as String,
      mimeType: data['mime_type'] as String,
      sizeBytes: data['size_bytes'] as int,
      filePath: data['file_path'] as String?,
      thumbnail: data['thumbnail'] != null 
          ? Uint8List.fromList(data['thumbnail'] as List<dynamic>) 
          : null,
      metadata: data['metadata'] != null 
          ? jsonDecode(data['metadata'] as String) as Map<String, dynamic>
          : null,
      isEncrypted: (data['is_encrypted'] as int) == 1,
      encryptedData: data['encrypted_data'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(data['created_at'] as int),
    );
  }

  /// Convert AttachmentType to string for database storage
  String _getAttachmentTypeString(AttachmentType type) {
    switch (type) {
      case AttachmentType.image:
        return 'image';
      case AttachmentType.audio:
        return 'audio';
      case AttachmentType.video:
        return 'video';
      case AttachmentType.document:
        return 'document';
      case AttachmentType.voice:
        return 'voice';
      case AttachmentType.file:
        return 'file';
    }
  }

  /// Parse attachment type from database string
  AttachmentType _parseAttachmentType(String typeString) {
    switch (typeString) {
      case 'image':
        return AttachmentType.image;
      case 'audio':
        return AttachmentType.audio;
      case 'video':
        return AttachmentType.video;
      case 'document':
        return AttachmentType.document;
      case 'voice':
        return AttachmentType.voice;
      case 'file':
      default:
        return AttachmentType.file;
    }
  }

  /// Dispose of all services
  void dispose() {
    _attachmentService.dispose();
  }
}

/// Exception class for attachment integration errors
class AttachmentIntegrationException implements Exception {
  final String message;
  AttachmentIntegrationException(this.message);

  @override
  String toString() => 'AttachmentIntegrationException: $message';
}