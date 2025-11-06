# Attachment Service

A comprehensive encrypted attachment system for secure file sharing in mesh networking applications, with support for LoRa transmission, file chunking, and burn-after-read functionality.

## Features

### 🔐 **Encryption & Security**
- **End-to-end encryption** using AES-256-GCM via EncryptionService
- **Secure file storage** with encrypted local storage
- **Burn-after-read support** with automatic file expiration
- **File integrity verification** using SHA-256 checksums
- **Secure key management** using FlutterSecureStorage

### 📡 **LoRa Transmission Support**
- **File chunking** for LoRa packet size limits (240 bytes chunks)
- **Chunk reassembly** with integrity verification
- **Metadata preservation** during transmission
- **Retry handling** for reliable delivery

### 📁 **File Type Support**
- **Images**: JPEG, PNG, GIF, WebP, BMP
- **Audio**: MP3, WAV, OGG, M4A, AAC, FLAC
- **Video**: MP4, AVI, MOV, WMV, FLV, WebM
- **Documents**: PDF, TXT, DOC, DOCX, XLS, XLSX, PPT, PPTX

### 🖼️ **File Previews**
- **Automatic thumbnail generation** for images (200x200px)
- **Document preview** for text files (first 5 lines)
- **File metadata display** with formatted sizes
- **Type-specific icons** and descriptions

### 🔄 **File Management**
- **Secure download and decryption**
- **System integration** for opening files with default apps
- **Storage statistics** and cleanup utilities
- **Cross-platform support** (Android, iOS, Desktop)

## Installation

1. **Add dependencies** to `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  # ... existing dependencies
  
  # New dependencies for Attachment Service
  share_plus: ^7.2.1
  url_launcher: ^6.2.2
  mime: ^1.0.4
  image: ^4.1.7
```

2. **Import the service**:

```dart
import 'package:encrypted_mesh_chat/services/attachment_service.dart';
```

## Usage

### Initialize the Service

```dart
final attachmentService = AttachmentService();

await attachmentService.initialize(
  encryptionService: encryptionService,
  secureStorage: secureStorage,
);
```

### Pick and Process Files

```dart
// Pick a file and encrypt it
final attachment = await attachmentService.pickAndProcessFile(
  messageId: 'message-123',
  senderId: 'user-456',
  pickedFile: selectedFile,
  isEncrypted: true,
  expirationTime: Duration(hours: 24), // Auto-delete after 24 hours
);
```

### File Chunking for LoRa

```dart
// Chunk file for transmission
final chunks = await attachmentService.createChunks(
  fileId: attachment.id,
  data: fileData,
  recipientId: 'recipient-789',
  metadata: {
    'filename': attachment.fileName,
    'mime_type': attachment.mimeType,
  },
);

// Reassemble on receiver side
final reassembledData = await attachmentService.reassembleFile(receivedChunks);
```

### File Previews

```dart
// Generate image thumbnail
if (attachment.isImage && attachment.thumbnail != null) {
  // Use thumbnail data
  Image.memory(attachment.thumbnail!);
}

// Generate document preview
final preview = await attachmentService.generateDocumentPreview(
  fileData, 
  attachment.mimeType,
);
```

### Download and Open Files

```dart
// Download and decrypt file
final file = await attachmentService.downloadAndDecrypt(
  fileId: attachment.id,
  savePath: '/path/to/save/file.pdf',
  fileKey: decryptionKey,
);

// Open with system default app
await attachmentService.openAttachment(attachment);
```

### Expiration and Burn-After-Read

```dart
// Set expiration (burn-after-read)
await attachmentService.setExpiration(
  fileId, 
  Duration(minutes: 30),
);

// Check if expired
bool expired = attachmentService.isExpired(fileId);

// Automatically clean up expired files
await attachmentService.cleanupExpiredFiles();
```

### File Management

```dart
// Get storage statistics
final stats = await attachmentService.getStorageStats();
print('Total size: ${stats.formattedSize}');
print('File count: ${stats.fileCount}');

// Delete single attachment
await attachmentService.deleteAttachment(fileId);

// Clear all attachments (use with caution)
await attachmentService.clearAllAttachments();
```

## API Reference

### Core Methods

#### `initialize({EncryptionService?, FlutterSecureStorage?})`
Initialize the attachment service with dependencies.

#### `pickAndProcessFile(...)`
Pick and encrypt a file for secure storage.

#### `createChunks(...)`
Chunk file data for LoRa transmission.

