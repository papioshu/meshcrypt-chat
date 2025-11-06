import 'package:uuid/uuid.dart';
import 'package:json_annotation/json_annotation.dart';

part 'message_model.g.dart';

@JsonSerializable()
class Message {
  final String id;
  final String senderId;
  final String recipientId;
  final String content;
  final MessageType type;
  final DateTime timestamp;
  final bool isEncrypted;
  final String? encryptedContent;
  final MessageStatus status;
  final Map<String, dynamic>? metadata;
  final List<String>? attachments;
  final bool? burnAfterRead;
  final DateTime? expiresAt;
  final bool isExpired;
  final bool isRead;
  final String? parentMessageId;
  final List<String>? groupMemberIds;

  const Message({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.content,
    required this.type,
    required this.timestamp,
    this.isEncrypted = true,
    this.encryptedContent,
    this.status = MessageStatus.pending,
    this.metadata,
    this.attachments,
    this.burnAfterRead,
    this.expiresAt,
    this.isExpired = false,
    this.isRead = false,
    this.parentMessageId,
    this.groupMemberIds,
  });

  factory Message.create({
    required String senderId,
    required String recipientId,
    required String content,
    MessageType type = MessageType.text,
    Map<String, dynamic>? metadata,
    List<String>? attachments,
    bool? burnAfterRead,
    Duration? expiresIn,
    List<String>? groupMemberIds,
    String? parentMessageId,
  }) {
    DateTime? expiresAt;
    if (expiresIn != null) {
      expiresAt = DateTime.now().add(expiresIn);
    }
    
    return Message(
      id: const Uuid().v4(),
      senderId: senderId,
      recipientId: recipientId,
      content: content,
      type: type,
      timestamp: DateTime.now(),
      metadata: metadata,
      attachments: attachments,
      burnAfterRead: burnAfterRead,
      expiresAt: expiresAt,
      groupMemberIds: groupMemberIds,
      parentMessageId: parentMessageId,
    );
  }

  factory Message.fromJson(Map<String, dynamic> json) => _$MessageFromJson(json);
  Map<String, dynamic> toJson() => _$MessageToJson(this);

  Message copyWith({
    String? id,
    String? senderId,
    String? recipientId,
    String? content,
    MessageType? type,
    DateTime? timestamp,
    bool? isEncrypted,
    String? encryptedContent,
    MessageStatus? status,
    Map<String, dynamic>? metadata,
    List<String>? attachments,
    bool? burnAfterRead,
    DateTime? expiresAt,
    bool? isExpired,
    bool? isRead,
    String? parentMessageId,
    List<String>? groupMemberIds,
  }) {
    return Message(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      recipientId: recipientId ?? this.recipientId,
      content: content ?? this.content,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      encryptedContent: encryptedContent ?? this.encryptedContent,
      status: status ?? this.status,
      metadata: metadata ?? this.metadata,
      attachments: attachments ?? this.attachments,
      burnAfterRead: burnAfterRead ?? this.burnAfterRead,
      expiresAt: expiresAt ?? this.expiresAt,
      isExpired: isExpired ?? this.isExpired,
      isRead: isRead ?? this.isRead,
      parentMessageId: parentMessageId ?? this.parentMessageId,
      groupMemberIds: groupMemberIds ?? this.groupMemberIds,
    );
  }

  @override
  String toString() {
    return 'Message(id: $id, senderId: $senderId, recipientId: $recipientId, content: ${content.substring(0, content.length > 50 ? 50 : content.length)}${content.length > 50 ? '...' : ''}, type: $type, timestamp: $timestamp, status: $status)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Message && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

enum MessageType {
  @JsonValue('text')
  text,
  @JsonValue('image')
  image,
  @JsonValue('file')
  file,
  @JsonValue('voice')
  voice,
  @JsonValue('location')
  location,
  @JsonValue('contact')
  contact,
  @JsonValue('system')
  system,
}

enum MessageStatus {
  @JsonValue('pending')
  pending,
  @JsonValue('sent')
  sent,
  @JsonValue('delivered')
  delivered,
  @JsonValue('read')
  read,
  @JsonValue('burned')
  burned,
  @JsonValue('failed')
  failed,
}