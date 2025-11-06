import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../services/integrated_attachment_service.dart';
import '../models/attachment_model.dart';
import '../models/message_model.dart';

/// Complete example showing how to use the integrated attachment service
/// with all the required dependencies (database, encryption, attachment handling)
class IntegrationExample {
  final IntegratedAttachmentService _attachmentService = IntegratedAttachmentService();

  /// Initialize all required services
  Future<void> initializeServices() async {
    try {
      await _attachmentService.initialize();
      print('All services initialized successfully');
    } catch (e) {
      print('Error initializing services: $e');
    }
  }

  /// Example: Complete attachment workflow - from file selection to storage to transmission
  Future<Attachment> completeAttachmentWorkflow({
    required String senderId,
    required String recipientId,
  }) async {
    try {
      // Step 1: Create a message
      final message = Message.create(
        senderId: senderId,
        recipientId: recipientId,
        content: 'Sending you a file',
        type: MessageType.file,
      );

      // Step 2: Pick a file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'txt'],
      );

      if (result == null || result.files.single.bytes == null) {
        throw Exception('No file selected');
      }

      final selectedFile = result.files.single;

      // Step 3: Process and store the attachment
      final attachment = await _attachmentService.createAttachment(
        message: message,
        pickedFile: selectedFile,
        isEncrypted: true,
        expirationTime: Duration(hours: 24), // Auto-delete after 24 hours
      );

      print('Attachment created: ${attachment.fileName}');
      print('Size: ${attachment.formattedSize}');
      print('Type: ${attachment.type.description}');
      print('Encrypted: ${attachment.isEncrypted}');

      return attachment;
    } catch (e) {
      print('Error in complete workflow: $e');
      rethrow;
    }
  }

  /// Example: LoRa transmission workflow
  Future<List<AttachmentChunk>> prepareFileForLoRaTransmission({
    required String attachmentId,
    required String recipientId,
  }) async {
    try {
      print('Preparing file for LoRa transmission...');

      // Create chunks for LoRa transmission
      final chunks = await _attachmentService.createTransmissionChunks(
        attachmentId: attachmentId,
        recipientId: recipientId,
      );

      print('File chunked into ${chunks.length} parts');
      print('Each chunk is ${chunks.first.data.length} bytes');

      // Here you would send each chunk via LoRa
      for (int i = 0; i < chunks.length; i++) {
        final chunk = chunks[i];
        print('Chunk $i/${chunks.length}: ${chunk.chunkId}');
        
        // Simulate sending chunk
        // await loRaTransport.sendChunk(chunk);
      }

      return chunks;
    } catch (e) {
      print('Error preparing LoRa transmission: $e');
      rethrow;
    }
  }

  /// Example: Receive and reassemble file from LoRa chunks
  Future<Attachment> receiveLoRaFile({
    required List<AttachmentChunk> receivedChunks,
    required Message message,
  }) async {
    try {
      print('Reassembling file from ${receivedChunks.length} chunks...');

      // Reassemble file data
      final fileData = await _attachmentService.reassembleFileFromChunks(receivedChunks);
      
      if (fileData == null) {
        throw Exception('Failed to reassemble file');
      }

      print('File reassembled: ${fileData.length} bytes');

      // Get metadata from first chunk
      final firstChunk = receivedChunks.first;
      final metadata = firstChunk.metadata;
      
      final fileName = metadata?['filename'] as String? ?? 'received_file';
      final mimeType = metadata?['mime_type'] as String? ?? 'application/octet-stream';

      // Create attachment from received data
      final attachment = await _attachmentService.createAttachmentFromReceivedData(
        message: message,
        fileData: fileData,
        fileName: fileName,
        mimeType: mimeType,
        metadata: metadata,
        isEncrypted: true,
      );

      print('Received file stored: ${attachment.fileName}');
      return attachment;
    } catch (e) {
      print('Error receiving LoRa file: $e');
      rethrow;
    }
  }

  /// Example: File management operations
  Future<void> fileManagementExample(String attachmentId) async {
    try {
      print('=== File Management Example ===');

      // Get storage statistics
      final stats = await _attachmentService.getStorageStats();
      print('Storage stats: ${stats.formattedSize} total, ${stats.fileCount} files');

      // Check if file is expired
      final isExpired = _attachmentService.isAttachmentExpired(attachmentId);
      print('File expired: $isExpired');

      // Download and open file
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/downloaded_file';
      
      final downloadedFile = await _attachmentService.downloadAttachment(
        attachmentId: attachmentId,
        savePath: tempPath,
        fileKey: Uint8List.fromList([]), // Use appropriate key
      );

      if (downloadedFile != null) {
        print('File downloaded to: ${downloadedFile.path}');
        
        // Open with system default app
        final attachment = await _attachmentService.getAttachment(attachmentId);
        if (attachment != null) {
          await _attachmentService.openAttachment(attachment);
          print('File opened successfully');
        }
      }

      // Set expiration (burn-after-read)
      await _attachmentService.setAttachmentExpiration(
        attachmentId,
        Duration(minutes: 30),
      );
      print('File expiration set to 30 minutes');

    } catch (e) {
      print('Error in file management: $e');
    }
  }

  /// Example: Get attachments for a message
  Future<List<Attachment>> getMessageAttachmentsExample(String messageId) async {
    try {
      print('Getting attachments for message: $messageId');
      
      final attachments = await _attachmentService.getMessageAttachments(messageId);
      
      print('Found ${attachments.length} attachments:');
      for (final attachment in attachments) {
        print('- ${attachment.fileName} (${attachment.formattedSize})');
        print('  Type: ${attachment.type.description}');
        print('  Encrypted: ${attachment.isEncrypted}');
        print('  Created: ${attachment.createdAt}');
      }
      
      return attachments;
    } catch (e) {
      print('Error getting message attachments: $e');
      return [];
    }
  }

  /// Example: Cleanup operations
  Future<void> cleanupExample() async {
    try {
      print('=== Cleanup Example ===');

      // Clean up expired attachments
      await _attachmentService.cleanupExpiredAttachments();
      print('Expired attachments cleaned up');

      // Get updated storage stats
      final stats = await _attachmentService.getStorageStats();
      print('Updated storage stats: ${stats.formattedSize} total, ${stats.fileCount} files');

    } catch (e) {
      print('Error in cleanup: $e');
    }
  }
}

