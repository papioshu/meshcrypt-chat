import 'package:uuid/uuid.dart';
import 'package:json_annotation/json_annotation.dart';
import 'dart:typed_data';

part 'attachment_model.g.dart';

@JsonSerializable()
class Attachment {
  final String id;
  final String messageId;
  final AttachmentType type;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final String? filePath;
  final Uint8List? thumbnail;
  final Map<String, dynamic>? metadata;
  final bool isEncrypted;
  final String? encryptedData;
  final DateTime createdAt;

  const Attachment({
    required this.id,
    required this.messageId,
    required this.type,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    this.filePath,
    this.thumbnail,
    this.metadata,
    this.isEncrypted = false,
    this.encryptedData,
    required this.createdAt,
  });

  factory Attachment.create({
    required String messageId,
    required AttachmentType type,
    required String fileName,
    required String mimeType,
    required int sizeBytes,
    String? filePath,
    Map<String, dynamic>? metadata,
    bool isEncrypted = false,
  }) {
    return Attachment(
      id: const Uuid().v4(),
      messageId: messageId,
      type: type,
      fileName: fileName,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      filePath: filePath,
      metadata: metadata,
      isEncrypted: isEncrypted,
      createdAt: DateTime.now(),
    );
  }

  factory Attachment.fromJson(Map<String, dynamic> json) => _$AttachmentFromJson(json);
  Map<String, dynamic> toJson() => _$AttachmentToJson(this);

  Attachment copyWith({
    String? id,
    String? messageId,
    AttachmentType? type,
    String? fileName,
    String? mimeType,
    int? sizeBytes,
    String? filePath,
    Uint8List? thumbnail,
    Map<String, dynamic>? metadata,
    bool? isEncrypted,
    String? encryptedData,
    DateTime? createdAt,
  }) {
    return Attachment(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      type: type ?? this.type,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      filePath: filePath ?? this.filePath,
      thumbnail: thumbnail ?? this.thumbnail,
      metadata: metadata ?? this.metadata,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      encryptedData: encryptedData ?? this.encryptedData,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // Get human readable file size
  String get formattedSize {
    if (sizeBytes < 1024) return '${sizeBytes}B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)}KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  // Get file extension
  String get fileExtension {
    final parts = fileName.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  // Check if it's an image
  bool get isImage => type == AttachmentType.image;

  // Check if it's audio
  bool get isAudio => type == AttachmentType.audio;

  // Check if it's a document
  bool get isDocument => type == AttachmentType.document;

  // Check if it's a video
  bool get isVideo => type == AttachmentType.video;

  // Check if it's a voice message
  bool get isVoiceMessage => type == AttachmentType.voice;

  // Get preview text for file sharing
  String get previewText {
    switch (type) {
      case AttachmentType.image:
        return '📸 $fileName';
      case AttachmentType.audio:
        return '🎵 $fileName';
      case AttachmentType.video:
        return '🎥 $fileName';
      case AttachmentType.document:
        return '📄 $fileName';
      case AttachmentType.voice:
        return '🎤 Voice message';
      default:
        return '📎 $fileName';
    }
  }

  @override
  String toString() {
    return 'Attachment(id: $id, messageId: $messageId, type: $type, fileName: $fileName, sizeBytes: $sizeBytes, isEncrypted: $isEncrypted)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Attachment && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

enum AttachmentType {
  @JsonValue('image')
  image,
  @JsonValue('audio')
  audio,
  @JsonValue('video')
  video,
  @JsonValue('document')
  document,
  @JsonValue('voice')
  voice,
  @JsonValue('file')
  file,
}

// Extension for AttachmentType
extension AttachmentTypeExtension on AttachmentType {
  String get description {
    switch (this) {
      case AttachmentType.image:
        return 'Image';
      case AttachmentType.audio:
        return 'Audio';
      case AttachmentType.video:
        return 'Video';
      case AttachmentType.document:
        return 'Document';
      case AttachmentType.voice:
        return 'Voice Message';
      case AttachmentType.file:
        return 'File';
    }
  }

  String get icon {
    switch (this) {
      case AttachmentType.image:
        return '🖼️';
      case AttachmentType.audio:
        return '🎵';
      case AttachmentType.video:
        return '🎥';
      case AttachmentType.document:
        return '📄';
      case AttachmentType.voice:
        return '🎤';
      case AttachmentType.file:
        return '📎';
    }
  }
}