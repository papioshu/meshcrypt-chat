import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:json_annotation/json_annotation.dart';

part 'contact_model.g.dart';

@JsonSerializable()
class Contact {
  final String id;
  final String name;
  final String? publicKey;
  final String? bluetoothId;
  final ContactStatus status;
  final DateTime lastSeen;
  final DateTime createdAt;
  final String? avatarUrl;
  final Map<String, dynamic>? metadata;
  final bool isBlocked;
  final String? nickname;
  final int messageCount;

  const Contact({
    required this.id,
    required this.name,
    this.publicKey,
    this.bluetoothId,
    this.status = ContactStatus.offline,
    required this.lastSeen,
    required this.createdAt,
    this.avatarUrl,
    this.metadata,
    this.isBlocked = false,
    this.nickname,
    this.messageCount = 0,
  });

  factory Contact.create({
    required String name,
    String? publicKey,
    String? bluetoothId,
    Map<String, dynamic>? metadata,
    String? avatarUrl,
  }) {
    final now = DateTime.now();
    return Contact(
      id: const Uuid().v4(),
      name: name,
      publicKey: publicKey,
      bluetoothId: bluetoothId,
      lastSeen: now,
      createdAt: now,
      avatarUrl: avatarUrl,
      metadata: metadata,
    );
  }

  factory Contact.fromJson(Map<String, dynamic> json) => _$ContactFromJson(json);
  Map<String, dynamic> toJson() => _$ContactToJson(this);

  Contact copyWith({
    String? id,
    String? name,
    String? publicKey,
    String? bluetoothId,
    ContactStatus? status,
    DateTime? lastSeen,
    DateTime? createdAt,
    String? avatarUrl,
    Map<String, dynamic>? metadata,
    bool? isBlocked,
    String? nickname,
    int? messageCount,
  }) {
    return Contact(
      id: id ?? this.id,
      name: name ?? this.name,
      publicKey: publicKey ?? this.publicKey,
      bluetoothId: bluetoothId ?? this.bluetoothId,
      status: status ?? this.status,
      lastSeen: lastSeen ?? this.lastSeen,
      createdAt: createdAt ?? this.createdAt,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      metadata: metadata ?? this.metadata,
      isBlocked: isBlocked ?? this.isBlocked,
      nickname: nickname ?? this.nickname,
      messageCount: messageCount ?? this.messageCount,
    );
  }

  // Get display name (nickname if available, otherwise name)
  String get displayName => nickname ?? name;

  // Check if contact is online
  bool get isOnline => status == ContactStatus.online;

  // Check if contact is available for messaging
  bool get isAvailableForMessage => !isBlocked && 
      (status == ContactStatus.online || status == ContactStatus.nearby);

  @override
  String toString() {
    return 'Contact(id: $id, name: $name, displayName: ${displayName}, status: $status, isBlocked: $isBlocked, messageCount: $messageCount)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Contact && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

enum ContactStatus {
  @JsonValue('online')
  online,
  @JsonValue('offline')
  offline,
  @JsonValue('away')
  away,
  @JsonValue('busy')
  busy,
  @JsonValue('nearby')
  nearby,
  @JsonValue('connecting')
  connecting,
}

// Extension for ContactStatus
extension ContactStatusExtension on ContactStatus {
  String get description {
    switch (this) {
      case ContactStatus.online:
        return 'Online';
      case ContactStatus.offline:
        return 'Offline';
      case ContactStatus.away:
        return 'Away';
      case ContactStatus.busy:
        return 'Busy';
      case ContactStatus.nearby:
        return 'Nearby';
      case ContactStatus.connecting:
        return 'Connecting';
    }
  }

  Color get color {
    switch (this) {
      case ContactStatus.online:
        return Colors.green;
      case ContactStatus.offline:
        return Colors.grey;
      case ContactStatus.away:
        return Colors.orange;
      case ContactStatus.busy:
        return Colors.red;
      case ContactStatus.nearby:
        return Colors.blue;
      case ContactStatus.connecting:
        return Colors.yellow;
    }
  }
}