#### `reassembleFile(List<AttachmentChunk>)`
Reassemble file from transmitted chunks.

#### `downloadAndDecrypt(...)`
Download and decrypt attachment.

#### `openAttachment(Attachment)`
Open attachment with system default app.

#### `setExpiration(String, Duration)`
Set file expiration time.

#### `deleteAttachment(String)`
Delete attachment and clean up.

### Utility Methods

#### `formatFileSize(int bytes)`
Format bytes into human readable string.

#### `getStorageStats()`
Get storage usage statistics.

#### `isExpired(String)`
Check if attachment has expired.

## Data Models

### Attachment
```dart
class Attachment {
  final String id;
  final String messageId;
  final AttachmentType type;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final Uint8List? thumbnail;
  final bool isEncrypted;
  final DateTime createdAt;
  // ... additional fields
}
```

### AttachmentChunk
```dart
class AttachmentChunk {
  final String chunkId;
  final String fileId;
  final int chunkIndex;
  final int totalChunks;
  final Uint8List data;
  final String fingerprint;
  final Map<String, dynamic> metadata;
}
```

### AttachmentStats
```dart
class AttachmentStats {
  final int totalSizeBytes;
  final int fileCount;
  final int activeAttachments;
  
  String get formattedSize;
  double get averageSize;
}
```

## Configuration

### File Size Limits
- **Maximum file size**: 50MB (configurable via `_maxFileSize`)
- **LoRa chunk size**: 240 bytes (configurable via `_chunkSize`)

### Supported File Types
- **Images**: JPEG, PNG, GIF, WebP, BMP
- **Audio**: MP3, WAV, OGG, M4A, AAC, FLAC
- **Video**: MP4, AVI, MOV, WMV, FLV, WebM
- **Documents**: PDF, TXT, DOC, DOCX, XLS, XLSX, PPT, PPTX

### Expiration Settings
- **Expiration check interval**: 1 hour (configurable via `_expirationCheckInterval`)
- **Preview cache expiry**: 7 days (configurable via `_previewExpiry`)

## Error Handling

The service uses `AttachmentException` for all error handling:

```dart
try {
  final attachment = await attachmentService.pickAndProcessFile(...);
} catch (e) {
  if (e is AttachmentException) {
    print('Attachment error: ${e.message}');
  }
}
```

## Security Considerations

### Encryption
- Files are encrypted using AES-256-GCM
- Each file gets a unique encryption key
- Keys are stored securely using FlutterSecureStorage
- Integrity verification using HMAC

### Storage
- Files are stored encrypted in application documents directory
- Metadata is stored in secure storage
- Automatic cleanup of expired files
- File system permissions properly handled

### Transmission
- Files are chunked for LoRa transmission
- Chunk integrity verification using SHA-256
- Metadata preservation during transmission
- Graceful handling of missing chunks

## Platform Support

### Android
- Full support for all features
- Uses Android-specific file operations
- Permissions: READ_EXTERNAL_STORAGE, WRITE_EXTERNAL_STORAGE

### iOS
- Full support for all features
- Uses iOS-specific file operations
- Permissions: NSPhotoLibraryUsageDescription

### Desktop (Windows, macOS, Linux)
- Full support for all features
- Uses desktop file operations
- No special permissions required

## Integration with Other Services

### EncryptionService
```dart
// Initialize with existing EncryptionService
await attachmentService.initialize(
  encryptionService: encryptionService,
);
```

### StorageService
```dart
// Integrate with existing StorageService for metadata
final metadata = await storageService.storeAttachment(...);
```

### LoRa Transport
```dart
// Use chunks for LoRa transmission
final chunks = await attachmentService.createChunks(...);
await loRaTransport.sendChunks(chunks);
```

## Testing

Run the included examples:

```dart
final example = AttachmentServiceExample();
await example.initializeExample();
await example.pickFileExample('message-123', 'user-456');
```

## Best Practices

1. **Always initialize** the service before use
2. **Handle exceptions** properly with try-catch blocks
3. **Check file types** before processing
4. **Set appropriate expiration** times for sensitive files
5. **Clean up resources** by calling `dispose()` when done
6. **Use secure file keys** for encryption/decryption
7. **Validate chunk integrity** during reassembly

## Contributing

When contributing to the Attachment Service:

1. Maintain encryption standards
2. Add tests for new features
3. Update documentation
4. Follow Dart coding standards
5. Test on all supported platforms

## License

Part of the Encrypted Mesh Chat application.