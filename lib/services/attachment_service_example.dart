import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../services/attachment_service.dart';
import '../models/attachment_model.dart';
import 'encryption_service.dart';

/// Example usage of the AttachmentService
class AttachmentServiceExample {
  final AttachmentService _attachmentService = AttachmentService();
  final EncryptionService _encryptionService = EncryptionService();

  /// Example: Initialize the service
  Future<void> initializeExample() async {
    await _attachmentService.initialize(
      encryptionService: _encryptionService,
    );
  }

  /// Example: Pick and process a file
  Future<Attachment?> pickFileExample(String messageId, String senderId) async {
    try {
      // Pick a file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'pdf', 'txt', 'doc', 'docx'],
      );

      if (result != null && result.files.single.bytes != null) {
        final file = result.files.single;
        
        // Process the file with encryption
        final attachment = await _attachmentService.pickAndProcessFile(
          messageId: messageId,
          senderId: senderId,
          pickedFile: file,
          isEncrypted: true,
          expirationTime: Duration(hours: 24), // Auto-delete after 24 hours
        );

        print('File processed successfully: ${attachment.fileName}');
        print('File size: ${attachment.formattedSize}');
        print('File type: ${attachment.type}');
        
        return attachment;
      }
    } catch (e) {
      print('Error processing file: $e');
    }
    return null;
  }

  /// Example: Chunk a file for LoRa transmission
  Future<List<AttachmentChunk>> chunkFileForTransmission({
    required Attachment attachment,
    required String recipientId,
  }) async {
    try {
      // Download and decrypt the file
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/${attachment.fileName}';
      
      final file = await _attachmentService.downloadAndDecrypt(
        fileId: attachment.id,
        savePath: tempPath,
        fileKey: Uint8List.fromList([]), // Use appropriate key
      );

      if (file == null) throw Exception('Failed to decrypt file');

      final fileData = await file.readAsBytes();
      
      // Create chunks for transmission
      final chunks = await _attachmentService.createChunks(
        fileId: attachment.id,
        data: fileData,
        recipientId: recipientId,
        metadata: {
          'filename': attachment.fileName,
          'mime_type': attachment.mimeType,
          'size_bytes': attachment.sizeBytes,
        },
      );

      print('File chunked into ${chunks.length} parts for LoRa transmission');
      return chunks;
    } catch (e) {
      print('Error chunking file: $e');
      return [];
    }
  }

  /// Example: Reassemble file from received chunks
  Future<Uint8List?> reassembleFileFromChunks(List<AttachmentChunk> chunks) async {
    try {
      final data = await _attachmentService.reassembleFile(chunks);
      if (data != null) {
        print('File reassembled successfully. Size: ${data.length} bytes');
      }
      return data;
    } catch (e) {
      print('Error reassembling file: $e');
      return null;
    }
  }

  /// Example: Generate file preview
  Future<String?> generatePreviewExample(Attachment attachment) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/${attachment.fileName}';
      
      final file = await _attachmentService.downloadAndDecrypt(
        fileId: attachment.id,
        savePath: tempPath,
        fileKey: Uint8List.fromList([]), // Use appropriate key
      );

      if (file == null) return null;

      final fileData = await file.readAsBytes();
      
      String? preview;
      if (attachment.isDocument) {
        preview = await AttachmentService.generateDocumentPreview(
          fileData, 
          attachment.mimeType,
        );
      }
      // For images, the thumbnail is already available in attachment.thumbnail
      
      return preview;
    } catch (e) {
      print('Error generating preview: $e');
      return null;
    }
  }

  /// Example: Open attachment with system default app
  Future<void> openAttachmentExample(Attachment attachment) async {
    try {
      await _attachmentService.openAttachment(attachment);
      print('File opened successfully');
    } catch (e) {
      print('Error opening file: $e');
    }
  }

  /// Example: Set file expiration (burn-after-read)
  Future<void> setExpirationExample(String fileId) async {
    try {
      await _attachmentService.setExpiration(
        fileId, 
        Duration(minutes: 30), // Expires in 30 minutes
      );
      print('File expiration set successfully');
    } catch (e) {
      print('Error setting expiration: $e');
    }
  }

  /// Example: Check if file is expired
  bool checkExpirationExample(String fileId) {
    return _attachmentService.isExpired(fileId);
  }

  /// Example: Delete attachment
  Future<void> deleteAttachmentExample(String fileId) async {
    try {
      await _attachmentService.deleteAttachment(fileId);
      print('Attachment deleted successfully');
    } catch (e) {
      print('Error deleting attachment: $e');
    }
  }

  /// Example: Get storage statistics
  Future<void> getStorageStatsExample() async {
    try {
      final stats = await _attachmentService.getStorageStats();
      print('Storage Statistics:');
      print('Total size: ${stats.formattedSize}');
      print('File count: ${stats.fileCount}');
      print('Active attachments: ${stats.activeAttachments}');
      print('Average file size: ${AttachmentService.formatFileSize(stats.averageSize.round())}');
    } catch (e) {
      print('Error getting storage stats: $e');
    }
  }

  /// Example: Clear all attachments
  Future<void> clearAllAttachmentsExample() async {
    try {
      await _attachmentService.clearAllAttachments();
      print('All attachments cleared successfully');
    } catch (e) {
      print('Error clearing attachments: $e');
    }
  }
}

