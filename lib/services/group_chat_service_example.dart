/// Group Chat Service Example Implementation
/// 
/// This example demonstrates how to integrate and use the GroupChatService
/// with the existing encryption and transport infrastructure.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/group_chat_service.dart';
import '../services/encryption_service.dart';
import '../services/transport_manager.dart';
import '../services/ble_transport.dart';
import '../services/libp2p_transport.dart';
import '../services/loRa_transport.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Group Chat Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: GroupChatExampleScreen(),
    );
  }
}

class GroupChatExampleScreen extends StatefulWidget {
  @override
  _GroupChatExampleScreenState createState() => _GroupChatExampleScreenState();
}

class _GroupChatExampleScreenState extends State<GroupChatExampleScreen> {
  late GroupChatService _groupChatService;
  late EncryptionService _encryptionService;
  late TransportManager _transportManager;
  
  List<GroupInfo> _myGroups = [];
  List<GroupMessage> _messages = [];
  String? _currentGroupId;
  
  StreamSubscription<GroupMessage>? _messageSubscription;
  StreamSubscription<GroupEvent>? _eventSubscription;
  
  final _messageController = TextEditingController();
  final _groupNameController = TextEditingController();
  final _memberKeyController = TextEditingController();
  final _invitationController = TextEditingController();
  