/// Flutter widget example for complete attachment UI integration
class AttachmentIntegrationWidget extends StatefulWidget {
  final String currentUserId;
  final String recipientId;

  const AttachmentIntegrationWidget({
    super.key,
    required this.currentUserId,
    required this.recipientId,
  });

  @override
  State<AttachmentIntegrationWidget> createState() => _AttachmentIntegrationWidgetState();
}

class _AttachmentIntegrationWidgetState extends State<AttachmentIntegrationWidget> {
  final IntegratedAttachmentService _attachmentService = IntegratedAttachmentService();
  final IntegrationExample _example = IntegrationExample();
  
  List<Attachment> _attachments = [];
  bool _isLoading = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    setState(() => _isLoading = true);
    
    try {
      await _attachmentService.initialize();
      setState(() => _isInitialized = true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to initialize: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndSendFile() async {
    if (!_isInitialized) return;

    try {
      setState(() => _isLoading = true);

      final attachment = await _example.completeAttachmentWorkflow(
        senderId: widget.currentUserId,
        recipientId: widget.recipientId,
      );

      setState(() {
        _attachments.add(attachment);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File sent: ${attachment.fileName}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _prepareLoRaTransmission(Attachment attachment) async {
    try {
      setState(() => _isLoading = true);

      final chunks = await _example.prepareFileForLoRaTransmission(
        attachmentId: attachment.id,
        recipientId: widget.recipientId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File prepared for LoRa: ${chunks.length} chunks'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to prepare LoRa transmission: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openAttachment(Attachment attachment) async {
    try {
      await _attachmentService.openAttachment(attachment);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteAttachment(Attachment attachment) async {
    try {
      await _attachmentService.deleteAttachment(attachment.id);
      
      setState(() {
        _attachments.removeWhere((a) => a.id == attachment.id);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File deleted: ${attachment.fileName}'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Attachment Integration Demo'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _isLoading ? null : _initializeServices,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : !_isInitialized
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error, size: 64, color: Colors.red),
                      SizedBox(height: 16),
                      Text('Failed to initialize services'),
                      SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _initializeServices,
                        child: Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Action buttons
                    Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _pickAndSendFile,
                            icon: Icon(Icons.attach_file),
                            label: Text('Pick & Send File'),
                          ),
                          SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () => _example.cleanupExample(),
                            icon: Icon(Icons.cleaning_services),
                            label: Text('Cleanup'),
                          ),
                        ],
                      ),
                    ),

                    // Attachments list
                    Expanded(
                      child: _attachments.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.folder_open, size: 64, color: Colors.grey),
                                  SizedBox(height: 16),
                                  Text('No attachments yet'),
                                  SizedBox(height: 8),
                                  Text('Tap "Pick & Send File" to get started'),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: _attachments.length,
                              itemBuilder: (context, index) {
                                final attachment = _attachments[index];
                                return Card(
                                  margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                  child: ListTile(
                                    leading: _buildAttachmentIcon(attachment),
                                    title: Text(attachment.fileName),
                                    subtitle: Text(
                                      '${attachment.type.description} • ${attachment.formattedSize}',
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: Icon(Icons.send),
                                          onPressed: () => _prepareLoRaTransmission(attachment),
                                          tooltip: 'Prepare for LoRa',
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.open_in_new),
                                          onPressed: () => _openAttachment(attachment),
                                          tooltip: 'Open',
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.delete),
                                          onPressed: () => _deleteAttachment(attachment),
                                          tooltip: 'Delete',
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildAttachmentIcon(Attachment attachment) {
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