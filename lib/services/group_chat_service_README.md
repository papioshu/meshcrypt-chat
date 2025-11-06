# Group Chat Service Documentation

The Group Chat Service provides secure group messaging with shared symmetric keys, implementing end-to-end encryption for multi-party communications across all transport layers.

## Features

### 🔐 Security
- **Group Key Generation**: Unique symmetric keys for each group using HKDF
- **Member Invitation**: Secure key distribution using Curve25519 key exchange
- **End-to-End Encryption**: AES-256-GCM encryption for all group messages
- **Key Rotation**: Admin-controlled rotation of group symmetric keys
- **Invitation Expiration**: Time-limited invitations (24 hours default)

### 👥 Group Management
- **Member Management**: Add/remove members with role-based permissions
- **Admin Controls**: Admin role for group management operations
- **Group Metadata**: Flexible metadata storage and synchronization
- **Auto Cleanup**: Automatic group cleanup when all members leave

### 📡 Transport Integration
- **Multi-Transport Support**: Works with BLE, LibP2P, and LoRa transports
- **Broadcast Messaging**: Efficient group broadcasts via TransportManager
- **Fallback Handling**: Automatic failover across transport layers
- **Message Queuing**: Reliable message delivery with retries

### 💾 Data Management
- **Secure Storage**: Group keys and metadata in FlutterSecureStorage
- **Synchronization**: Automatic group state synchronization across devices
- **Member Tracking**: Active/inactive member status management
- **Invitation Management**: Pending invitation tracking and cleanup

## Quick Start

### Basic Setup

```dart
import 'package:flutter/material.dart';
import '../services/group_chat_service.dart';
import '../services/encryption_service.dart';
import '../services/transport_manager.dart';

// Initialize services
final encryptionService = EncryptionService();
final transportManager = TransportManager();
final groupChatService = GroupChatService(
  encryptionService: encryptionService,
  transportManager: transportManager,
);

// Initialize encryption service
await encryptionService.initialize();

// Create a new group
final groupInfo = await groupChatService.createGroup(
  'Project Team',
  description: 'Development team collaboration',
);
```

### Creating and Managing Groups

```dart
// Create a new group (automatically makes creator an admin)
final groupInfo = await groupChatService.createGroup(
  'Family Chat',
  description: 'Private family discussions',
);

print('Group created: ${groupInfo.name}');
print('Group ID: ${groupInfo.id}');
print('Admin: You');

// Get all your groups
final myGroups = await groupChatService.getMyGroups();
for (final group in myGroups) {
  print('${group.name}: ${group.members.length} members');
}
```

### Inviting Members

```dart
// Import a member's public key (from QR code, file, etc.)
final memberPublicKey = EncryptionService.parsePublicKeyFromQr(
  'MESH_PUBLIC_KEY:base64_encoded_key_here'
);

// Invite member to group (admin only)
await groupChatService.inviteMember(groupId, memberPublicKey);

// The invited member will receive an invitation and can accept it
```

### Accepting Invitations

```dart
// When receiving an invitation (via transport)
void handleInvitation(GroupInvitation invitation) async {
  try {
    final groupInfo = await groupChatService.acceptInvitation(invitation);
    print('Successfully joined group: ${groupInfo.name}');
  } catch (e) {
    print('Failed to accept invitation: $e');
  }
}
```

### Sending Group Messages

```dart
// Send a text message
final messageData = utf8.encode('Hello everyone!');
await groupChatService.sendGroupMessage(groupId, messageData);

// Send a file (convert to bytes first)
final fileData = await File('document.pdf').readAsBytes();
await groupChatService.sendGroupMessage(groupId, fileData);

// Decrypt received messages
void handleGroupMessage(GroupMessage message) async {
  try {
    final decryptedData = await groupChatService.decryptGroupMessage(message);
    final messageText = utf8.decode(decryptedData);
    print('Received: $messageText');
  } catch (e) {
    print('Failed to decrypt message: $e');
  }
}
```

### Member Management

```dart
// Remove a member (admin only)
await groupChatService.removeMember(groupId, memberPublicKey);

// Leave a group
await groupChatService.leaveGroup(groupId);

// Transfer admin role by making someone else admin and removing yourself
```

### Key Management

