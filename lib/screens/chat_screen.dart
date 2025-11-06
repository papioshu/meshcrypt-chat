import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/encryption_service.dart';
import '../services/bluetooth_service.dart';
import '../services/database_service.dart';
import '../models/contact_model.dart';
import '../models/message_model.dart';

class ChatScreen extends StatefulWidget {
  final ContactModel contact;
  final EncryptionService encryptionService;
  final BluetoothService bluetoothService;
  final DatabaseService databaseService;

  const ChatScreen({
    super.key,
    required this.contact,
    required this.encryptionService,
    required this.bluetoothService,
    required this.databaseService,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _cursorVisible = true;
  Timer? _cursorTimer;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _startCursorBlink();
    _initializeChat();
    _listenForMessages();
  }

  void _startCursorBlink() {
    _cursorTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      setState(() {
        _cursorVisible = !_cursorVisible;
      });
    });
  }

  Future<void> _initializeChat() async {
    // Load existing messages from database
    final messages = await widget.databaseService.getMessagesForContact(widget.contact.id);
    setState(() {
      _messages.addAll(messages);
    });
    
    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    // Check connection status
    _checkConnectionStatus();
  }

  void _checkConnectionStatus() async {
    final isConnected = await widget.bluetoothService.isConnectedToDevice(widget.contact.deviceId);
    setState(() {
      _isConnected = isConnected;
    });
  }

  void _listenForMessages() {
    widget.bluetoothService.messageStream.listen((encryptedData) async {
      try {
        // Decrypt the message
        final sharedSecret = await widget.encryptionService.deriveSharedSecret(
          base64Decode(widget.contact.publicKey)
        );
        
        final decrypted = widget.encryptionService.decrypt(encryptedData, sharedSecret);
        if (decrypted != null) {
          final messageText = utf8.decode(decrypted);
          
          final message = ChatMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            senderId: widget.contact.id,
            receiverId: 'self',
            content: messageText,
            timestamp: DateTime.now(),
            isSent: false,
            isEncrypted: true,
          );

          // Save to database
          await widget.databaseService.saveMessage(message);
          
          setState(() {
            _messages.add(message);
          });

          // Scroll to bottom
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          });
        }
      } catch (e) {
        debugPrint('Error decrypting message: $e');
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    try {
      // Encrypt the message
      final sharedSecret = await widget.encryptionService.deriveSharedSecret(
        base64Decode(widget.contact.publicKey)
      );
      
      final encrypted = widget.encryptionService.encrypt(
        Uint8List.fromList(text.codeUnits), 
        sharedSecret
      );

      // Send via Bluetooth
      await widget.bluetoothService.sendMessage(widget.contact.deviceId, encrypted);

      // Create and save local message
      final message = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        senderId: 'self',
        receiverId: widget.contact.id,
        content: text,
        timestamp: DateTime.now(),
        isSent: true,
        isEncrypted: true,
      );

      await widget.databaseService.saveMessage(message);

      setState(() {
        _messages.add(message);
        _controller.clear();
      });

      // Scroll to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });

    } catch (e) {
      debugPrint('Error sending message: $e');
      _showError('Failed to send message: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade400,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _clearChat() async {
    await widget.databaseService.clearMessagesForContact(widget.contact.id);
    setState(() {
      _messages.clear();
    });
  }

  @override
  void dispose() {
    _cursorTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cursor = _cursorVisible ? "█" : " ";
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: SafeArea(
        child: Column(
          children: [
            // Terminal-style header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0A),
                border: Border(
                  bottom: BorderSide(color: Colors.green.shade400, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 12,
                    color: _isConnected ? Colors.green.shade400 : Colors.red.shade400,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'mesh-chat@${widget.contact.alias}',
                      style: GoogleFonts.robotoMono(
                        color: Colors.green.shade400,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Text(
                    '[${widget.contact.id.substring(0, 8)}]',
                    style: GoogleFonts.robotoMono(
                      color: Colors.grey.shade400,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Messages area
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                child: _messages.isEmpty 
                  ? _buildEmptyState()
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[index];
                        return _buildMessage(message);
                      },
                    ),
              ),
            ),

            // Terminal-style input area
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0A),
                border: Border(
                  top: BorderSide(color: Colors.green.shade400, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '> ',
                    style: GoogleFonts.robotoMono(
                      color: Colors.green.shade400,
                      fontSize: 18,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: GoogleFonts.robotoMono(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                      cursorColor: Colors.green.shade400,
                      decoration: InputDecoration(
                        hintText: _isConnected ? 'Type your encrypted message...' : 'No connection available',
                        hintStyle: GoogleFonts.robotoMono(
                          color: Colors.grey.shade600,
                          fontSize: 16,
                        ),
                        border: InputBorder.none,
                        enabled: _isConnected,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  Text(
                    cursor,
                    style: GoogleFonts.robotoMono(
                      color: Colors.green.shade400,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _isConnected ? _sendMessage : null,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _isConnected ? Colors.green.shade400 : Colors.grey.shade600,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        Icons.send,
                        color: Colors.black,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: Colors.green.shade400.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: GoogleFonts.robotoMono(
              color: Colors.grey.shade400,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a secure conversation with ${widget.contact.alias}',
            style: GoogleFonts.robotoMono(
              color: Colors.grey.shade600,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(ChatMessage message) {
    final isSent = message.isSent;
    final timestamp = '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isSent ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isSent) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.blue.shade400,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSent 
                  ? Colors.green.shade400.withOpacity(0.2)
                  : Colors.blue.shade400.withOpacity(0.2),
                border: Border(
                  left: BorderSide(
                    color: isSent ? Colors.green.shade400 : Colors.blue.shade400,
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.content,
                    style: GoogleFonts.robotoMono(
                      color: isSent ? Colors.green.shade100 : Colors.blue.shade100,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        timestamp,
                        style: GoogleFonts.robotoMono(
                          color: Colors.grey.shade500,
                          fontSize: 10,
                        ),
                      ),
                      if (message.isEncrypted) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.lock,
                          size: 12,
                          color: Colors.yellow.shade400,
                        ),
                      ],
                      if (message.isSent) ...[
                        const SizedBox(width: 4),
                        Icon(
                          message.isDelivered ? Icons.done_all : Icons.done,
                          size: 12,
                          color: message.isDelivered ? Colors.blue.shade400 : Colors.grey.shade500,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isSent) ...[
            const SizedBox(width: 8),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.green.shade400,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Extended message model for chat screen
class ChatMessage extends MessageModel {
  final bool isEncrypted;
  final bool isDelivered;
  final bool isSent;

  ChatMessage({
    required String id,
    required String senderId,
    required String receiverId,
    required String content,
    required DateTime timestamp,
    this.isEncrypted = false,
    this.isDelivered = false,
    this.isSent = false,
  }) : super(
          id: id,
          senderId: senderId,
          receiverId: receiverId,
          content: content,
          timestamp: timestamp,
        );
}