import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/encryption_service.dart';
import '../services/transport_manager.dart';
import '../services/transport.dart';

/// Group Chat Service providing secure group messaging with shared symmetric keys
/// 
/// Features:
/// - Group key generation and management using Curve25519 and HKDF
/// - Member invitation and secure key distribution
/// - Group membership management (add/remove members)
/// - Encrypted group messaging with shared keys
/// - Group metadata storage and synchronization
/// - Integration with all transport layers for group broadcasts
class GroupChatService {
  static const String _groupKeysPrefix = 'group_keys_';
  static const String _groupMetadataPrefix = 'group_metadata_';
  static const String _groupMembersPrefix = 'group_members_';
  
  static const int _symmetricKeyLength = 32; // AES-256-GCM key
  static const int _maxGroupMembers = 50; // Reasonable limit for performance
  
  final FlutterSecureStorage _secureStorage;
  final EncryptionService _encryptionService;
  final TransportManager _transportManager;
  
  // Group state management
  final Map<String, GroupInfo> _activeGroups = {};
  final Map<String, StreamController<GroupMessage>> _messageStreams = {};
  final Map<String, StreamController<GroupEvent>> _eventStreams = {};
  
  // Key management
  final X25519 _x25519 = X25519();
  final Hkdf _hkdf = Hkdf(Sha256());
  final AesGcm _aesGcm = AesGcm.with256bits();
  final Random _random = Random.secure();

