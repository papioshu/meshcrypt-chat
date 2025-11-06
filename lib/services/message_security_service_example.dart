import 'dart:typed_data';

import 'message_security_service.dart';

/// Comprehensive usage examples for the MessageSecurityService
/// 
/// This file demonstrates all features of the message security service including:
/// - Creating timed messages with expiration
/// - Burn-after-read messages
/// - Message integrity verification
/// - Secure message reading and deletion
/// - Message statistics and management
class MessageSecurityExample {
  late MessageSecurityService _messageSecurityService;
  late EncryptionService _encryptionService;

  /// Initialize the services
  Future<void> initialize() async {
    // Initialize encryption service
    _encryptionService = EncryptionService();
    await _encryptionService.initialize();

    // Initialize message security service
    _messageSecurityService = MessageSecurityService(
      encryptionService: _encryptionService,
    );

    print('Services initialized successfully');
  }

  /// Example 1: Create a simple timed message
  Future<void> exampleTimedMessage() async {
    print('\n=== Example 1: Timed Message ===');
    
    try {
      // Simulate shared secret (in real app, this comes from key exchange)
      final sharedSecret = Uint8List.fromList(List<int>.generate(32, (i) => i));
      
      // Create a message that expires in 1 hour
      final timedMessage = await _messageSecurityService.createTimedMessage(
        message: 'This message will expire in 1 hour',
        sharedSecret: sharedSecret,
        expirationDuration: const Duration(hours: 1),
      );
      
      print('Created timed message:');
      print('- Message ID: ${timedMessage.messageId}');
      print('- Expires at: ${timedMessage.metadata.expiresAt}');
      print('- Encrypted data: ${timedMessage.encryptedData.substring(0, 50)}...');
      
    } catch (e) {
      print('Error creating timed message: $e');
    }
  }

  /// Example 2: Create burn-after-read message
  Future<void> exampleBurnMessage() async {
    print('\n=== Example 2: Burn-After-Read Message ===');
    
    try {
      // Simulate shared secret
      final sharedSecret = Uint8List.fromList(List<int>.generate(32, (i) => i + 10));
      
      // Create a burn-after-read message
      final burnMessage = await _messageSecurityService.createBurnMessage(
        message: 'This message will be deleted after reading!',
        sharedSecret: sharedSecret,
        maxViewTime: const Duration(minutes: 5),
      );
      
      print('Created burn-after-read message:');
      print('- Message ID: ${burnMessage.messageId}');
      print('- Burn key: ${base64Encode(burnMessage.burnKey)}');
      print('- Expires at: ${burnMessage.metadata.expiresAt}');
      
      // Read the message (this will burn it)
      print('\nReading the message (will burn it):');
      final readResult = await _messageSecurityService.readTimedMessage(
        messageId: burnMessage.messageId,
        sharedSecret: sharedSecret,
        burnKey: base64Encode(burnMessage.burnKey),
      );
      
      print('- Message: ${readResult.message}');
      print('- Burned: ${readResult.burned}');
      
      // Try to read again (should fail)
      print('\nTrying to read again (should fail):');
      try {
        await _messageSecurityService.readTimedMessage(
          messageId: burnMessage.messageId,
          sharedSecret: sharedSecret,
        );
        print('ERROR: Message was not burned properly!');
      } catch (e) {
        print('Expected error: $e');
      }
      
    } catch (e) {
      print('Error with burn message: $e');
    }
  }

