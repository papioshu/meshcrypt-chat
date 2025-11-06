/// Unit Tests for Offline Queue Service
/// 
/// This test file demonstrates the functionality of the OfflineQueueService
/// and provides a starting point for comprehensive testing.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import '../services/offline_queue_service.dart';
import '../services/transport.dart';

void main() {
  group('OfflineQueueService Tests', () {
    late OfflineQueueService queueService;
    
    setUp(() async {
      // Initialize the service for testing
      await OfflineQueueService.initialize();
      queueService = OfflineQueueService.instance;
    });
    
    tearDown(() async {
      // Clean up after tests
      await queueService.clearAllQueuedMessages();
      queueService.dispose();
    });
    
    test('Should initialize service successfully', () async {
      expect(queueService.isInitialized, true);
      expect(queueService.queueSize, 0);
      expect(queueService.isProcessing, false);
    });
    
    test('Should queue message successfully', () async {
      final target = TransportTarget(
        id: 'test_device_1',
        address: '00:11:22:33:44:55',
        name: 'Test Device',
      );
      
      final content = Uint8List.fromList(utf8.encode('Test message'));
      
      final messageId = await queueService.queueMessage(
        target: target,
        content: content,
        priority: MessagePriority.normal,
      );
      
      expect(messageId, isNotNull);
      expect(queueService.queueSize, 1);
    });
    
    test('Should deduplicate identical messages', () async {
      final target = TransportTarget(
        id: 'test_device_2',
        address: '00:11:22:33:44:66',
        name: 'Test Device 2',
      );
      
      final content = Uint8List.fromList(utf8.encode('Duplicate test'));
      
      // Queue first message
      final messageId1 = await queueService.queueMessage(
        target: target,
        content: content,
      );
      
      // Queue identical message (should be deduplicated)
      final messageId2 = await queueService.queueMessage(
        target: target,
        content: content,
      );
      
      expect(messageId1, isNotNull);
      expect(messageId2, isNull); // Should be null due to deduplication
      expect(queueService.queueSize, 1); // Only one message in queue
    });
    
    test('Should handle different priority levels', () async {
      final target = TransportTarget(
        id: 'test_device_3',
        address: '00:11:22:33:44:77',
        name: 'Test Device 3',
      );
      
      final messages = [
        ('Low priority', MessagePriority.low),
        ('Normal priority', MessagePriority.normal),
        ('High priority', MessagePriority.high),
        ('Urgent priority', MessagePriority.urgent),
      ];
      
      // Queue messages in random order
      await queueService.queueMessage(
        target: target,
        content: Uint8List.fromList(utf8.encode(messages[3][0])),
        priority: messages[3][1],
      );
      
      await queueService.queueMessage(
        target: target,
        content: Uint8List.fromList(utf8.encode(messages[1][0])),
        priority: messages[1][1],
      );
      
      await queueService.queueMessage(
        target: target,
        content: Uint8List.fromList(utf8.encode(messages[0][0])),
        priority: messages[0][1],
      );
      
      await queueService.queueMessage(
        target: target,
        content: Uint8List.fromList(utf8.encode(messages[2][0])),
        priority: messages[2][1],
      );
      
      expect(queueService.queueSize, 4);
      
      // Verify priority ordering would work correctly
      final queuedMessages = queueService.getQueuedMessages();
      expect(queuedMessages, hasLength(4));
      
      // Messages should be retrievable
      for (final message in queuedMessages) {
        expect(message.id, isNotEmpty);
        expect(message.priority, isA<MessagePriority>());
      }
    });
    
    test('Should generate unique message IDs', () async {
      final target1 = TransportTarget(
        id: 'device_1',
        address: '00:11:22:33:44:88',
      );
      
      final target2 = TransportTarget(
        id: 'device_2',
        address: '00:11:22:33:44:99',
      );
      
      final content = Uint8List.fromList(utf8.encode('Test content'));
      
      final messageId1 = await queueService.queueMessage(
        target: target1,
        content: content,
      );
      
      final messageId2 = await queueService.queueMessage(
        target: target2,
        content: content,
      );
      
      expect(messageId1, isNotNull);
      expect(messageId2, isNotNull);
      expect(messageId1, isNot(equals(messageId2)));
    });
    
    test('Should handle message metadata', () async {
      final target = TransportTarget(
        id: 'test_device_4',
        address: '00:11:22:33:44:AA',
        name: 'Test Device 4',
        metadata: {
          'device_type': 'smartphone',
          'protocol_version': '2.0',
        },
      );
      
      final metadata = {
        'chat_id': 'room_123',
        'message_id': 'msg_456',
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      final messageId = await queueService.queueMessage(
        target: target,
        content: Uint8List.fromList(utf8.encode('Metadata test')),
        messageType: 'chat_message',
        metadata: metadata,
        preferredTransportType: 'BLE',
        expiresIn: Duration(hours: 2),
      );
      
      expect(messageId, isNotNull);
      
      final queuedMessages = queueService.getQueuedMessages();
      expect(queuedMessages, hasLength(1));
      
      final queuedMessage = queuedMessages.first;
      expect(queuedMessage.messageType, equals('chat_message'));
      expect(queuedMessage.preferredTransportType, equals('BLE'));
      expect(queuedMessage.metadata, equals(metadata));
      expect(queuedMessage.expiresAt, isNotNull);
    });
    
    test('Should provide accurate statistics', () async {
      final stats = queueService.getCurrentStatistics();
      
      expect(stats.totalQueued, equals(0));
      expect(stats.successfullySent, equals(0));
      expect(stats.failedMessages, equals(0));
      expect(stats.currentQueueSize, equals(0));
      expect(stats.messagesByPriority, isNotNull);
      expect(stats.messagesByTransportType, isNotNull);
      expect(stats.averageQueueTime, equals(Duration.zero));
      expect(stats.totalRetries, equals(0));
      expect(stats.successRate, equals(0.0));
    });
    
    test('Should handle cancellation of messages', () async {
      final target = TransportTarget(
        id: 'test_device_5',
        address: '00:11:22:33:44:BB',
      );
      
      final messageId = await queueService.queueMessage(
        target: target,
        content: Uint8List.fromList(utf8.encode('Cancel test')),
      );
      
      expect(messageId, isNotNull);
      expect(queueService.queueSize, 1);
      
      await queueService.cancelQueuedMessage(messageId!);
      
      expect(queueService.queueSize, 0);
    });
    
    test('Should handle service disposal properly', () async {
      expect(queueService.isInitialized, true);
      
      queueService.dispose();
      
      expect(queueService.isInitialized, false);
    });
  });
  
  group('Message Processing Logic Tests', () {
    test('Should calculate retry delays correctly', () {
      final message = QueuedMessage(
        id: 'test_msg',
        target: TransportTarget(id: 'device', address: '00:11:22:33:44:CC'),
        encryptedContent: 'encrypted_content',
        priority: MessagePriority.normal,
        createdAt: DateTime.now(),
        contentHash: 'hash123',
        attemptCount: 0,
        maxAttempts: 3,
        backoffMultiplier: 2,
      );
      
      // First retry: 2^0 = 1 second
      var delay = message.getRetryDelay();
      expect(delay, equals(Duration(seconds: 1)));
      
      // Second retry: 2^1 = 2 seconds
      message.copyWith(attemptCount: 1);
      delay = message.getRetryDelay();
      expect(delay, equals(Duration(seconds: 2)));
      
      // Third retry: 2^2 = 4 seconds
      message.copyWith(attemptCount: 2);
      delay = message.getRetryDelay();
      expect(delay, equals(Duration(seconds: 4)));
    });
    
    test('Should identify expired messages correctly', () {
      final expiredMessage = QueuedMessage(
        id: 'expired_msg',
        target: TransportTarget(id: 'device', address: '00:11:22:33:44:DD'),
        encryptedContent: 'encrypted',
        priority: MessagePriority.normal,
        createdAt: DateTime.now(),
        contentHash: 'hash',
        expiresAt: DateTime.now().subtract(Duration(minutes: 1)),
      );
      
      final validMessage = QueuedMessage(
        id: 'valid_msg',
        target: TransportTarget(id: 'device', address: '00:11:22:33:44:EE'),
        encryptedContent: 'encrypted',
        priority: MessagePriority.normal,
        createdAt: DateTime.now(),
        contentHash: 'hash',
        expiresAt: DateTime.now().add(Duration(minutes: 1)),
      );
      
      final noExpiryMessage = QueuedMessage(
        id: 'no_expiry_msg',
        target: TransportTarget(id: 'device', address: '00:11:22:33:44:FF'),
        encryptedContent: 'encrypted',
        priority: MessagePriority.normal,
        createdAt: DateTime.now(),
        contentHash: 'hash',
      );
      
      expect(expiredMessage.isExpired, true);
      expect(validMessage.isExpired, false);
      expect(noExpiryMessage.isExpired, false);
    });
    
    test('Should determine retry eligibility correctly', () {
      // Message that should be retried
      final retryableMessage = QueuedMessage(
        id: 'retryable',
        target: TransportTarget(id: 'device', address: '00:11:22:33:44:11'),
        encryptedContent: 'encrypted',
        priority: MessagePriority.normal,
        createdAt: DateTime.now(),
        contentHash: 'hash',
        attemptCount: 2,
        maxAttempts: 5,
      );
      
      // Message that exceeded max attempts
      final exceededMessage = QueuedMessage(
        id: 'exceeded',
        target: TransportTarget(id: 'device', address: '00:11:22:33:44:22'),
        encryptedContent: 'encrypted',
        priority: MessagePriority.normal,
        createdAt: DateTime.now(),
        contentHash: 'hash',
        attemptCount: 5,
        maxAttempts: 5,
      );
      
      // Already processed message
      final processedMessage = QueuedMessage(
        id: 'processed',
        target: TransportTarget(id: 'device', address: '00:11:22:33:44:33'),
        encryptedContent: 'encrypted',
        priority: MessagePriority.normal,
        createdAt: DateTime.now(),
        contentHash: 'hash',
        isProcessed: true,
      );
      
      // Expired message
      final expiredMessage = QueuedMessage(
        id: 'expired',
        target: TransportTarget(id: 'device', address: '00:11:22:33:44:44'),
        encryptedContent: 'encrypted',
        priority: MessagePriority.normal,
        createdAt: DateTime.now(),
        contentHash: 'hash',
        expiresAt: DateTime.now().subtract(Duration(minutes: 1)),
      );
      
      expect(retryableMessage.shouldRetry, true);
      expect(exceededMessage.shouldRetry, false);
      expect(processedMessage.shouldRetry, false);
      expect(expiredMessage.shouldRetry, false);
    });
  });
  
  group('Database Integration Tests', () {
    test('Should handle database operations correctly', () async {
      await OfflineQueueService.initialize();
      final service = OfflineQueueService.instance;
      
      final target = TransportTarget(
        id: 'db_test_device',
        address: '00:11:22:33:44:55',
        name: 'Database Test Device',
      );
      
      final messageId = await service.queueMessage(
        target: target,
        content: Uint8List.fromList(utf8.encode('Database test')),
        priority: MessagePriority.high,
        messageType: 'test_message',
      );
      
      expect(messageId, isNotNull);
      
      // Simulate successful processing
      await service._markMessageAsProcessed(messageId!);
      
      // Verify message is marked as processed in database
      final queuedMessages = service.getQueuedMessages();
      final processedMessage = queuedMessages.firstWhere(
        (msg) => msg.id == messageId,
        orElse: () => throw Exception('Message not found'),
      );
      
      expect(processedMessage.isProcessed, true);
      
      await service.clearAllQueuedMessages();
      service.dispose();
    });
  });
}

// Helper function for UTF-8 encoding in tests
extension StringEncoding on String {
  List<int> get utf8Bytes => utf8.encode(this);
}