```dart
// Rotate group key (admin only)
await groupChatService.rotateGroupKey(groupId);

// Synchronize group metadata
await groupChatService.synchronizeGroup(groupId);
```

## Stream Integration

### Listening to Group Messages

```dart
// Listen to all group messages
groupChatService.groupMessageStream.listen((message) {
  print('Group message in ${message.groupId}');
  handleGroupMessage(message);
});

// Listen to group-specific messages
groupChatService._messageStreams[groupId]?.stream.listen((message) {
  // Handle messages for specific group
});

// Listen to group events
groupChatService.groupEventStream.listen((event) {
  switch (event.type) {
    case GroupEventType.memberJoined:
      print('New member joined ${event.groupId}');
      break;
    case GroupEventType.memberLeft:
      print('Member left ${event.groupId}');
      break;
    case GroupEventType.keyRotated:
      print('Group key rotated in ${event.groupId}');
      break;
    // Handle other events...
  }
});
```

## Data Classes

### GroupInfo
```dart
class GroupInfo {
  final String id;
  final String name;
  final String? description;
  final Uint8List createdBy;
  final DateTime createdAt;
  final SecretKey symmetricKey;
  final List<GroupMember> members;
  final Map<String, dynamic> metadata;
}
```

### GroupMember
```dart
class GroupMember {
  final Uint8List id;
  final GroupMemberRole role; // admin, member
  final DateTime joinedAt;
  final bool isActive;
}
```

### GroupMessage
```dart
class GroupMessage {
  final String id;
  final String groupId;
  final Uint8List senderId;
  final String encryptedData;
  final DateTime timestamp;
  final GroupMessageType messageType; // text, file, image, system, sync
}
```

### GroupEvent
```dart
class GroupEvent {
  final String groupId;
  final GroupEventType type;
  final Map<String, dynamic> data;
  final DateTime timestamp;
}
```

## Transport Layer Integration

The Group Chat Service automatically integrates with all registered transport layers:

### BLE Transport
- **Use Case**: Short-range, high-reliability communication
- **Message Size**: Up to 240 bytes per packet
- **Best For**: Local mesh networks, offline scenarios

### LibP2P Transport
- **Use Case**: Internet-based peer-to-peer communication
- **Message Size**: Up to 1MB
- **Best For**: Global communication, file sharing

### LoRa Transport
- **Use Case**: Long-range, low-power communication
- **Message Size**: Up to 240 bytes per packet
- **Best For**: Rural areas, emergency communications

### Automatic Transport Selection
The service uses TransportManager's intelligent selection:
1. **Connectivity Check**: Verifies transport availability
2. **Quality Assessment**: Considers connection quality scores
3. **Fallback Handling**: Automatic failover on failures
4. **Load Balancing**: Distributes across multiple connections

## Security Considerations

### Key Management
- **Group Keys**: Derived using HKDF from device key + group ID
- **Key Distribution**: Encrypted using Curve25519 with each member
- **Key Rotation**: Admin-controlled, distributed to all active members
- **Storage**: Secure storage using FlutterSecureStorage

### Encryption Details
- **Algorithm**: AES-256-GCM for group messages
- **Key Exchange**: Curve25519 for member invitation
- **Derivation**: HKDF with context-specific salt and info
- **Authentication**: GCM provides authenticity and integrity

### Access Control
- **Admin Permissions**: Only admins can invite/remove members and rotate keys
- **Membership Verification**: All operations validate active membership
- **Invitation Expiration**: Time-limited invitations prevent replay attacks
- **Message Origin**: All messages verified against member list

## Error Handling

### Common Exceptions
```dart
try {
  await groupChatService.sendGroupMessage(groupId, messageData);
} on GroupChatException catch (e) {
  switch (e.message) {
    case 'Group not found':
      // Handle missing group
      break;
    case 'Not an active group member':
      // Handle membership issues
      break;
    case 'Only admins can invite members':
      // Handle permission issues
      break;
    case 'Group has reached maximum member limit':
      // Handle capacity limits
      break;
  }
}
```

### Transport Errors
- **Connection Issues**: Automatic fallback to alternative transports
- **Message Delivery**: Retry logic with exponential backoff
- **Network Changes**: Dynamic transport selection based on availability

## Performance Considerations

### Group Size Limits
- **Maximum Members**: 50 (configurable in code)
- **Optimal Size**: 10-20 members for best performance
- **Large Groups**: May experience increased latency