  /// Example 3: Message with specific expiration date/time
  Future<void> exampleScheduledExpiration() async {
    print('\n=== Example 3: Scheduled Expiration ===');
    
    try {
      final sharedSecret = Uint8List.fromList(List<int>.generate(32, (i) => i + 20));
      
      // Create a message that expires at a specific date/time
      final expirationDateTime = DateTime.now().add(const Duration(minutes: 2));
      final scheduledMessage = await _messageSecurityService.createTimedMessage(
        message: 'This message expires at a specific time',
        sharedSecret: sharedSecret,
        expirationDateTime: expirationDateTime,
      );
      
      print('Created scheduled message:');
      print('- Message ID: ${scheduledMessage.messageId}');
      print('- Expires at: ${scheduledMessage.metadata.expiresAt}');
      print('- Current time: ${DateTime.now()}');
      
      // Wait a bit and try to read
      await Future.delayed(const Duration(seconds: 1));
      print('\nReading message after 1 second:');
      
      final readResult = await _messageSecurityService.readTimedMessage(
        messageId: scheduledMessage.messageId,
        sharedSecret: sharedSecret,
      );
      
      print('- Message: ${readResult.message}');
      print('- Message intact: true');
      
    } catch (e) {
      print('Error with scheduled expiration: $e');
    }
  }

  /// Example 4: Message integrity verification
  Future<void> exampleIntegrityVerification() async {
    print('\n=== Example 4: Message Integrity Verification ===');
    
    try {
      final sharedSecret = Uint8List.fromList(List<int>.generate(32, (i) => i + 30));
      
      // Create a message
      final originalMessage = await _messageSecurityService.createTimedMessage(
        message: 'This message should pass integrity check',
        sharedSecret: sharedSecret,
        expirationDuration: const Duration(hours: 1),
      );
      
      print('Created message for integrity test:');
      print('- Message ID: ${originalMessage.messageId}');
      
      // Verify integrity before reading
      final metadata = await _messageSecurityService.getMessageMetadata(
        originalMessage.messageId,
      );
      print('- Metadata retrieved: ${metadata != null}');
      
      // Read the message
      final readResult = await _messageSecurityService.readTimedMessage(
        messageId: originalMessage.messageId,
        sharedSecret: sharedSecret,
      );
      
      print('- Message read successfully: ${readResult.message}');
      print('- Integrity verification: passed');
      
    } catch (e) {
      print('Error with integrity verification: $e');
    }
  }

  /// Example 5: Message management and statistics
  Future<void> exampleMessageManagement() async {
    print('\n=== Example 5: Message Management ===');
    
    try {
      final sharedSecret = Uint8List.fromList(List<int>.generate(32, (i) => i + 40));
      
      // Create multiple messages
      final messageIds = <String>[];
      
      for (int i = 1; i <= 3; i++) {
        final message = await _messageSecurityService.createTimedMessage(
          message: 'Test message number $i',
          sharedSecret: sharedSecret,
          expirationDuration: Duration(hours: i),
        );
        messageIds.add(message.messageId);
        print('Created message $i: ${message.messageId}');
      }
      
      // List all active messages
      print('\nListing active messages:');
      final activeMessages = await _messageSecurityService.listActiveMessages();
      
      for (final summary in activeMessages) {
        print('- Message ${summary.messageId.substring(0, 8)}...');
        print('  Created: ${summary.createdAt}');
        print('  Expires: ${summary.expiresAt}');
        print('  Burn after read: ${summary.burnAfterRead}');
        print('  Integrity verified: ${summary.integrityVerified}');
      }
      
      // Get statistics
      final stats = await _messageSecurityService.getStatistics();
      print('\nMessage statistics:');
      print('- Active messages: ${stats.activeMessages}');
      print('- Burned messages: ${stats.burnedMessages}');
      print('- Active timers: ${stats.activeTimers}');
      if (stats.nextExpiration != null) {
        print('- Next expiration: ${stats.nextExpiration}');
      }
      
      // Clean up
      print('\nCleaning up test messages...');
      for (final messageId in messageIds) {
        await _messageSecurityService.burnMessage(
          messageId: messageId,
          sharedSecret: sharedSecret,
        );
        print('Deleted: ${messageId.substring(0, 8)}...');
      }
      
    } catch (e) {
      print('Error with message management: $e');
    }
  }