/// Flutter widget example for file picker integration
class FileAttachmentWidget extends StatefulWidget {
  final String messageId;
  final String senderId;
  final Function(Attachment) onAttachmentAdded;

  const FileAttachmentWidget({
    super.key,
    required this.messageId,
    required this.senderId,
    required this.onAttachmentAdded,
  });

  @override
  State<FileAttachmentWidget> createState() => _FileAttachmentWidgetState();
}

class _FileAttachmentWidgetState extends State<FileAttachmentWidget> {
  final AttachmentService _attachmentService = AttachmentService();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _attachmentService.initialize();
  }

  Future<void> _pickAndProcessFile() async {
    setState(() => _isProcessing = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'pdf', 'txt', 'doc', 'docx'],
      );

      if (result != null && result.files.single.bytes != null) {
        final file = result.files.single;
        
        final attachment = await _attachmentService.pickAndProcessFile(
          messageId: widget.messageId,
          senderId: widget.senderId,
          pickedFile: file,
          isEncrypted: true,
          expirationTime: Duration(hours: 24),
        );

        widget.onAttachmentAdded(attachment);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('File "${attachment.fileName}" added successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: _isProcessing ? null : _pickAndProcessFile,
      icon: _isProcessing
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.attach_file),
      label: Text(_isProcessing ? 'Processing...' : 'Attach File'),
    );
  }
}

/// Flutter widget example for attachment preview
class AttachmentPreviewWidget extends StatelessWidget {
  final Attachment attachment;
  final VoidCallback? onOpen;
  final VoidCallback? onDelete;

  const AttachmentPreviewWidget({
    super.key,
    required this.attachment,
    this.onOpen,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: _buildPreviewIcon(),
        title: Text(attachment.fileName),
        subtitle: Text('${attachment.type.description} • ${attachment.formattedSize}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onOpen != null)
              IconButton(
                icon: Icon(Icons.open_in_new),
                onPressed: onOpen,
              ),
            if (onDelete != null)
              IconButton(
                icon: Icon(Icons.delete),
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewIcon() {
    if (attachment.isImage && attachment.thumbnail != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.memory(
          attachment.thumbnail!,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
        ),
      );
    }
    return Icon(
      _getIconForType(attachment.type),
      size: 40,
      color: Colors.blue,
    );
  }

  IconData _getIconForType(AttachmentType type) {
    switch (type) {
      case AttachmentType.image:
        return Icons.image;
      case AttachmentType.audio:
        return Icons.audiotrack;
      case AttachmentType.video:
        return Icons.videocam;
      case AttachmentType.document:
        return Icons.description;
      case AttachmentType.voice:
        return Icons.mic;
      case AttachmentType.file:
        return Icons.attach_file;
    }
  }
}