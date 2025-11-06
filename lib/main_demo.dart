import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/encryption_service.dart';
import 'services/bluetooth_service.dart';
import 'services/database_service.dart';
import 'models/contact_model.dart';
import 'screens/chat_screen.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => EncryptionService()),
        ChangeNotifierProvider(create: (_) => BluetoothService()),
        ChangeNotifierProvider(create: (_) => DatabaseService()),
      ],
      child: MaterialApp(
        title: 'Encrypted Mesh Chat',
        theme: ThemeData(
          primarySwatch: Colors.green,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: ChatDemo(),
      ),
    );
  }
}

class ChatDemo extends StatefulWidget {
  @override
  _ChatDemoState createState() => _ChatDemoState();
}

class _ChatDemoState extends State<ChatDemo> {
  ContactModel? _selectedContact;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          'Mesh Chat Demo',
          style: TextStyle(
            fontFamily: 'Courier',
            color: Colors.green.shade400,
          ),
        ),
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.green.shade400),
      ),
      body: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTerminalHeader(),
            const SizedBox(height: 30),
            _buildDemoInstructions(),
            const SizedBox(height: 30),
            _buildContactSelection(),
            const SizedBox(height: 30),
            if (_selectedContact != null) ...[
              _buildStartChatButton(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTerminalHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        border: Border(
          left: BorderSide(color: Colors.green.shade400, width: 4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '> mesh-chat --secure-terminal-v1.0',
            style: TextStyle(
              fontFamily: 'Courier',
              color: Colors.green.shade400,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '> status: initialized',
            style: TextStyle(
              fontFamily: 'Courier',
              color: Colors.green.shade300,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDemoInstructions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '📋 Demo Instructions:',
            style: TextStyle(
              fontFamily: 'Courier',
              color: Colors.blue.shade400,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '1. Select a demo contact below\n'
            '2. Tap "Start Secure Chat" to open terminal\n'
            '3. Type messages - they will be encrypted\n'
            '4. Messages are stored locally only\n'
            '5. Uses Bluetooth LE for peer-to-peer',
            style: TextStyle(
              fontFamily: 'Courier',
              color: Colors.grey.shade300,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactSelection() {
    final demoContacts = [
      ContactModel(
        id: 'demo-001',
        alias: 'Alice-Node',
        publicKey: 'YWxpY2UtcHVibGljLWtleS0xMjM0NTY3ODkwMTIzNDU2Nzg5MA==',
        deviceId: 'demo-device-001',
        lastSeen: DateTime.now(),
        trustLevel: TrustLevel.verified,
      ),
      ContactModel(
        id: 'demo-002',
        alias: 'Bob-Terminal',
        publicKey: 'Ym9iLXB1YmxpYy1rZXktYWJjZGVmZ2hpams=',
        deviceId: 'demo-device-002',
        lastSeen: DateTime.now().subtract(const Duration(minutes: 5)),
        trustLevel: TrustLevel.known,
      ),
      ContactModel(
        id: 'demo-003',
        alias: 'Crypto-Peer',
        publicKey: 'Y3J5cHRvLXBlZXItZ2hpa3psbQ==',
        deviceId: 'demo-device-003',
        lastSeen: DateTime.now().subtract(const Duration(hours: 2)),
        trustLevel: TrustLevel.untrusted,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '🔍 Available Contacts:',
          style: TextStyle(
            fontFamily: 'Courier',
            color: Colors.yellow.shade400,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...demoContacts.map((contact) => _buildContactCard(contact)).toList(),
      ],
    );
  }

  Widget _buildContactCard(ContactModel contact) {
    final isSelected = _selectedContact?.id == contact.id;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSelected 
          ? Colors.green.shade400.withOpacity(0.2)
          : const Color(0xFF1A1A1A),
        border: Border(
          left: BorderSide(
            color: isSelected ? Colors.green.shade400 : Colors.grey.shade600,
            width: 3,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.alias,
                  style: TextStyle(
                    fontFamily: 'Courier',
                    color: isSelected ? Colors.green.shade100 : Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Trust: ${contact.trustLevel.name}',
                  style: TextStyle(
                    fontFamily: 'Courier',
                    color: Colors.grey.shade400,
                    fontSize: 10,
                  ),
                ),
                Text(
                  'Last seen: ${_formatTimeAgo(contact.lastSeen)}',
                  style: TextStyle(
                    fontFamily: 'Courier',
                    color: Colors.grey.shade500,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: _getTrustColor(contact.trustLevel),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartChatButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _openChatScreen,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green.shade400,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(0),
          ),
        ),
        child: Text(
          '> START SECURE CHAT',
          style: TextStyle(
            fontFamily: 'Courier',
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  void _openChatScreen() {
    if (_selectedContact == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          contact: _selectedContact!,
          encryptionService: context.read<EncryptionService>(),
          bluetoothService: context.read<BluetoothService>(),
          databaseService: context.read<DatabaseService>(),
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }

  Color _getTrustColor(TrustLevel trustLevel) {
    switch (trustLevel) {
      case TrustLevel.verified:
        return Colors.green.shade400;
      case TrustLevel.known:
        return Colors.yellow.shade400;
      case TrustLevel.untrusted:
        return Colors.red.shade400;
    }
  }
}