  bool _isInitialized = false;
  bool _isCreatingGroup = false;
  bool _isInvitingMember = false;
  bool _isSendingMessage = false;
  String _statusMessage = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _eventSubscription?.cancel();
    _groupChatService.dispose();
    _transportManager.dispose();
    _messageController.dispose();
    _groupNameController.dispose();
    _memberKeyController.dispose();
    _invitationController.dispose();
    super.dispose();
  }

  Future<void> _initializeServices() async {
    try {
      setState(() {
        _statusMessage = 'Initializing encryption service...';
      });

      // Initialize encryption service
      _encryptionService = EncryptionService();
      await _encryptionService.initialize();

      setState(() {
        _statusMessage = 'Initializing transport manager...';
      });

      // Initialize transport manager
      _transportManager = TransportManager();
      
      // Register available transports
      if (await _isTransportAvailable('BLE')) {
        await _transportManager.registerTransport(BleTransport());
      }
      
      if (await _isTransportAvailable('LibP2P')) {
        await _transportManager.registerTransport(LibP2PTransport());
      }
      
      if (await _isTransportAvailable('LoRa')) {
        await _transportManager.registerTransport(LoRaTransport());
      }

      await _transportManager.initializeAllTransports();

      setState(() {
        _statusMessage = 'Initializing group chat service...';
      });

      // Initialize group chat service
      _groupChatService = GroupChatService(
        encryptionService: _encryptionService,
        transportManager: _transportManager,
      );

      // Listen to group events
      _messageSubscription = _groupChatService.groupMessageStream.listen(
        _handleGroupMessage,
      );
      
      _eventSubscription = _groupChatService.groupEventStream.listen(
        _handleGroupEvent,
      );

      // Load my groups
      await _loadMyGroups();

      setState(() {
        _isInitialized = true;
        _statusMessage = 'Ready';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Initialization failed: $e';
      });
    }
  }

  Future<bool> _isTransportAvailable(String transportType) async {
    // Simple check - in a real app, you'd check actual device capabilities
    return true; // Assume all transports are available for this example
  }

  Future<void> _loadMyGroups() async {
    try {
      final groups = await _groupChatService.getMyGroups();
      setState(() {
        _myGroups = groups;
      });
    } catch (e) {
      print('Failed to load groups: $e');
    }
  }

  void _handleGroupMessage(GroupMessage message) async {
    try {
      // Decrypt the message
      final decryptedData = await _groupChatService.decryptGroupMessage(message);
      final messageText = utf8.decode(decryptedData);
      
      setState(() {
        _messages.add(message.copyWith(
          encryptedData: messageText, // Store decrypted text for display
        ));
      });
      
      // Show notification for messages in current group
      if (message.groupId == _currentGroupId) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('New message from group member'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Failed to decrypt message: $e');
    }
  }

  void _handleGroupEvent(GroupEvent event) async {
    switch (event.type) {
      case GroupEventType.memberJoined:
        await _loadMyGroups(); // Refresh group list
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('New member joined a group')),
        );
        break;
      case GroupEventType.memberLeft:
        await _loadMyGroups();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('A member left a group')),
        );
        break;
      case GroupEventType.keyRotated:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Group key was rotated - re-authenticate')),
        );
        break;
      default:
        print('Group event: ${event.type}');
    }
  }

  Future<void> _createGroup() async {
    if (_groupNameController.text.isEmpty) return;

    setState(() {
      _isCreatingGroup = true;
      _statusMessage = 'Creating group...';
    });

    try {
      final groupInfo = await _groupChatService.createGroup(
        _groupNameController.text,
        description: 'Example group created via app',
      );

      await _loadMyGroups();
      
      setState(() {
        _currentGroupId = groupInfo.id;
        _messages.clear();
      });

      _groupNameController.clear();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Group created successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create group: $e')),
      );
    } finally {
      setState(() {
        _isCreatingGroup = false;
        _statusMessage = 'Ready';
      });
    }
  }

  Future<void> _inviteMember() async {
    if (_currentGroupId == null || _memberKeyController.text.isEmpty) return;

    setState(() {
      _isInvitingMember = true;
      _statusMessage = 'Inviting member...';
    });

    try {
      // Parse the public key from QR code data or manual input
      Uint8List memberPublicKey;
      if (_memberKeyController.text.startsWith('MESH_PUBLIC_KEY:')) {
        memberPublicKey = EncryptionService.parsePublicKeyFromQr(_memberKeyController.text);
      } else {
        // Assume it's base64 encoded
        memberPublicKey = base64Decode(_memberKeyController.text);
      }

      await _groupChatService.inviteMember(_currentGroupId!, memberPublicKey);
      
      _memberKeyController.clear();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invitation sent successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to invite member: $e')),
      );
    } finally {
      setState(() {
        _isInvitingMember = false;
        _statusMessage = 'Ready';
      });
    }
  }

  Future<void> _sendMessage() async {
    if (_currentGroupId == null || _messageController.text.isEmpty) return;

    setState(() {
      _isSendingMessage = true;
      _statusMessage = 'Sending message...';
    });

    try {
      final messageData = utf8.encode(_messageController.text);
      await _groupChatService.sendGroupMessage(_currentGroupId!, messageData);
      
      _messageController.clear();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Message sent!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send message: $e')),
      );
    } finally {
      setState(() {
        _isSendingMessage = false;
        _statusMessage = 'Ready';
      });
    }
  }

  Future<void> _acceptInvitation() async {
    if (_invitationController.text.isEmpty) return;

    try {
      final invitationData = jsonDecode(_invitationController.text);
      final invitation = GroupInvitation.fromJson(invitationData);
      
      final groupInfo = await _groupChatService.acceptInvitation(invitation);
      
      await _loadMyGroups();
      
      setState(() {
        _currentGroupId = groupInfo.id;
        _messages.clear();
      });
      
      _invitationController.clear();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Successfully joined group: ${groupInfo.name}!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to accept invitation: $e')),
      );
    }
  }

  void _selectGroup(String groupId) {
    setState(() {
      _currentGroupId = groupId;
      _messages.clear();
    });
  }

  Future<void> _leaveGroup() async {
    if (_currentGroupId == null) return;

    try {
      await _groupChatService.leaveGroup(_currentGroupId!);
      await _loadMyGroups();
      
      setState(() {
        _currentGroupId = null;
        _messages.clear();
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Left group successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to leave group: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        appBar: AppBar(title: Text('Group Chat Example')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(_statusMessage),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Secure Group Chat'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadMyGroups,
          ),
          IconButton(
            icon: Icon(Icons.qr_code),
            onPressed: _showQrDialog,
          ),
        ],
      ),
      body: Row(
        children: [
          // Group list sidebar
          Container(
            width: 250,
            child: _buildGroupList(),
          ),
          // Main chat area
          Expanded(
            child: Column(
              children: [
                // Status bar
                Container(
                  padding: EdgeInsets.all(8),
                  color: Colors.grey[200],
                  child: Row(
                    children: [
                      Icon(Icons.circle, color: Colors.green, size: 12),
                      SizedBox(width: 8),
                      Text(_statusMessage),
                    ],
                  ),
                ),
                // Messages area
                Expanded(
                  child: _currentGroupId != null 
                      ? _buildMessagesArea()
                      : _buildWelcomeScreen(),
                ),
                // Message input
                if (_currentGroupId != null) _buildMessageInput(),
              ],
            ),
          ),
        ],
      ),
      // Floating action buttons for group management
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "create_group",
            onPressed: _showCreateGroupDialog,
            child: Icon(Icons.add_group),
            tooltip: 'Create Group',
          ),
          SizedBox(height: 8),
          FloatingActionButton(
            heroTag: "join_group",
            onPressed: _showJoinGroupDialog,
            child: Icon(Icons.group_add),
            tooltip: 'Join Group',
          ),
        ],
      ),
    );
  }

  Widget _buildGroupList() {
    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('My Groups', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text('${_myGroups.length} groups'),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _myGroups.length,
              itemBuilder: (context, index) {
                final group = _myGroups[index];
                final isSelected = group.id == _currentGroupId;
                
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(group.name[0].toUpperCase()),
                    backgroundColor: isSelected ? Colors.blue : Colors.grey,
                  ),
                  title: Text(group.name),
                  subtitle: Text('${group.members.length} members'),
                  selected: isSelected,
                  onTap: () => _selectGroup(group.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesArea() {
    return Column(
      children: [
        // Group info header
        if (_currentGroupId != null) _buildGroupHeader(),
        // Messages list
        Expanded(
          child: ListView.builder(
            reverse: true,
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final message = _messages[_messages.length - 1 - index];
              return _buildMessageTile(message);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildGroupHeader() {
    return Container(
      padding: EdgeInsets.all(16),
      color: Colors.blue[50],
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _myGroups.firstWhere((g) => g.id == _currentGroupId).name,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Secure group chat with ${_myGroups.firstWhere((g) => g.id == _currentGroupId).members.length} members',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.exit_to_app),
            onPressed: _leaveGroup,
            tooltip: 'Leave Group',
          ),
        ],
      ),
    );
  }

  Widget _buildMessageTile(GroupMessage message) {
    final isMyMessage = false; // In a real app, compare with own public key
    
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: isMyMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isMyMessage ? Colors.blue : Colors.grey[300],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.encryptedData,
                  style: TextStyle(
                    color: isMyMessage ? Colors.white : Colors.black87,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: isMyMessage ? Colors.white70 : Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          SizedBox(width: 8),
          IconButton(
            icon: _isSendingMessage 
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.send),
            onPressed: _isSendingMessage ? null : _sendMessage,
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'Welcome to Secure Group Chat',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'Create a new group or join an existing one to start chatting',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  void _showCreateGroupDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Create New Group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _groupNameController,
              decoration: InputDecoration(
                labelText: 'Group Name',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _isCreatingGroup ? null : () {
              Navigator.of(context).pop();
              _createGroup();
            },
            child: _isCreatingGroup 
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showJoinGroupDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Join Group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Paste the group invitation data:',
              style: TextStyle(fontSize: 14),
            ),
            SizedBox(height: 8),
            TextField(
              controller: _invitationController,
              decoration: InputDecoration(
                hintText: 'Group invitation JSON...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _acceptInvitation();
            },
            child: Text('Join'),
          ),
        ],
      ),
    );
  }

  void _showQrDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('My Public Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Share this QR code or key with others to invite you to groups:',
              style: TextStyle(fontSize: 14),
            ),
            SizedBox(height: 16),
            FutureBuilder<String>(
              future: _encryptionService.getPublicKeyQrString(),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return SelectableText(
                    snapshot.data!,
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                  );
                } else {
                  return CircularProgressIndicator();
                }
              },
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }
}