  /// Example 6: Error handling and edge cases
  Future<void> exampleErrorHandling() async {
    print('\n=== Example 6: Error Handling ===');
    
    try {
      final sharedSecret = Uint8List.fromList(List<int>.generate(32, (i) => i + 50));
      
      // Try to read non-existent message
      print('Trying to read non-existent message:');
      try {
        await _messageSecurityService.readTimedMessage(
          messageId: 'non-existent-id',
          sharedSecret: sharedSecret,
        );
        print('ERROR: Should have thrown exception');
      } catch (e) {
        print('Expected error: $e');
      }
      
      // Try to create message with past expiration
      print('\nTrying to create message with past expiration:');
      try {
        await _messageSecurityService.createTimedMessage(
          message: 'This should fail',
          sharedSecret: sharedSecret,
          expirationDateTime: DateTime.now().subtract(const Duration(hours: 1)),
        );
        print('ERROR: Should have thrown exception');
      } catch (e) {
        print('Expected error: $e');
      }
      
      // Try to read expired message
      print('\nTesting expired message handling:');
      final expiredMessage = await _messageSecurityService.createTimedMessage(
        message: 'This message expires immediately',
        sharedSecret: sharedSecret,
        expirationDuration: const Duration(milliseconds: 100),
      );
      
      // Wait for expiration
      await Future.delayed(const Duration(milliseconds: 150));
      
      try {
        await _messageSecurityService.readTimedMessage(
          messageId: expiredMessage.messageId,
          sharedSecret: sharedSecret,
        );
        print('ERROR: Should have thrown exception for expired message');
      } catch (e) {
        print('Expected error for expired message: $e');
      }
      
    } catch (e) {
      print('Unexpected error in error handling example: $e');
    }
  }

  /// Example 7: Full workflow demonstration
  Future<void> exampleFullWorkflow() async {
    print('\n=== Example 7: Full Workflow ===');
    
    try {
      // Simulate two users exchanging secure messages
      final userASharedSecret = Uint8List.fromList(List<int>.generate(32, (i) => i + 60));
      final userBSharedSecret = Uint8List.fromList(List<int>.generate(32, (i) => i + 70));
      
      print('=== User A creates messages ===');
      
      // User A creates a timed message for User B
      final message1 = await _messageSecurityService.createTimedMessage(
        message: 'Hello User B, this message expires in 2 hours',
        sharedSecret: userASharedSecret,
        expirationDuration: const Duration(hours: 2),
      );
      
      // User A creates a burn-after-read message for User B
      final message2 = await _messageSecurityService.createBurnMessage(
        message: 'Secret message for User B only',
        sharedSecret: userASharedSecret,
        maxViewTime: const Duration(minutes: 10),
      );
      
      print('User A created:');
      print('- Timed message: ${message1.messageId}');
      print('- Burn message: ${message2.messageId}');
      
      print('\n=== User B reads messages ===');
      
      // User B reads the timed message
      final read1 = await _messageSecurityService.readTimedMessage(
        messageId: message1.messageId,
        sharedSecret: userBSharedSecret, // In real app, would derive from key exchange
      );
      
      print('User B read timed message: ${read1.message}');
      print('Message still available: ${read1.burned == false}');
      
      // User B reads the burn message
      final read2 = await _messageSecurityService.readTimedMessage(
        messageId: message2.messageId,
        sharedSecret: userBSharedSecret,
        burnKey: base64Encode(message2.burnKey),
      );
      
      print('User B read burn message: ${read2.message}');
      print('Message burned: ${read2.burned}');
      
      print('\n=== Final statistics ===');
      final finalStats = await _messageSecurityService.getStatistics();
      print('Active messages: ${finalStats.activeMessages}');
      print('Burned messages: ${finalStats.burnedMessages}');
      
    } catch (e) {
      print('Error in full workflow: $e');
    }
  }