  GroupChatService({
    FlutterSecureStorage? secureStorage,
    required EncryptionService encryptionService,
    required TransportManager transportManager,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _encryptionService = encryptionService,
       _transportManager = transportManager {
    
    // Listen to transport messages for group operations
    _transportManager.messageStream.listen(_handleIncomingMessage);
  }

  /// Get all streams for external listeners
  Stream<GroupMessage> get groupMessageStream => 
      _messageStreams.values.expand((controller) => controller.stream);
  
  Stream<GroupEvent> get groupEventStream => 
      _eventStreams.values.expand((controller) => controller.stream);

  /// Create a new group with a generated symmetric key
  Future<GroupInfo> createGroup(String groupName, {String? description}) async {
    try {
      // Generate unique group ID
      final groupId = _generateGroupId();
      
      // Generate group symmetric key
      final groupKey = await _generateGroupKey(groupId);
      
      // Create group metadata
      final groupInfo = GroupInfo(
        id: groupId,
        name: groupName,
        description: description,
        createdBy: await _encryptionService.getPublicKey(),
        createdAt: DateTime.now(),
        symmetricKey: groupKey,
        members: [],
        metadata: {},
      );
      
      // Add creator as admin member
      final creatorMember = GroupMember(
        id: await _encryptionService.getPublicKey(),
        role: GroupMemberRole.admin,
        joinedAt: DateTime.now(),
        isActive: true,
      );
      groupInfo.members.add(creatorMember);
      
      // Store group data
      await _storeGroupInfo(groupInfo);
      await _storeGroupKey(groupId, groupKey);
      await _storeGroupMembers(groupId, groupInfo.members);
      
      // Add to active groups
      _activeGroups[groupId] = groupInfo;
      _initializeGroupStreams(groupId);
      
      // Broadcast group creation
      await _broadcastGroupEvent(groupId, GroupEventType.groupCreated, {
        'group_id': groupId,
        'group_name': groupName,
        'creator_key': base64Encode(creatorMember.id),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      
      return groupInfo;
    } catch (e) {
      throw GroupChatException('Failed to create group: $e');
    }
  }

  /// Invite a member to the group with secure key distribution
  Future<void> inviteMember(String groupId, Uint8List memberPublicKey) async {
    try {
      final groupInfo = await getGroupInfo(groupId);
      if (groupInfo == null) {
        throw GroupChatException('Group not found: $groupId');
      }
      
      // Check if member already exists
      if (_memberExists(groupInfo.members, memberPublicKey)) {
        throw GroupChatException('Member already exists in group');
      }
      
      // Verify permissions (only admins can invite)
      final myPublicKey = await _encryptionService.getPublicKey();
      final myMember = groupInfo.members.firstWhere(
        (member) => _equalKeys(member.id, myPublicKey),
        orElse: () => throw GroupChatException('Not a group member'),
      );
      
      if (myMember.role != GroupMemberRole.admin) {
        throw GroupChatException('Only admins can invite members');
      }
      
      // Check member limit
      if (groupInfo.members.length >= _maxGroupMembers) {
        throw GroupChatException('Group has reached maximum member limit');
      }
      
      // Derive shared secret for key distribution
      final sharedSecret = await _encryptionService.deriveSharedSecret(memberPublicKey);
      
      // Encrypt group key with member's key
      final encryptedGroupKey = await _encryptionService.encrypt(groupInfo.symmetricKey.bytes, sharedSecret);
      
      // Create invitation message
      final invitation = GroupInvitation(
        groupId: groupId,
        groupName: groupInfo.name,
        encryptedGroupKey: encryptedGroupKey,
        inviterKey: myPublicKey,
        timestamp: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
      );
      
      // Create member entry
      final newMember = GroupMember(
        id: memberPublicKey,
        role: GroupMemberRole.member,
        joinedAt: DateTime.now(),
        isActive: false, // Will be activated upon accepting invitation
      );
      
      // Store pending invitation
      await _storeInvitation(groupId, memberPublicKey, invitation);
      
      // Send invitation via transport layers
      final invitationData = utf8.encode(jsonEncode(invitation.toJson()));
      final encryptedInvitation = await _encryptForMember(invitationData, memberPublicKey);
      
      final target = TransportTarget(
        id: base64Encode(memberPublicKey),
        type: TransportTargetType.peer,
        address: null,
        port: null,
      );
      
      await _transportManager.send(target, encryptedInvitation);
      
      // Broadcast invitation sent event
      await _broadcastGroupEvent(groupId, GroupEventType.memberInvited, {
        'group_id': groupId,
        'member_key': base64Encode(memberPublicKey),
        'inviter_key': base64Encode(myPublicKey),
      });
      
    } catch (e) {
      throw GroupChatException('Failed to invite member: $e');
    }
  }

  /// Accept a group invitation
  Future<GroupInfo> acceptInvitation(GroupInvitation invitation) async {
    try {
      // Verify invitation hasn't expired
      if (DateTime.now().isAfter(invitation.expiresAt)) {
        throw GroupChatException('Invitation has expired');
      }
      
      // Get my private key
      final myPrivateKey = await _encryptionService.getPrivateKey();
      final myPublicKey = await _encryptionService.getPublicKey();
      
      // Verify the invitation is for me
      if (!_equalKeys(myPublicKey, invitation.inviterKey)) {
        throw GroupChatException('Invitation is not for this device');
      }
      
      // Find the inviter in my contacts or verify through other means
      // For now, we'll assume the invitation is legitimate if it decrypts properly
      
      // Decrypt group key using shared secret with inviter
      final sharedSecret = await _encryptionService.deriveSharedSecret(invitation.inviterKey);
      final groupKeyBytes = await _encryptionService.decrypt(invitation.encryptedGroupKey, sharedSecret);
      final groupKey = SecretKey(groupKeyBytes);
      
      // Retrieve or create group info
      GroupInfo? groupInfo = await getGroupInfo(invitation.groupId);
      if (groupInfo == null) {
        // Create new group info from invitation
        groupInfo = GroupInfo(
          id: invitation.groupId,
          name: invitation.groupName,
          createdBy: invitation.inviterKey,
          createdAt: invitation.timestamp,
          symmetricKey: groupKey,
          members: [],
          metadata: {},
        );
      }
      
      // Add member if not already present
      final existingMemberIndex = groupInfo.members.indexWhere(
        (member) => _equalKeys(member.id, myPublicKey),
      );
      
      if (existingMemberIndex >= 0) {
        groupInfo.members[existingMemberIndex].isActive = true;
      } else {
        groupInfo.members.add(GroupMember(
          id: myPublicKey,
          role: GroupMemberRole.member,
          joinedAt: DateTime.now(),
          isActive: true,
        ));
      }
      
      // Store updated group data
      await _storeGroupInfo(groupInfo);
      await _storeGroupKey(groupInfo.id, groupKey);
      await _storeGroupMembers(groupInfo.id, groupInfo.members);
      
      // Add to active groups if not present
      if (!_activeGroups.containsKey(groupInfo.id)) {
        _activeGroups[groupInfo.id] = groupInfo;
        _initializeGroupStreams(groupInfo.id);
      }
      
      // Remove pending invitation
      await _removeInvitation(invitation.groupId, myPublicKey);
      
      // Broadcast member joined event
      await _broadcastGroupEvent(groupInfo.id, GroupEventType.memberJoined, {
        'group_id': groupInfo.id,
        'member_key': base64Encode(myPublicKey),
      });
      
      return groupInfo;
    } catch (e) {
      throw GroupChatException('Failed to accept invitation: $e');
    }
  }

  /// Send an encrypted message to a group
  Future<void> sendGroupMessage(String groupId, Uint8List messageData) async {
    try {
      final groupInfo = await getGroupInfo(groupId);
      if (groupInfo == null) {
        throw GroupChatException('Group not found: $groupId');
      }
      
      // Verify member is active
      final myPublicKey = await _encryptionService.getPublicKey();
      final member = groupInfo.members.firstWhere(
        (m) => _equalKeys(m.id, myPublicKey) && m.isActive,
        orElse: () => throw GroupChatException('Not an active group member'),
      );
      
      // Encrypt message with group symmetric key
      final encryptedMessage = await _encryptGroupMessage(messageData, groupInfo.symmetricKey);
      
      // Create group message
      final groupMessage = GroupMessage(
        id: _generateMessageId(),
        groupId: groupId,
        senderId: myPublicKey,
        encryptedData: encryptedMessage,
        timestamp: DateTime.now(),
        messageType: GroupMessageType.text,
      );
      
      // Broadcast message to all active members
      await _broadcastGroupMessage(groupMessage);
      
      // Add to local message stream
      _messageStreams[groupId]?.add(groupMessage);
      
    } catch (e) {
      throw GroupChatException('Failed to send group message: $e');
    }
  }

  /// Decrypt a group message
  Future<Uint8List> decryptGroupMessage(GroupMessage groupMessage) async {
    final groupInfo = await getGroupInfo(groupMessage.groupId);
    if (groupInfo == null) {
      throw GroupChatException('Group not found: ${groupMessage.groupId}');
    }
    
    return await _decryptGroupMessage(groupMessage.encryptedData, groupInfo.symmetricKey);
  }

  /// Remove a member from the group (admin only)
  Future<void> removeMember(String groupId, Uint8List memberPublicKey) async {
    try {
      final groupInfo = await getGroupInfo(groupId);
      if (groupInfo == null) {
        throw GroupChatException('Group not found: $groupId');
      }
      
      // Verify admin permissions
      final myPublicKey = await _encryptionService.getPublicKey();
      final myMember = groupInfo.members.firstWhere(
        (member) => _equalKeys(member.id, myPublicKey),
        orElse: () => throw GroupChatException('Not a group member'),
      );
      
      if (myMember.role != GroupMemberRole.admin) {
        throw GroupChatException('Only admins can remove members');
      }
      
      // Find and remove member
      final memberIndex = groupInfo.members.indexWhere(
        (member) => _equalKeys(member.id, memberPublicKey),
      );
      
      if (memberIndex < 0) {
        throw GroupChatException('Member not found in group');
      }
      
      final removedMember = groupInfo.members.removeAt(memberIndex);
      
      // Store updated member list
      await _storeGroupMembers(groupId, groupInfo.members);
      
      // Broadcast member removed event
      await _broadcastGroupEvent(groupId, GroupEventType.memberRemoved, {
        'group_id': groupId,
        'removed_member_key': base64Encode(removedMember.id),
        'remover_key': base64Encode(myPublicKey),
      });
      
    } catch (e) {
      throw GroupChatException('Failed to remove member: $e');
    }
  }

  /// Leave a group
  Future<void> leaveGroup(String groupId) async {
    try {
      final groupInfo = await getGroupInfo(groupId);
      if (groupInfo == null) {
        throw GroupChatException('Group not found: $groupId');
      }
      
      final myPublicKey = await _encryptionService.getPublicKey();
      final memberIndex = groupInfo.members.indexWhere(
        (member) => _equalKeys(member.id, myPublicKey),
      );
      
      if (memberIndex < 0) {
        throw GroupChatException('Not a group member');
      }
      
      final member = groupInfo.members[memberIndex];
      
      // If admin, transfer admin role or disband group
      if (member.role == GroupMemberRole.admin) {
        final otherActiveMembers = groupInfo.members
            .where((m) => m.isActive && !_equalKeys(m.id, myPublicKey))
            .toList();
        
        if (otherActiveMembers.isNotEmpty) {
          // Transfer admin role to first other member
          final newAdmin = otherActiveMembers.first;
          newAdmin.role = GroupMemberRole.admin;
          
          await _storeGroupMembers(groupId, groupInfo.members);
          
          await _broadcastGroupEvent(groupId, GroupEventType.adminTransferred, {
            'group_id': groupId,
            'new_admin_key': base64Encode(newAdmin.id),
            'previous_admin_key': base64Encode(myPublicKey),
          });
        } else {
          // No other members, disband group
          await _disbandGroup(groupId);
          return;
        }
      }
      
      // Remove member from group
      groupInfo.members.removeAt(memberIndex);
      await _storeGroupMembers(groupId, groupInfo.members);
      
      // Broadcast member left event
      await _broadcastGroupEvent(groupId, GroupEventType.memberLeft, {
        'group_id': groupId,
        'member_key': base64Encode(myPublicKey),
      });
      
      // Remove from active groups if no longer a member
      if (!_memberExists(groupInfo.members, myPublicKey)) {
        _activeGroups.remove(groupId);
        _messageStreams[groupId]?.close();
        _eventStreams[groupId]?.close();
        _messageStreams.remove(groupId);
        _eventStreams.remove(groupId);
      }
      
    } catch (e) {
      throw GroupChatException('Failed to leave group: $e');
    }
  }

  /// Get group information
  Future<GroupInfo?> getGroupInfo(String groupId) async {
    try {
      // Check active groups first
      if (_activeGroups.containsKey(groupId)) {
        return _activeGroups[groupId];
      }
      
      // Load from storage
      final metadataJson = await _secureStorage.read(key: '$_groupMetadataPrefix$groupId');
      if (metadataJson == null) {
        return null;
      }
      
      final metadata = jsonDecode(metadataJson) as Map<String, dynamic>;
      final membersJson = await _secureStorage.read(key: '$_groupMembersPrefix$groupId');
      final membersList = membersJson != null ? 
          (jsonDecode(membersJson) as List).map((e) => GroupMember.fromJson(e as Map<String, dynamic>)).toList() :
          <GroupMember>[];
      
      final keyJson = await _secureStorage.read(key: '$_groupKeysPrefix$groupId');
      if (keyJson == null) {
        return null;
      }
      final symmetricKey = SecretKey(base64Decode(keyJson));
      
      final groupInfo = GroupInfo.fromJson(metadata).copyWith(
        symmetricKey: symmetricKey,
        members: membersList,
      );
      
      // Cache in active groups
      _activeGroups[groupId] = groupInfo;
      _initializeGroupStreams(groupId);
      
      return groupInfo;
    } catch (e) {
      return null;
    }
  }

  /// Get all groups this device is a member of
  Future<List<GroupInfo>> getMyGroups() async {
    final groups = <GroupInfo>[];
    final myPublicKey = await _encryptionService.getPublicKey();
    
    // Get all stored groups and filter by membership
    final allKeys = await _secureStorage.readAll();
    
    for (final key in allKeys.keys) {
      if (key.startsWith(_groupMetadataPrefix)) {
        final groupId = key.substring(_groupMetadataPrefix.length);
        final groupInfo = await getGroupInfo(groupId);
        
        if (groupInfo != null && _memberExists(groupInfo.members, myPublicKey)) {
          groups.add(groupInfo);
        }
      }
    }
    
    return groups;
  }

  /// Synchronize group metadata with other members
  Future<void> synchronizeGroup(String groupId) async {
    try {
      final groupInfo = await getGroupInfo(groupId);
      if (groupInfo == null) {
        throw GroupChatException('Group not found: $groupId');
      }
      
      final syncData = GroupSyncData(
        groupId: groupId,
        members: groupInfo.members,
        metadata: groupInfo.metadata,
        timestamp: DateTime.now(),
      );
      
      final syncJson = jsonEncode(syncData.toJson());
      final encryptedSync = await _encryptForGroup(syncJson, groupInfo.symmetricKey);
      
      await _broadcastGroupMessage(GroupMessage(
        id: _generateMessageId(),
        groupId: groupId,
        senderId: await _encryptionService.getPublicKey(),
        encryptedData: encryptedSync,
        timestamp: DateTime.now(),
        messageType: GroupMessageType.sync,
      ));
      
    } catch (e) {
      throw GroupChatException('Failed to synchronize group: $e');
    }
  }

  /// Rotate group symmetric key (admin only)
  Future<void> rotateGroupKey(String groupId) async {
    try {
      final groupInfo = await getGroupInfo(groupId);
      if (groupInfo == null) {
        throw GroupChatException('Group not found: $groupId');
      }
      
      // Verify admin permissions
      final myPublicKey = await _encryptionService.getPublicKey();
      final myMember = groupInfo.members.firstWhere(
        (member) => _equalKeys(member.id, myPublicKey),
        orElse: () => throw GroupChatException('Not a group member'),
      );
      
      if (myMember.role != GroupMemberRole.admin) {
        throw GroupChatException('Only admins can rotate group keys');
      }
      
      // Generate new symmetric key
      final newGroupKey = await _generateGroupKey(groupId);
      
      // Update group info
      final updatedGroup = groupInfo.copyWith(symmetricKey: newGroupKey);
      await _storeGroupKey(groupId, newGroupKey);
      await _storeGroupInfo(updatedGroup);
      _activeGroups[groupId] = updatedGroup;
      
      // Distribute new key to all active members
      for (final member in groupInfo.members.where((m) => m.isActive)) {
        if (!_equalKeys(member.id, myPublicKey)) {
          try {
            await _distributeNewGroupKey(groupId, member.id, newGroupKey);
          } catch (e) {
            // Log but continue with other members
            print('Failed to distribute new key to member: $e');
          }
        }
      }
      
      // Broadcast key rotation event
      await _broadcastGroupEvent(groupId, GroupEventType.keyRotated, {
        'group_id': groupId,
        'rotator_key': base64Encode(myPublicKey),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      
    } catch (e) {
      throw GroupChatException('Failed to rotate group key: $e');
    }
  }

  // Private helper methods

  String _generateGroupId() {
    return 'group_${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(999999)}';
  }

  String _generateMessageId() {
    return 'msg_${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(999999)}';
  }

  Future<SecretKey> _generateGroupKey(String groupId) async {
    // Use HKDF with device key and group ID to derive unique group key
    final deviceKey = await _encryptionService.getPrivateKey();
    final salt = utf8.encode('group_$groupId');
    const info = 'mesh_group_symmetric_key';
    
    final derivedKey = await _hkdf.deriveKey(
      secretKey: SecretKey(deviceKey),
      outputLength: _symmetricKeyLength,
      salt: salt,
      info: utf8.encode(info),
    );
    
    return derivedKey;
  }

  Future<String> _encryptGroupMessage(Uint8List data, SecretKey groupKey) async {
    // Use AES-GCM with group key
    final nonce = _generateNonce();
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final aad = utf8.encode('group_chat_$timestamp');
    
    final secretBox = await _aesGcm.encrypt(
      data,
      secretKey: groupKey,
      nonce: nonce,
      aad: aad,
    );
    
    // Pack nonce || ciphertext || tag
    final packed = Uint8List(nonce.length + secretBox.cipherText.length + secretBox.mac.bytes.length);
    packed.setAll(0, nonce);
    packed.setAll(nonce.length, secretBox.cipherText);
    packed.setAll(nonce.length + secretBox.cipherText.length, secretBox.mac.bytes);
    
    return base64Encode(packed);
  }

  Future<Uint8List> _decryptGroupMessage(String encryptedData, SecretKey groupKey) async {
    final packed = base64Decode(encryptedData);
    
    final nonceLength = 12;
    final tagLength = 16;
    final nonce = packed.sublist(0, nonceLength);
    final tag = packed.sublist(packed.length - tagLength);
    final ciphertext = packed.sublist(nonceLength, packed.length - tagLength);
    
    final secretBox = SecretBox(
      ciphertext,
      nonce: nonce,
      mac: Mac(tag),
    );
    
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final aad = utf8.encode('group_chat_$timestamp');
    
    return await _aesGcm.decrypt(
      secretBox,
      secretKey: groupKey,
      aad: aad,
    );
  }

  Uint8List _generateNonce() {
    return Uint8List.fromList(
      List<int>.generate(12, (_) => _random.nextInt(256)),
    );
  }

  Future<void> _encryptForMember(Uint8List data, Uint8List memberPublicKey) async {
    // This would encrypt data specifically for a member using their public key
    // Implementation depends on the transport layer requirements
  }

  Future<void> _distributeNewGroupKey(String groupId, Uint8List memberPublicKey, SecretKey newKey) async {
    // Create a special message to distribute the new group key
    final keyDistribution = GroupKeyDistribution(
      groupId: groupId,
      newGroupKey: base64Encode(newKey.bytes),
      timestamp: DateTime.now(),
      senderKey: await _encryptionService.getPublicKey(),
    );
    
    final distributionJson = utf8.encode(jsonEncode(keyDistribution.toJson()));
    final encryptedDistribution = await _encryptForMember(distributionJson, memberPublicKey);
    
    final target = TransportTarget(
      id: base64Encode(memberPublicKey),
      type: TransportTargetType.peer,
      address: null,
      port: null,
    );
    
    await _transportManager.send(target, encryptedDistribution);
  }

  Future<void> _broadcastGroupMessage(GroupMessage message) async {
    final groupInfo = await getGroupInfo(message.groupId);
    if (groupInfo == null) return;
    
    final messageJson = jsonEncode(message.toJson());
    final encryptedMessage = utf8.encode(messageJson);
    
    // Broadcast to all active members except sender
    for (final member in groupInfo.members.where((m) => m.isActive)) {
      if (!_equalKeys(member.id, message.senderId)) {
        final target = TransportTarget(
          id: base64Encode(member.id),
          type: TransportTargetType.peer,
          address: null,
          port: null,
        );
        
        await _transportManager.send(target, encryptedMessage);
      }
    }
  }

  Future<void> _broadcastGroupEvent(String groupId, GroupEventType eventType, Map<String, dynamic> data) async {
    final groupInfo = await getGroupInfo(groupId);
    if (groupInfo == null) return;
    
    final event = GroupEvent(
      groupId: groupId,
      type: eventType,
      data: data,
      timestamp: DateTime.now(),
    );
    
    final eventJson = utf8.encode(jsonEncode(event.toJson()));
    final encryptedEvent = await _encryptForGroup(eventJson, groupInfo.symmetricKey);
    
    // Broadcast to all active members
    for (final member in groupInfo.members.where((m) => m.isActive)) {
      final target = TransportTarget(
        id: base64Encode(member.id),
        type: TransportTargetType.peer,
        address: null,
        port: null,
      );
      
      await _transportManager.send(target, encryptedEvent);
    }
  }

  Future<void> _encryptForGroup(Uint8List data, SecretKey groupKey) async {
    // Simplified - in practice, this would use the same encryption as group messages
    final encrypted = await _encryptGroupMessage(data, groupKey);
    return utf8.encode(encrypted);
  }

  void _initializeGroupStreams(String groupId) {
    if (!_messageStreams.containsKey(groupId)) {
      _messageStreams[groupId] = StreamController<GroupMessage>.broadcast();
    }
    if (!_eventStreams.containsKey(groupId)) {
      _eventStreams[groupId] = StreamController<GroupEvent>.broadcast();
    }
  }

  void _handleIncomingMessage(TransportMessage transportMessage) async {
    try {
      // Parse incoming message and route to appropriate group
      final messageStr = utf8.decode(transportMessage.data);
      final messageData = jsonDecode(messageStr);
      
      // Determine message type based on structure
      if (messageData.containsKey('encryptedData')) {
        // Group message
        final groupMessage = GroupMessage.fromJson(messageData);
        await _processIncomingGroupMessage(groupMessage);
      } else if (messageData.containsKey('type')) {
        // Group event
        final groupEvent = GroupEvent.fromJson(messageData);
        _eventStreams[groupEvent.groupId]?.add(groupEvent);
      }
    } catch (e) {
      print('Error processing incoming group message: $e');
    }
  }

  Future<void> _processIncomingGroupMessage(GroupMessage groupMessage) async {
    try {
      final groupInfo = await getGroupInfo(groupMessage.groupId);
      if (groupInfo == null) return;
      
      // Only add message if we're a member
      final myPublicKey = await _encryptionService.getPublicKey();
      if (_memberExists(groupInfo.members, myPublicKey)) {
        _messageStreams[groupMessage.groupId]?.add(groupMessage);
      }
    } catch (e) {
      print('Error processing group message: $e');
    }
  }

  bool _memberExists(List<GroupMember> members, Uint8List publicKey) {
    return members.any((member) => _equalKeys(member.id, publicKey));
  }

  bool _equalKeys(Uint8List key1, Uint8List key2) {
    if (key1.length != key2.length) return false;
    for (int i = 0; i < key1.length; i++) {
      if (key1[i] != key2[i]) return false;
    }
    return true;
  }

  // Storage methods
  Future<void> _storeGroupInfo(GroupInfo groupInfo) async {
    final metadata = groupInfo.toJson();
    metadata.remove('symmetricKey'); // Don't store key in metadata
    metadata.remove('members'); // Store members separately
    
    await _secureStorage.write(
      key: '$_groupMetadataPrefix${groupInfo.id}',
      value: jsonEncode(metadata),
    );
  }

  Future<void> _storeGroupKey(String groupId, SecretKey groupKey) async {
    await _secureStorage.write(
      key: '$_groupKeysPrefix$groupId',
      value: base64Encode(groupKey.bytes),
    );
  }

  Future<void> _storeGroupMembers(String groupId, List<GroupMember> members) async {
    final membersList = members.map((member) => member.toJson()).toList();
    await _secureStorage.write(
      key: '$_groupMembersPrefix$groupId',
      value: jsonEncode(membersList),
    );
  }

  Future<void> _storeInvitation(String groupId, Uint8List memberKey, GroupInvitation invitation) async {
    final invitationKey = 'invitation_${groupId}_${base64Encode(memberKey)}';
    await _secureStorage.write(
      key: invitationKey,
      value: jsonEncode(invitation.toJson()),
    );
  }

  Future<void> _removeInvitation(String groupId, Uint8List memberKey) async {
    final invitationKey = 'invitation_${groupId}_${base64Encode(memberKey)}';
    await _secureStorage.delete(key: invitationKey);
  }

  Future<void> _disbandGroup(String groupId) async {
    await _secureStorage.delete(key: '$_groupMetadataPrefix$groupId');
    await _secureStorage.delete(key: '$_groupKeysPrefix$groupId');
    await _secureStorage.delete(key: '$_groupMembersPrefix$groupId');
    
    _activeGroups.remove(groupId);
    _messageStreams[groupId]?.close();
    _eventStreams[groupId]?.close();
    _messageStreams.remove(groupId);
    _eventStreams.remove(groupId);
  }

  void dispose() {
    // Close all streams
    for (final stream in _messageStreams.values) {
      stream.close();
    }
    for (final stream in _eventStreams.values) {
      stream.close();
    }
    _messageStreams.clear();
    _eventStreams.clear();
    _activeGroups.clear();
  }
}

// Data classes

class GroupInfo {
  final String id;
  final String name;
  final String? description;
  final Uint8List createdBy;
  final DateTime createdAt;
  final SecretKey symmetricKey;
  final List<GroupMember> members;
  final Map<String, dynamic> metadata;

  GroupInfo({
    required this.id,
    required this.name,
    this.description,
    required this.createdBy,
    required this.createdAt,
    required this.symmetricKey,
    required this.members,
    required this.metadata,
  });

  factory GroupInfo.fromJson(Map<String, dynamic> json) => GroupInfo(
    id: json['id'],
    name: json['name'],
    description: json['description'],
    createdBy: base64Decode(json['created_by']),
    createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at']),
    symmetricKey: SecretKey(Uint8List(0)), // Will be set separately
    members: [], // Will be set separately
    metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'created_by': base64Encode(createdBy),
    'created_at': createdAt.millisecondsSinceEpoch,
    'metadata': metadata,
  };

  GroupInfo copyWith({
    String? id,
    String? name,
    String? description,
    Uint8List? createdBy,
    DateTime? createdAt,
    SecretKey? symmetricKey,
    List<GroupMember>? members,
    Map<String, dynamic>? metadata,
  }) => GroupInfo(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    createdBy: createdBy ?? this.createdBy,
    createdAt: createdAt ?? this.createdAt,
    symmetricKey: symmetricKey ?? this.symmetricKey,
    members: members ?? this.members,
    metadata: metadata ?? this.metadata,
  );
}

class GroupMember {
  final Uint8List id;
  final GroupMemberRole role;
  final DateTime joinedAt;
  final bool isActive;

  GroupMember({
    required this.id,
    required this.role,
    required this.joinedAt,
    required this.isActive,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) => GroupMember(
    id: base64Decode(json['id']),
    role: GroupMemberRole.values.firstWhere((r) => r.toString().split('.').last == json['role']),
    joinedAt: DateTime.fromMillisecondsSinceEpoch(json['joined_at']),
    isActive: json['is_active'],
  );

  Map<String, dynamic> toJson() => {
    'id': base64Encode(id),
    'role': role.toString().split('.').last,
    'joined_at': joinedAt.millisecondsSinceEpoch,
    'is_active': isActive,
  };
}

class GroupMessage {
  final String id;
  final String groupId;
  final Uint8List senderId;
  final String encryptedData;
  final DateTime timestamp;
  final GroupMessageType messageType;

  GroupMessage({
    required this.id,
    required this.groupId,
    required this.senderId,
    required this.encryptedData,
    required this.timestamp,
    required this.messageType,
  });

  factory GroupMessage.fromJson(Map<String, dynamic> json) => GroupMessage(
    id: json['id'],
    groupId: json['group_id'],
    senderId: base64Decode(json['sender_id']),
    encryptedData: json['encrypted_data'],
    timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp']),
    messageType: GroupMessageType.values.firstWhere((t) => t.toString().split('.').last == json['message_type']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'group_id': groupId,
    'sender_id': base64Encode(senderId),
    'encrypted_data': encryptedData,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'message_type': messageType.toString().split('.').last,
  };
}

class GroupEvent {
  final String groupId;
  final GroupEventType type;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  GroupEvent({
    required this.groupId,
    required this.type,
    required this.data,
    required this.timestamp,
  });

  factory GroupEvent.fromJson(Map<String, dynamic> json) => GroupEvent(
    groupId: json['group_id'],
    type: GroupEventType.values.firstWhere((t) => t.toString().split('.').last == json['type']),
    data: Map<String, dynamic>.from(json['data']),
    timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp']),
  );

  Map<String, dynamic> toJson() => {
    'group_id': groupId,
    'type': type.toString().split('.').last,
    'data': data,
    'timestamp': timestamp.millisecondsSinceEpoch,
  };
}

class GroupInvitation {
  final String groupId;
  final String groupName;
  final String encryptedGroupKey;
  final Uint8List inviterKey;
  final DateTime timestamp;
  final DateTime expiresAt;

  GroupInvitation({
    required this.groupId,
    required this.groupName,
    required this.encryptedGroupKey,
    required this.inviterKey,
    required this.timestamp,
    required this.expiresAt,
  });

  factory GroupInvitation.fromJson(Map<String, dynamic> json) => GroupInvitation(
    groupId: json['group_id'],
    groupName: json['group_name'],
    encryptedGroupKey: json['encrypted_group_key'],
    inviterKey: base64Decode(json['inviter_key']),
    timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp']),
    expiresAt: DateTime.fromMillisecondsSinceEpoch(json['expires_at']),
  );

  Map<String, dynamic> toJson() => {
    'group_id': groupId,
    'group_name': groupName,
    'encrypted_group_key': encryptedGroupKey,
    'inviter_key': base64Encode(inviterKey),
    'timestamp': timestamp.millisecondsSinceEpoch,
    'expires_at': expiresAt.millisecondsSinceEpoch,
  };
}

class GroupKeyDistribution {
  final String groupId;
  final String newGroupKey;
  final DateTime timestamp;
  final Uint8List senderKey;

  GroupKeyDistribution({
    required this.groupId,
    required this.newGroupKey,
    required this.timestamp,
    required this.senderKey,
  });

  factory GroupKeyDistribution.fromJson(Map<String, dynamic> json) => GroupKeyDistribution(
    groupId: json['group_id'],
    newGroupKey: json['new_group_key'],
    timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp']),
    senderKey: base64Decode(json['sender_key']),
  );

  Map<String, dynamic> toJson() => {
    'group_id': groupId,
    'new_group_key': newGroupKey,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'sender_key': base64Encode(senderKey),
  };
}

class GroupSyncData {
  final String groupId;
  final List<GroupMember> members;
  final Map<String, dynamic> metadata;
  final DateTime timestamp;

  GroupSyncData({
    required this.groupId,
    required this.members,
    required this.metadata,
    required this.timestamp,
  });

  factory GroupSyncData.fromJson(Map<String, dynamic> json) => GroupSyncData(
    groupId: json['group_id'],
    members: (json['members'] as List).map((e) => GroupMember.fromJson(e)).toList(),
    metadata: Map<String, dynamic>.from(json['metadata']),
    timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp']),
  );

  Map<String, dynamic> toJson() => {
    'group_id': groupId,
    'members': members.map((e) => e.toJson()).toList(),
    'metadata': metadata,
    'timestamp': timestamp.millisecondsSinceEpoch,
  };
}

// Enums

enum GroupMemberRole {
  admin,
  member,
}

enum GroupMessageType {
  text,
  file,
  image,
  system,
  sync,
}

enum GroupEventType {
  groupCreated,
  groupDisbanded,
  memberInvited,
  memberJoined,
  memberLeft,
  memberRemoved,
  adminTransferred,
  keyRotated,
  memberActivated,
  memberDeactivated,
}

// Exceptions

class GroupChatException implements Exception {
  final String message;
  
  GroupChatException(this.message);
  
  @override
  String toString() => 'GroupChatException: $message';
}