### Message Throughput
- **Small Messages**: Near-real-time delivery
- **Large Files**: Chunked transmission via LibP2P
- **Offline Messages**: Queued for delivery when connection restored

### Storage Usage
- **Keys**: ~32 bytes per group
- **Metadata**: Minimal storage per group
- **Invitations**: Automatically cleaned up after expiration

## Integration Example

Complete integration with existing services:

```dart
class ChatApp extends StatefulWidget {
  @override
  _ChatAppState createState() => _ChatAppState();
}

class _ChatAppState extends State<ChatApp> {
  late GroupChatService groupChatService;
  late EncryptionService encryptionService;
  late TransportManager transportManager;
  
  StreamSubscription<GroupMessage>? messageSubscription;
  StreamSubscription<GroupEvent>? eventSubscription;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    // Initialize encryption service
    encryptionService = EncryptionService();
    await encryptionService.initialize();

    // Initialize transport manager
    transportManager = TransportManager();
    await transportManager.registerTransport(BleTransport());
    await transportManager.registerTransport(LibP2PTransport());
    await transportManager.registerTransport(LoRaTransport());
    await transportManager.initializeAllTransports();

    // Initialize group chat service
    groupChatService = GroupChatService(
      encryptionService: encryptionService,
      transportManager: transportManager,
    );

    // Listen to group events
    messageSubscription = groupChatService.groupMessageStream.listen(
      _handleGroupMessage
    );
    eventSubscription = groupChatService.groupEventStream.listen(
      _handleGroupEvent
    );
  }

  void _handleGroupMessage(GroupMessage message) async {
    try {
      final decryptedData = await groupChatService.decryptGroupMessage(message);
      // Handle decrypted message
    } catch (e) {
      print('Failed to decrypt message: $e');
    }
  }

  void _handleGroupEvent(GroupEvent event) {
    // Handle group events (member joined, left, etc.)
  }

  @override
  void dispose() {
    messageSubscription?.cancel();
    eventSubscription?.cancel();
    groupChatService.dispose();
    transportManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Secure Group Chat')),
        body: YourChatInterface(),
      ),
    );
  }
}
```

## Testing

Unit tests are provided for key functionality:

```dart
// Test group creation
final groupInfo = await groupChatService.createGroup('Test Group');
expect(groupInfo.name, equals('Test Group'));
expect(groupInfo.members.length, equals(1));

// Test member invitation
final memberKey = await encryptionService.generateKeyPair();
await groupChatService.inviteMember(groupInfo.id, memberKey.publicKey);

// Test message encryption/decryption
final messageData = utf8.encode('Test message');
await groupChatService.sendGroupMessage(groupInfo.id, messageData);
```

## Troubleshooting

### Common Issues

1. **"Group not found"**
   - Verify group ID is correct
   - Check if you're still a member
   - Synchronize group state

2. **"Not an active group member"**
   - Accept pending invitation
   - Check membership status
   - Contact group admin

3. **Transport connection issues**
   - Verify transport initialization
   - Check network connectivity
   - Try alternative transports

4. **Message decryption failures**
   - Verify group key rotation
   - Check if key distribution completed
   - Ensure member is active

### Debug Logging
Enable detailed logging by adding print statements in key method points:

```dart
// Enable debug mode
const bool kDebugMode = true;

// Add logging in critical paths
if (kDebugMode) {
  print('Creating group: $groupName');
  print('Inviting member: ${base64Encode(memberKey)}');
  print('Sending message to group: $groupId');
}
```

## Future Enhancements

### Planned Features
- **Message History**: Persistent message storage and retrieval
- **File Transfer**: Large file sharing with chunking
- **Voice Messages**: Encrypted audio messaging
- **Read Receipts**: Message delivery and read confirmations
- **Group Discovery**: Public group directory with search
- **Backup/Restore**: Group migration between devices

### Scalability Improvements
- **Hierarchical Groups**: Nested group structures
- **Hybrid Encryption**: Combination of symmetric and asymmetric encryption
- **Optimized Broadcasting**: Tree-based message distribution
- **Offline Support**: Message queuing for offline members

This comprehensive group chat service provides secure, scalable group messaging suitable for a wide range of use cases while maintaining strong security guarantees and cross-platform compatibility.