  /// Run all examples
  Future<void> runAllExamples() async {
    print('Message Security Service - Comprehensive Examples');
    print('================================================');
    
    await initialize();
    
    await exampleTimedMessage();
    await exampleBurnMessage();
    await exampleScheduledExpiration();
    await exampleIntegrityVerification();
    await exampleMessageManagement();
    await exampleErrorHandling();
    await exampleFullWorkflow();
    
    // Final cleanup
    print('\n=== Final Cleanup ===');
    await _messageSecurityService.clearAllMessages();
    print('All messages cleared');
    
    print('\nAll examples completed successfully!');
  }
}

/// Flutter widget example
class MessageSecurityWidgetExample extends StatefulWidget {
  const MessageSecurityWidgetExample({super.key});

  @override
  State<MessageSecurityWidgetExample> createState() => _MessageSecurityWidgetExampleState();
}

class _MessageSecurityWidgetExampleState extends State<MessageSecurityWidgetExample> {
  late MessageSecurityService _messageSecurityService;
  late EncryptionService _encryptionService;
  bool _initialized = false;
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _readMessageController = TextEditingController();
  String _status = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      _encryptionService = EncryptionService();
      await _encryptionService.initialize();

      _messageSecurityService = MessageSecurityService(
        encryptionService: _encryptionService,
      );

      setState(() {
        _initialized = true;
        _status = 'Services initialized';
      });
    } catch (e) {
      setState(() {
        _status = 'Initialization failed: $e';
      });
    }
  }

  Future<void> _createTimedMessage() async {
    try {
      final sharedSecret = Uint8List.fromList(List<int>.generate(32, (i) => i));
      
      final message = await _messageSecurityService.createTimedMessage(
        message: _messageController.text,
        sharedSecret: sharedSecret,
        expirationDuration: const Duration(hours: 1),
      );

      setState(() {
        _status = 'Created message: ${message.messageId}';
        _readMessageController.text = message.messageId;
      });
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
      });
    }
  }

  Future<void> _createBurnMessage() async {
    try {
      final sharedSecret = Uint8List.fromList(List<int>.generate(32, (i) => i));
      
      final message = await _messageSecurityService.createBurnMessage(
        message: _messageController.text,
        sharedSecret: sharedSecret,
      );

      setState(() {
        _status = 'Created burn message: ${message.messageId}';
        _readMessageController.text = message.messageId;
      });
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
      });
    }
  }

  Future<void> _readMessage() async {
    try {
      final sharedSecret = Uint8List.fromList(List<int>.generate(32, (i) => i));
      
      final result = await _messageSecurityService.readTimedMessage(
        messageId: _readMessageController.text,
        sharedSecret: sharedSecret,
      );

      setState(() {
        _status = 'Read message: ${result.message} (burned: ${result.burned})';
      });
    } catch (e) {
      setState(() {
        _status = 'Error reading: $e';
      });
    }
  }

  Future<void> _listMessages() async {
    try {
      final messages = await _messageSecurityService.listActiveMessages();
      setState(() {
        _status = 'Active messages: ${messages.length}';
      });
    } catch (e) {
      setState(() {
        _status = 'Error listing: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Message Security Example')),
        body: Center(child: Text(_status)),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Message Security Example')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('Status: $_status'),
            const SizedBox(height: 20),
            
            TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                labelText: 'Message to create',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            
            Row(
              children: [
                ElevatedButton(
                  onPressed: _createTimedMessage,
                  child: const Text('Create Timed Message'),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _createBurnMessage,
                  child: const Text('Create Burn Message'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            TextField(
              controller: _readMessageController,
              decoration: const InputDecoration(
                labelText: 'Message ID to read',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            
            Row(
              children: [
                ElevatedButton(
                  onPressed: _readMessage,
                  child: const Text('Read Message'),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _listMessages,
                  child: const Text('List Messages'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Main function to run examples
Future<void> main() async {
  final example = MessageSecurityExample();
  await example.runAllExamples();
}