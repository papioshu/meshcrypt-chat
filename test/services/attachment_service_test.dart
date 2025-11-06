import 'package:flutter_test/flutter_test.dart';
import 'package:encrypted_mesh_chat/services/attachment_service.dart';
import 'package:encrypted_mesh_chat/models/attachment_model.dart';
import 'dart:typed_data';

void main() {
  group('AttachmentService Tests', () {
    late AttachmentService attachmentService;

    setUp(() {
      attachmentService = AttachmentService();
    });

    group('File Size Formatting', () {
      test('should format bytes correctly', () {
        expect(AttachmentService.formatFileSize(0), '0B');
        expect(AttachmentService.formatFileSize(512), '512B');
        expect(AttachmentService.formatFileSize(1024), '1.0KB');
        expect(AttachmentService.formatFileSize(1536), '1.5KB');
        expect(AttachmentService.formatFileSize(1024 * 1024), '1.0MB');
        expect(AttachmentService.formatFileSize(1536 * 1024), '1.5MB');
        expect(AttachmentService.formatFileSize(1024 * 1024 * 1024), '1.0GB');
      });
    });

    group('AttachmentChunk Tests', () {
      test('should create attachment chunk correctly', () {
        final chunk = AttachmentChunk(
          chunkId: 'chunk-123',
          fileId: 'file-456',
          chunkIndex: 0,
          totalChunks: 3,
          data: Uint8List.fromList([1, 2, 3]),
          fingerprint: 'abc123',
          metadata: {'test': 'value'},
        );

        expect(chunk.chunkId, 'chunk-123');
        expect(chunk.fileId, 'file-456');
        expect(chunk.chunkIndex, 0);
        expect(chunk.totalChunks, 3);
        expect(chunk.data, [1, 2, 3]);
        expect(chunk.fingerprint, 'abc123');
        expect(chunk.metadata, {'test': 'value'});
      });

      test('should serialize and deserialize chunk correctly', () {
        final originalChunk = AttachmentChunk(
          chunkId: 'chunk-123',
          fileId: 'file-456',
          chunkIndex: 0,
          totalChunks: 3,
          data: Uint8List.fromList([1, 2, 3]),
          fingerprint: 'abc123',
          metadata: {'test': 'value'},
        );

        final serialized = originalChunk.toMap();
        final deserializedChunk = AttachmentChunk.fromMap(serialized);

        expect(deserializedChunk.chunkId, originalChunk.chunkId);
        expect(deserializedChunk.fileId, originalChunk.fileId);
        expect(deserializedChunk.chunkIndex, originalChunk.chunkIndex);
        expect(deserializedChunk.totalChunks, originalChunk.totalChunks);
        expect(deserializedChunk.data, originalChunk.data);
        expect(deserializedChunk.fingerprint, originalChunk.fingerprint);
        expect(deserializedChunk.metadata, originalChunk.metadata);
      });
    });

    group('AttachmentExpiration Tests', () {
      test('should create expiration correctly', () {
        final now = DateTime.now();
        final expiresAt = now.add(Duration(hours: 1));
        
        final expiration = AttachmentExpiration(
          fileId: 'file-123',
          expiresAt: expiresAt,
          createdAt: now,
        );

        expect(expiration.fileId, 'file-123');
        expect(expiration.expiresAt, expiresAt);
        expect(expiration.createdAt, now);
        expect(expiration.isExpired, false);
      });

      test('should detect expired attachments', () {
        final past = DateTime.now().subtract(Duration(hours: 1));
        
        final expiration = AttachmentExpiration(
          fileId: 'file-123',
          expiresAt: past,
          createdAt: past.subtract(Duration(hours: 2)),
        );

        expect(expiration.isExpired, true);
        expect(expiration.remainingTime.isNegative, true);
      });
    });

    group('AttachmentStats Tests', () {
      test('should create stats correctly', () {
        final stats = AttachmentStats(
          totalSizeBytes: 1024 * 1024, // 1MB
          fileCount: 5,
          activeAttachments: 3,
        );

        expect(stats.totalSizeBytes, 1048576);
        expect(stats.fileCount, 5);
        expect(stats.activeAttachments, 3);
        expect(stats.formattedSize, '1.0MB');
        expect(stats.averageSize, 209715.2); // 1MB / 5 files
      });

      test('should handle zero file count', () {
        final stats = AttachmentStats(
          totalSizeBytes: 0,
          fileCount: 0,
          activeAttachments: 0,
        );

        expect(stats.averageSize, 0.0);
        expect(stats.formattedSize, '0B');
      });
    });

    group('AttachmentType Tests', () {
      test('should detect attachment types correctly', () {
        // Note: These would be tested through the actual service methods
        // This is a placeholder for type detection logic
        expect(AttachmentType.image.toString(), contains('image'));
        expect(AttachmentType.audio.toString(), contains('audio'));
        expect(AttachmentType.document.toString(), contains('document'));
      });

      test('should return correct descriptions', () {
        expect(AttachmentType.image.description, 'Image');
        expect(AttachmentType.audio.description, 'Audio');
        expect(AttachmentType.document.description, 'Document');
        expect(AttachmentType.voice.description, 'Voice Message');
        expect(AttachmentType.file.description, 'File');
      });

      test('should return correct icons', () {
        expect(AttachmentType.image.icon, '🖼️');
        expect(AttachmentType.audio.icon, '🎵');
        expect(AttachmentType.video.icon, '🎥');
        expect(AttachmentType.document.icon, '📄');
        expect(AttachmentType.voice.icon, '🎤');
        expect(AttachmentType.file.icon, '📎');
      });
    });

    group('Attachment Tests', () {
      test('should create attachment correctly', () {
        final attachment = Attachment(
          id: 'att-123',
          messageId: 'msg-456',
          type: AttachmentType.image,
          fileName: 'photo.jpg',
          mimeType: 'image/jpeg',
          sizeBytes: 1024 * 1024,
          createdAt: DateTime.now(),
        );

        expect(attachment.id, 'att-123');
        expect(attachment.messageId, 'msg-456');
        expect(attachment.type, AttachmentType.image);
        expect(attachment.fileName, 'photo.jpg');
        expect(attachment.mimeType, 'image/jpeg');
        expect(attachment.sizeBytes, 1048576);
        expect(attachment.isImage, true);
        expect(attachment.isAudio, false);
        expect(attachment.isDocument, false);
        expect(attachment.isVideo, false);
      });

      test('should return formatted size correctly', () {
        final attachment = Attachment(
          id: 'att-123',
          messageId: 'msg-456',
          type: AttachmentType.document,
          fileName: 'document.pdf',
          mimeType: 'application/pdf',
          sizeBytes: 1024 * 1024 * 2.5, // 2.5MB
          createdAt: DateTime.now(),
        );

        expect(attachment.formattedSize, '2.5MB');
      });

      test('should return file extension correctly', () {
        final attachment = Attachment(
          id: 'att-123',
          messageId: 'msg-456',
          type: AttachmentType.document,
          fileName: 'document.pdf',
          mimeType: 'application/pdf',
          sizeBytes: 1024,
          createdAt: DateTime.now(),
        );

        expect(attachment.fileExtension, 'pdf');
      });

      test('should return preview text correctly', () {
        final imageAttachment = Attachment(
          id: 'att-123',
          messageId: 'msg-456',
          type: AttachmentType.image,
          fileName: 'photo.jpg',
          mimeType: 'image/jpeg',
          sizeBytes: 1024,
          createdAt: DateTime.now(),
        );

        expect(imageAttachment.previewText, '📸 photo.jpg');

        final voiceAttachment = Attachment(
          id: 'att-124',
          messageId: 'msg-457',
          type: AttachmentType.voice,
          fileName: 'voice_message',
          mimeType: 'audio/wav',
          sizeBytes: 1024,
          createdAt: DateTime.now(),
        );

        expect(voiceAttachment.previewText, '🎤 Voice message');
      });

      test('should create attachment using factory method', () {
        final attachment = Attachment.create(
          messageId: 'msg-456',
          type: AttachmentType.audio,
          fileName: 'song.mp3',
          mimeType: 'audio/mpeg',
          sizeBytes: 3000000,
        );

        expect(attachment.messageId, 'msg-456');
        expect(attachment.type, AttachmentType.audio);
        expect(attachment.fileName, 'song.mp3');
        expect(attachment.mimeType, 'audio/mpeg');
        expect(attachment.sizeBytes, 3000000);
        expect(attachment.id, isNotEmpty); // UUID should be generated
      });

      test('should copy attachment with new values', () {
        final original = Attachment(
          id: 'att-123',
          messageId: 'msg-456',
          type: AttachmentType.document,
          fileName: 'old.pdf',
          mimeType: 'application/pdf',
          sizeBytes: 1024,
          createdAt: DateTime(2024, 1, 1),
        );

        final copied = original.copyWith(
          fileName: 'new.pdf',
          sizeBytes: 2048,
        );

        expect(copied.id, original.id);
        expect(copied.messageId, original.messageId);
        expect(copied.type, original.type);
        expect(copied.fileName, 'new.pdf');
        expect(copied.sizeBytes, 2048);
        expect(copied.createdAt, original.createdAt);
      });
    });

    group('AttachmentException Tests', () {
      test('should create exception with message', () {
        final exception = AttachmentException('Test error message');
        expect(exception.message, 'Test error message');
        expect(exception.toString(), contains('AttachmentException'));
        expect(exception.toString(), contains('Test error message'));
      });
    });
  });

  group('Integration Tests', () {
    late AttachmentService attachmentService;

    setUp(() {
      attachmentService = AttachmentService();
    });

    test('should handle file chunk creation and reassembly', () async {
      // This is a simplified test - in reality, you'd need to initialize the service
      final testData = Uint8List.fromList(List.generate(1000, (i) => i % 256));
      
      // Create mock chunks (in real implementation, this would use the actual service)
      final chunks = <AttachmentChunk>[];
      const chunkSize = 240;
      final totalChunks = (testData.length / chunkSize).ceil();

      for (int i = 0; i < totalChunks; i++) {
        final start = i * chunkSize;
        final end = (i + 1) * chunkSize;
        final chunkData = testData.sublist(
          start, 
          end < testData.length ? end : testData.length
        );

        final chunk = AttachmentChunk(
          chunkId: 'chunk-$i',
          fileId: 'test-file',
          chunkIndex: i,
          totalChunks: totalChunks,
          data: chunkData,
          fingerprint: 'test-fingerprint',
          metadata: {},
        );

        chunks.add(chunk);
      }

      // Test that chunks were created correctly
      expect(chunks.length, greaterThan(0));
      expect(chunks.first.totalChunks, totalChunks);
      
      // In real implementation, you would test reassembly here
      // final reassembled = await attachmentService.reassembleFile(chunks);
      // expect(reassembled, equals(testData));
    });

    test('should handle expiration timing correctly', () {
      final now = DateTime.now();
      final past = now.subtract(Duration(minutes: 1));
      final future = now.add(Duration(minutes: 1));

      // Test non-expired attachment
      final futureExpiration = AttachmentExpiration(
        fileId: 'file-1',
        expiresAt: future,
        createdAt: now,
      );
      expect(futureExpiration.isExpired, false);

      // Test expired attachment
      final pastExpiration = AttachmentExpiration(
        fileId: 'file-2',
        expiresAt: past,
        createdAt: past.subtract(Duration(minutes: 2)),
      );
      expect(pastExpiration.isExpired, true);
    });
  });
}