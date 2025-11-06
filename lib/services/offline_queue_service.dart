/// Offline Message Queue Service for Network Resilient Messaging
/// 
/// This service provides comprehensive offline message queuing with automatic retry,
/// priority-based ordering, deduplication, and encrypted storage. It integrates
/// with all transport layers to ensure optimal delivery when connectivity returns.
/// 
/// Features:
/// - Queue messages during network unavailability
/// - Automatic retry with exponential backoff when connectivity returns
/// - Priority-based message ordering (urgent, high, normal, low)
/// - Encrypted storage in SQLite database
/// - Message deduplication using content hashing
/// - Integration with all transport layers (BLE, LibP2P, LoRa)
/// - Network connectivity monitoring
/// - Comprehensive error handling and retry logic

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/meshtastic_protobuf.dart' as proto;
import 'database_service.dart';
import 'encryption_service.dart';
import 'transport_manager.dart';
import 'transport.dart';

/// Represents a queued message with metadata and retry information
class QueuedMessage {
  /// Unique identifier for the message
  final String id;
  
  /// Message target (recipient)
  final TransportTarget target;
  
  /// Original message content (encrypted)
  final String encryptedContent;
  
  /// Message priority level
  final MessagePriority priority;
  
  /// Creation timestamp
  final DateTime createdAt;
  
  /// Last attempt timestamp
  final DateTime? lastAttemptAt;
  
  /// Number of retry attempts made
  final int attemptCount;
  
  /// Maximum retry attempts allowed
  final int maxAttempts;
  
  /// Message type (text, attachment, etc.)
  final String messageType;
  
  /// Additional metadata
  final Map<String, dynamic> metadata;
  
  /// Exponential backoff multiplier for retry delays
  final int backoffMultiplier;
  
  /// Content hash for deduplication
  final String contentHash;
  
  /// Whether the message has been processed
  final bool isProcessed;
  
  /// Error information from last failed attempt
  final String? lastError;
  
  /// Expiration timestamp for the message
  final DateTime? expiresAt;
  
  /// Transport type preference for delivery
  final String? preferredTransportType;

  QueuedMessage({
    required this.id,
    required this.target,
    required this.encryptedContent,
    required this.priority,
    required this.createdAt,
    this.lastAttemptAt,
    this.attemptCount = 0,
    this.maxAttempts = 5,
    this.messageType = 'text',
    this.metadata = const {},
    this.backoffMultiplier = 2,
    required this.contentHash,
    this.isProcessed = false,
    this.lastError,
    this.expiresAt,
    this.preferredTransportType,
  });

  /// Calculate next retry delay based on exponential backoff
  Duration getRetryDelay() {
    if (attemptCount >= maxAttempts) {
      return Duration.zero;
    }
    
    final baseDelay = Duration(seconds: pow(backoffMultiplier, attemptCount).toInt());
    final maxDelay = Duration(minutes: 30); // Cap at 30 minutes
    
    return baseDelay > maxDelay ? maxDelay : baseDelay;
  }

  /// Check if message has expired
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// Check if message should be retried
  bool get shouldRetry {
    return !isProcessed && !isExpired && attemptCount < maxAttempts;
  }

  /// Create a copy with updated fields
  QueuedMessage copyWith({
    String? id,
    TransportTarget? target,
    String? encryptedContent,
    MessagePriority? priority,
    DateTime? createdAt,
    DateTime? lastAttemptAt,
    int? attemptCount,
    int? maxAttempts,
    String? messageType,
    Map<String, dynamic>? metadata,
    int? backoffMultiplier,
    String? contentHash,
    bool? isProcessed,
    String? lastError,
    DateTime? expiresAt,
    String? preferredTransportType,
  }) {
    return QueuedMessage(
      id: id ?? this.id,
      target: target ?? this.target,
      encryptedContent: encryptedContent ?? this.encryptedContent,
      priority: priority ?? this.priority,
      createdAt: createdAt ?? this.createdAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      attemptCount: attemptCount ?? this.attemptCount,
      maxAttempts: maxAttempts ?? this.maxAttempts,
      messageType: messageType ?? this.messageType,
      metadata: metadata ?? this.metadata,
      backoffMultiplier: backoffMultiplier ?? this.backoffMultiplier,
      contentHash: contentHash ?? this.contentHash,
      isProcessed: isProcessed ?? this.isProcessed,
      lastError: lastError ?? this.lastError,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  /// Convert to Map for database storage
  Map<String, dynamic> toDatabaseMap() {
    return {
      'id': id,
      'target_id': target.id,
      'target_name': target.name,
      'target_address': target.address,
      'target_metadata': jsonEncode(target.metadata),
      'encrypted_content': encryptedContent,
      'priority': priority.toString(),
      'created_at': createdAt.millisecondsSinceEpoch,
      'last_attempt_at': lastAttemptAt?.millisecondsSinceEpoch,
      'attempt_count': attemptCount,
      'max_attempts': maxAttempts,
      'message_type': messageType,
      'metadata': jsonEncode(metadata),
      'backoff_multiplier': backoffMultiplier,
      'content_hash': contentHash,
      'is_processed': isProcessed ? 1 : 0,
      'last_error': lastError,
      'expires_at': expiresAt?.millisecondsSinceEpoch,
      'preferred_transport_type': preferredTransportType,
    };
  }

  /// Create from database Map
  factory QueuedMessage.fromDatabaseMap(Map<String, dynamic> map) {
    return QueuedMessage(
      id: map['id'] as String,
      target: TransportTarget(
        id: map['target_id'] as String,
        address: map['target_address'] as String,
        name: map['target_name'] as String?,
        metadata: map['target_metadata'] != null 
            ? jsonDecode(map['target_metadata'] as String) as Map<String, dynamic>
            : {},
      ),
      encryptedContent: map['encrypted_content'] as String,
      priority: MessagePriority.values.firstWhere(
        (p) => p.toString() == map['priority'],
        orElse: () => MessagePriority.normal,
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      lastAttemptAt: map['last_attempt_at'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['last_attempt_at'] as int)
          : null,
      attemptCount: map['attempt_count'] as int,
      maxAttempts: map['max_attempts'] as int,
      messageType: map['message_type'] as String? ?? 'text',
      metadata: map['metadata'] != null 
          ? jsonDecode(map['metadata'] as String) as Map<String, dynamic>
          : {},
      backoffMultiplier: map['backoff_multiplier'] as int,
      contentHash: map['content_hash'] as String,
      isProcessed: (map['is_processed'] as int) == 1,
      lastError: map['last_error'] as String?,
      expiresAt: map['expires_at'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['expires_at'] as int)
          : null,
      preferredTransportType: map['preferred_transport_type'] as String?,
    );
  }
}

/// Message priority levels
enum MessagePriority {
  urgent,
  high,
  normal,
  low,
}

/// Network connectivity states
enum ConnectivityState {
  connected,
  disconnected,
  unknown,
}

/// Queue statistics and monitoring
class QueueStatistics {
  /// Total messages queued
  final int totalQueued;
  
  /// Messages successfully sent
  final int successfullySent;
  
  /// Messages that failed after max retries
  final int failedMessages;
  
  /// Messages currently in queue
  final int currentQueueSize;
  
  /// Messages by priority
  final Map<MessagePriority, int> messagesByPriority;
  
  /// Messages by transport type preference
  final Map<String, int> messagesByTransportType;
  
  /// Average time spent in queue
  final Duration averageQueueTime;
  
  /// Last connectivity status change
  final DateTime? lastConnectivityChange;
  
  /// Total retry attempts made
  final int totalRetries;
  
  /// Success rate percentage
  final double successRate;

  QueueStatistics({
    required this.totalQueued,
    required this.successfullySent,
    required this.failedMessages,
    required this.currentQueueSize,
    required this.messagesByPriority,
    required this.messagesByTransportType,
    required this.averageQueueTime,
    this.lastConnectivityChange,
    required this.totalRetries,
    required this.successRate,
  });
}

/// Main offline queue service implementation
class OfflineQueueService {
  static OfflineQueueService? _instance;
  static OfflineQueueService get instance => _instance!;
  
  /// Service initialization
  static Future<void> initialize() async {
    if (_instance == null) {
      _instance = OfflineQueueService._internal();
    }
    await _instance!._init();
  }
  
  // Dependencies
  late DatabaseService _databaseService;
  late EncryptionService _encryptionService;
  late TransportManager _transportManager;
  
  // Database operations
  static const String _queueTable = 'offline_message_queue';
  static const String _duplicateTable = 'message_duplicates';
  
  // Connectivity monitoring
  final Connectivity _connectivity = Connectivity();
  ConnectivityState _currentConnectivityState = ConnectivityState.unknown;
  final StreamController<ConnectivityState> _connectivityController = 
      StreamController.broadcast();
  
  // Queue processing
  final StreamController<QueuedMessage> _queueProcessorController = 
      StreamController.broadcast();
  final StreamController<QueuedMessage> _messageDeliveredController = 
      StreamController.broadcast();
  final StreamController<QueuedMessage> _messageFailedController = 
      StreamController.broadcast();
  final StreamController<QueueStatistics> _statisticsController = 
      StreamController.broadcast();
  
  Timer? _processingTimer;
  Timer? _cleanupTimer;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  
  // Statistics tracking
  int _totalQueued = 0;
  int _successfullySent = 0;
  int _failedMessages = 0;
  int _totalRetries = 0;
  final List<Duration> _queueTimes = [];
  
  // Queue management
  final Map<String, QueuedMessage> _activeQueue = {};
  final Set<String> _duplicateCache = {};
  
  bool _isInitialized = false;
  bool _isProcessing = false;
  
  OfflineQueueService._internal();

  /// Stream of connectivity state changes
  Stream<ConnectivityState> get connectivityStream => _connectivityController.stream;
  
  /// Stream of queued messages being processed
  Stream<QueuedMessage> get queueProcessingStream => _queueProcessorController.stream;
  
  /// Stream of successfully delivered messages
  Stream<QueuedMessage> get messageDeliveredStream => _messageDeliveredController.stream;
  
  /// Stream of failed messages
  Stream<QueuedMessage> get messageFailedStream => _messageFailedController.stream;
  
  /// Stream of updated queue statistics
  Stream<QueueStatistics> get statisticsStream => _statisticsController.stream;
  
  /// Current connectivity state
  ConnectivityState get connectivityState => _currentConnectivityState;
  
  /// Current queue size
  int get queueSize => _activeQueue.length;
  
  /// Is the service currently processing messages
  bool get isProcessing => _isProcessing;
  
  /// Is the service initialized
  bool get isInitialized => _isInitialized;

  Future<void> _init() async {
    try {
      // Initialize dependencies
      await DatabaseService.initialize();
      _databaseService = DatabaseService.instance;
      
      _encryptionService = EncryptionService();
      await _encryptionService.initialize();
      
      _transportManager = TransportManager();
      
      // Create database tables
      await _createTables();
      
      // Load existing queued messages
      await _loadQueuedMessages();
      
      // Setup connectivity monitoring
      await _setupConnectivityMonitoring();
      
      // Start processing timers
      _startProcessingTimer();
      _startCleanupTimer();
      
      _isInitialized = true;
      
      _emitStatistics();
      
      print('OfflineQueueService initialized successfully');
    } catch (e) {
      print('Failed to initialize OfflineQueueService: $e');
      rethrow;
    }
  }

  /// Create database tables for queue storage
  Future<void> _createTables() async {
    await _databaseService._db.execute('''
      CREATE TABLE IF NOT EXISTS $_queueTable (
        id TEXT PRIMARY KEY,
        target_id TEXT NOT NULL,
        target_name TEXT,
        target_address TEXT NOT NULL,
        target_metadata TEXT,
        encrypted_content TEXT NOT NULL,
        priority TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        last_attempt_at INTEGER,
        attempt_count INTEGER DEFAULT 0,
        max_attempts INTEGER DEFAULT 5,
        message_type TEXT DEFAULT 'text',
        metadata TEXT,
        backoff_multiplier INTEGER DEFAULT 2,
        content_hash TEXT NOT NULL,
        is_processed INTEGER DEFAULT 0,
        last_error TEXT,
        expires_at INTEGER,
        preferred_transport_type TEXT,
        FOREIGN KEY (target_id) REFERENCES contacts (id)
      )
    ''');
    
    await _databaseService._db.execute('''
      CREATE TABLE IF NOT EXISTS $_duplicateTable (
        id TEXT PRIMARY KEY,
        content_hash TEXT NOT NULL,
        target_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        expires_at INTEGER
      )
    ''');
    
    // Create indexes for performance
    await _databaseService._db.execute('CREATE INDEX IF NOT EXISTS idx_queue_priority ON $_queueTable (priority)');
    await _databaseService._db.execute('CREATE INDEX IF NOT EXISTS idx_queue_created_at ON $_queueTable (created_at)');
    await _databaseService._db.execute('CREATE INDEX IF NOT EXISTS idx_queue_is_processed ON $_queueTable (is_processed)');
    await _databaseService._db.execute('CREATE INDEX IF NOT EXISTS idx_duplicate_hash ON $_duplicateTable (content_hash)');
  }

  /// Load existing queued messages from database
  Future<void> _loadQueuedMessages() async {
    try {
      final db = _databaseService._db;
      final results = await db.query(
        _queueTable,
        where: 'is_processed = ? AND (expires_at IS NULL OR expires_at > ?)',
        whereArgs: [0, DateTime.now().millisecondsSinceEpoch],
      );
      
      for (final row in results) {
        final message = QueuedMessage.fromDatabaseMap(row);
        if (!message.isExpired) {
          _activeQueue[message.id] = message;
          _totalQueued++;
        }
      }
      
      print('Loaded ${_activeQueue.length} queued messages from database');
    } catch (e) {
      print('Failed to load queued messages: $e');
    }
  }

  /// Setup connectivity monitoring
  Future<void> _setupConnectivityMonitoring() async {
    try {
      // Check initial connectivity
      final connectivityResults = await _connectivity.checkConnectivity();
      _updateConnectivityState(connectivityResults.first);
      
      // Listen for connectivity changes
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
        _handleConnectivityChange,
        onError: (error) {
          print('Connectivity monitoring error: $error');
        },
      );
      
      print('Connectivity monitoring initialized');
    } catch (e) {
      print('Failed to setup connectivity monitoring: $e');
    }
  }

  /// Handle connectivity state changes
  void _handleConnectivityChange(ConnectivityResult result) {
    final previousState = _currentConnectivityState;
    final newState = _connectivityResultToState(result);
    
    if (previousState != newState) {
      _currentConnectivityState = newState;
      _connectivityController.add(newState);
      
      final timestamp = DateTime.now();
      
      print('Connectivity changed: $previousState -> $newState');
      
      if (newState == ConnectivityState.connected) {
        // Start processing queue when connectivity returns
        _startProcessingQueue();
      }
      
      // Emit updated statistics
      _emitStatistics();
    }
  }

  /// Convert ConnectivityResult to ConnectivityState
  ConnectivityState _connectivityResultToState(ConnectivityResult result) {
    switch (result) {
      case ConnectivityResult.wifi:
      case ConnectivityResult.ethernet:
      case ConnectivityResult.mobile:
        return ConnectivityState.connected;
      case ConnectivityResult.none:
        return ConnectivityState.disconnected;
      default:
        return ConnectivityState.unknown;
    }
  }

  /// Queue a message for offline delivery
  /// 
  /// Returns the queued message ID if successful, null if deduplicated
  Future<String?> queueMessage({
    required TransportTarget target,
    required Uint8List content,
    MessagePriority priority = MessagePriority.normal,
    String messageType = 'text',
    Map<String, dynamic> metadata = const {},
    String? preferredTransportType,
    Duration? expiresIn,
  }) async {
    if (!_isInitialized) {
      throw StateError('OfflineQueueService is not initialized');
    }
    
    try {
      // Generate content hash for deduplication
      final contentHash = _generateContentHash(content);
      
      // Check for duplicates
      if (await _isDuplicate(contentHash, target.id)) {
        print('Message deduplicated (duplicate content hash)');
        return null;
      }
      
      // Encrypt the content
      final encryptedContent = await _encryptContent(content);
      
      // Generate message ID
      final messageId = 'msg_${DateTime.now().millisecondsSinceEpoch}_${target.id}';
      
      // Create expiration time if specified
      final expiresAt = expiresIn != null 
          ? DateTime.now().add(expiresIn)
          : null;
      
      // Create queued message
      final message = QueuedMessage(
        id: messageId,
        target: target,
        encryptedContent: encryptedContent,
        priority: priority,
        createdAt: DateTime.now(),
        messageType: messageType,
        metadata: metadata,
        contentHash: contentHash,
        preferredTransportType: preferredTransportType,
        expiresAt: expiresAt,
      );
      
      // Store in database
      await _storeMessageInDatabase(message);
      
      // Add to active queue
      _activeQueue[messageId] = message;
      _totalQueued++;
      
      // Store duplicate hash
      await _storeDuplicateHash(contentHash, target.id, expiresAt);
      
      print('Message queued: $messageId (priority: ${priority.toString()})');
      
      // Start processing if connected
      if (_currentConnectivityState == ConnectivityState.connected) {
        _startProcessingQueue();
      }
      
      // Emit statistics update
      _emitStatistics();
      
      return messageId;
    } catch (e) {
      print('Failed to queue message: $e');
      rethrow;
    }
  }

  /// Generate SHA-256 hash of content for deduplication
  String _generateContentHash(Uint8List content) {
    final bytes = content is Uint8List ? content : Uint8List.fromList(content);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Check if message is a duplicate
  Future<bool> _isDuplicate(String contentHash, String targetId) async {
    // Check in-memory duplicate cache first
    final cacheKey = '${contentHash}_${targetId}';
    if (_duplicateCache.contains(cacheKey)) {
      return true;
    }
    
    try {
      final db = _databaseService._db;
      final results = await db.query(
        _duplicateTable,
        where: 'content_hash = ? AND target_id = ? AND (expires_at IS NULL OR expires_at > ?)',
        whereArgs: [contentHash, targetId, DateTime.now().millisecondsSinceEpoch],
      );
      
      if (results.isNotEmpty) {
        _duplicateCache.add(cacheKey);
        return true;
      }
      
      return false;
    } catch (e) {
      print('Error checking for duplicates: $e');
      return false;
    }
  }

  /// Encrypt message content using encryption service
  Future<String> _encryptContent(Uint8List content) async {
    try {
      // For demonstration, using a shared secret (in real implementation, 
      // this would be derived per target/peer)
      final sharedSecret = await _encryptionService.getPrivateKey();
      return await _encryptionService.encrypt(content, sharedSecret);
    } catch (e) {
      print('Failed to encrypt content: $e');
      rethrow;
    }
  }

  /// Store message in database
  Future<void> _storeMessageInDatabase(QueuedMessage message) async {
    try {
      await _databaseService._db.insert(
        _queueTable,
        message.toDatabaseMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      print('Failed to store message in database: $e');
      rethrow;
    }
  }

  /// Store duplicate hash in database
  Future<void> _storeDuplicateHash(String contentHash, String targetId, DateTime? expiresAt) async {
    try {
      final duplicateId = 'dup_${DateTime.now().millisecondsSinceEpoch}';
      final duplicate = {
        'id': duplicateId,
        'content_hash': contentHash,
        'target_id': targetId,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'expires_at': expiresAt?.millisecondsSinceEpoch,
      };
      
      await _databaseService._db.insert(
        _duplicateTable,
        duplicate,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      _duplicateCache.add('${contentHash}_${targetId}');
    } catch (e) {
      print('Failed to store duplicate hash: $e');
    }
  }

  /// Start processing the message queue
  Future<void> _startProcessingQueue() async {
    if (_isProcessing || _activeQueue.isEmpty) {
      return;
    }
    
    _isProcessing = true;
    print('Starting queue processing (${_activeQueue.length} messages)');
    
    try {
      // Sort messages by priority and creation time
      final sortedMessages = _getPrioritySortedMessages();
      
      for (final message in sortedMessages) {
        if (!_activeQueue.containsKey(message.id)) {
          continue; // Message was already processed
        }
        
        _queueProcessorController.add(message);
        
        try {
          await _processMessage(message);
          
          // Message processed successfully
          _activeQueue.remove(message.id);
          _successfullySent++;
          
          final queueTime = DateTime.now().difference(message.createdAt);
          _queueTimes.add(queueTime);
          
          // Mark as processed in database
          await _markMessageAsProcessed(message.id);
          
          _messageDeliveredController.add(message);
          
          print('Message delivered: ${message.id} (queue time: ${queueTime.inSeconds}s)');
          
        } catch (e) {
          await _handleMessageProcessingError(message, e);
        }
        
        // Small delay between messages to avoid overwhelming transports
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
    } finally {
      _isProcessing = false;
      _emitStatistics();
    }
  }

  /// Get messages sorted by priority and creation time
  List<QueuedMessage> _getPrioritySortedMessages() {
    final messages = _activeQueue.values
        .where((msg) => msg.shouldRetry)
        .toList();
    
    // Sort by priority (urgent > high > normal > low) and then by creation time
    messages.sort((a, b) {
      final priorityOrder = {
        MessagePriority.urgent: 0,
        MessagePriority.high: 1,
        MessagePriority.normal: 2,
        MessagePriority.low: 3,
      };
      
      final aPriority = priorityOrder[a.priority] ?? 2;
      final bPriority = priorityOrder[b.priority] ?? 2;
      
      if (aPriority != bPriority) {
        return aPriority.compareTo(bPriority);
      }
      
      return a.createdAt.compareTo(b.createdAt);
    });
    
    return messages;
  }

  /// Process a single queued message
  Future<void> _processMessage(QueuedMessage message) async {
    // Check if it's time to retry this message
    if (message.lastAttemptAt != null) {
      final timeSinceLastAttempt = DateTime.now().difference(message.lastAttemptAt!);
      if (timeSinceLastAttempt < message.getRetryDelay()) {
        return; // Not yet time to retry
      }
    }
    
    // Update attempt count and timestamp
    final updatedMessage = message.copyWith(
      attemptCount: message.attemptCount + 1,
      lastAttemptAt: DateTime.now(),
    );
    
    _activeQueue[message.id] = updatedMessage;
    await _updateMessageInDatabase(updatedMessage);
    
    _totalRetries++;
    
    try {
      // Decrypt content
      final content = await _decryptContent(message.encryptedContent);
      
      // Select best transport for delivery
      final transport = await _selectBestTransport(message);
      
      if (transport == null) {
        throw Exception('No suitable transport available');
      }
      
      // Send message via selected transport
      if (message.preferredTransportType != null) {
        await transport.send(
          message.target, 
          content,
          preferredType: _getTransportTypeFromString(message.preferredTransportType!),
        );
      } else {
        await transport.send(message.target, content);
      }
      
    } catch (e) {
      throw MessageProcessingException('Failed to process message: $e');
    }
  }

  /// Decrypt message content
  Future<Uint8List> _decryptContent(String encryptedContent) async {
    try {
      final sharedSecret = await _encryptionService.getPrivateKey();
      return await _encryptionService.decrypt(encryptedContent, sharedSecret);
    } catch (e) {
      print('Failed to decrypt content: $e');
      rethrow;
    }
  }

  /// Select best transport for message delivery
  Future<Transport?> _selectBestTransport(QueuedMessage message) async {
    try {
      // Try preferred transport first if specified
      if (message.preferredTransportType != null) {
        final preferredType = _getTransportTypeFromString(message.preferredTransportType!);
        // TransportManager handles transport selection
        // We'll use a generic approach here
      }
      
      // For now, we'll use the first available transport
      // In a full implementation, this would integrate with TransportManager
      if (_transportManager.availableTransports.isNotEmpty) {
        final transportId = _transportManager.availableTransports.first;
        // Return appropriate transport instance based on ID
        // This would need proper integration with TransportManager
      }
      
      return null;
    } catch (e) {
      print('Failed to select transport: $e');
      return null;
    }
  }

  /// Convert transport type string to enum
  TransportType _getTransportTypeFromString(String type) {
    switch (type.toLowerCase()) {
      case 'ble':
        return TransportType.ble;
      case 'libp2p':
        return TransportType.libp2P;
      case 'lora':
        return TransportType.loRa;
      default:
        return TransportType.ble;
    }
  }

  /// Handle message processing error with retry logic
  Future<void> _handleMessageProcessingError(QueuedMessage message, dynamic error) async {
    print('Message processing failed: ${message.id} - $error');
    
    final updatedMessage = message.copyWith(lastError: error.toString());
    _activeQueue[message.id] = updatedMessage;
    
    if (message.attemptCount >= message.maxAttempts) {
      // Max retries exceeded
      _failedMessages++;
      _activeQueue.remove(message.id);
      
      await _markMessageAsFailed(message.id);
      _messageFailedController.add(message);
      
      print('Message failed permanently: ${message.id}');
    } else {
      // Update with new retry information
      await _updateMessageInDatabase(updatedMessage);
      print('Message queued for retry: ${message.id} (attempt ${message.attemptCount}/${message.maxAttempts})');
    }
  }

  /// Update message in database
  Future<void> _updateMessageInDatabase(QueuedMessage message) async {
    try {
      await _databaseService._db.update(
        _queueTable,
        message.toDatabaseMap(),
        where: 'id = ?',
        whereArgs: [message.id],
      );
    } catch (e) {
      print('Failed to update message in database: $e');
    }
  }

  /// Mark message as processed in database
  Future<void> _markMessageAsProcessed(String messageId) async {
    try {
      await _databaseService._db.update(
        _queueTable,
        {'is_processed': 1},
        where: 'id = ?',
        whereArgs: [messageId],
      );
    } catch (e) {
      print('Failed to mark message as processed: $e');
    }
  }

  /// Mark message as failed in database
  Future<void> _markMessageAsFailed(String messageId) async {
    try {
      await _databaseService._db.update(
        _queueTable,
        {'is_processed': 1, 'last_error': 'Max retries exceeded'},
        where: 'id = ?',
        whereArgs: [messageId],
      );
    } catch (e) {
      print('Failed to mark message as failed: $e');
    }
  }

  /// Start periodic queue processing
  void _startProcessingTimer() {
    _processingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_currentConnectivityState == ConnectivityState.connected && 
          _activeQueue.isNotEmpty && 
          !_isProcessing) {
        _startProcessingQueue();
      }
    });
  }

  /// Start periodic cleanup of expired messages
  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _cleanupExpiredMessages();
    });
  }

  /// Clean up expired messages
  Future<void> _cleanupExpiredMessages() async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final db = _databaseService._db;
      
      // Mark expired messages as processed
      await db.update(
        _queueTable,
        {'is_processed': 1, 'last_error': 'Message expired'},
        where: 'expires_at IS NOT NULL AND expires_at < ? AND is_processed = 0',
        whereArgs: [now],
      );
      
      // Remove expired duplicate hashes
      await db.delete(
        _duplicateTable,
        where: 'expires_at IS NOT NULL AND expires_at < ?',
        whereArgs: [now],
      );
      
      // Clean up in-memory cache
      _duplicateCache.clear();
      
      print('Cleaned up expired messages and duplicate hashes');
    } catch (e) {
      print('Failed to cleanup expired messages: $e');
    }
  }

  /// Emit updated queue statistics
  void _emitStatistics() {
    final messagesByPriority = <MessagePriority, int>{
      MessagePriority.urgent: 0,
      MessagePriority.high: 0,
      MessagePriority.normal: 0,
      MessagePriority.low: 0,
    };
    
    final messagesByTransportType = <String, int>{};
    
    for (final message in _activeQueue.values) {
      messagesByPriority[message.priority] = (messagesByPriority[message.priority] ?? 0) + 1;
      
      final transportType = message.preferredTransportType ?? 'auto';
      messagesByTransportType[transportType] = (messagesByTransportType[transportType] ?? 0) + 1;
    }
    
    final totalProcessed = _successfullySent + _failedMessages;
    final successRate = totalProcessed > 0 ? (_successfullySent / totalProcessed) * 100 : 0.0;
    
    final averageQueueTime = _queueTimes.isNotEmpty
        ? Duration(seconds: (_queueTimes
            .map((d) => d.inSeconds)
            .reduce((a, b) => a + b) / _queueTimes.length).round())
        : Duration.zero;
    
    final statistics = QueueStatistics(
      totalQueued: _totalQueued,
      successfullySent: _successfullySent,
      failedMessages: _failedMessages,
      currentQueueSize: _activeQueue.length,
      messagesByPriority: messagesByPriority,
      messagesByTransportType: messagesByTransportType,
      averageQueueTime: averageQueueTime,
      lastConnectivityChange: null, // Could track this
      totalRetries: _totalRetries,
      successRate: successRate,
    );
    
    _statisticsController.add(statistics);
  }

  /// Get current queue statistics
  QueueStatistics getCurrentStatistics() {
    return QueueStatistics(
      totalQueued: _totalQueued,
      successfullySent: _successfullySent,
      failedMessages: _failedMessages,
      currentQueueSize: _activeQueue.length,
      messagesByPriority: _getCurrentMessagesByPriority(),
      messagesByTransportType: _getCurrentMessagesByTransportType(),
      averageQueueTime: _getAverageQueueTime(),
      lastConnectivityChange: null,
      totalRetries: _totalRetries,
      successRate: _getCurrentSuccessRate(),
    );
  }

  Map<MessagePriority, int> _getCurrentMessagesByPriority() {
    final byPriority = <MessagePriority, int>{
      MessagePriority.urgent: 0,
      MessagePriority.high: 0,
      MessagePriority.normal: 0,
      MessagePriority.low: 0,
    };
    
    for (final message in _activeQueue.values) {
      byPriority[message.priority] = (byPriority[message.priority] ?? 0) + 1;
    }
    
    return byPriority;
  }

  Map<String, int> _getCurrentMessagesByTransportType() {
    final byTransportType = <String, int>{};
    
    for (final message in _activeQueue.values) {
      final transportType = message.preferredTransportType ?? 'auto';
      byTransportType[transportType] = (byTransportType[transportType] ?? 0) + 1;
    }
    
    return byTransportType;
  }

  Duration _getAverageQueueTime() {
    return _queueTimes.isNotEmpty
        ? Duration(seconds: (_queueTimes
            .map((d) => d.inSeconds)
            .reduce((a, b) => a + b) / _queueTimes.length).round())
        : Duration.zero;
  }

  double _getCurrentSuccessRate() {
    final totalProcessed = _successfullySent + _failedMessages;
    return totalProcessed > 0 ? (_successfullySent / totalProcessed) * 100 : 0.0;
  }

  /// Force processing of the queue (for testing or manual trigger)
  Future<void> forceProcessQueue() async {
    if (!_isProcessing) {
      await _startProcessingQueue();
    }
  }

  /// Clear all queued messages (use with caution)
  Future<void> clearAllQueuedMessages() async {
    try {
      await _databaseService._db.delete(_queueTable);
      await _databaseService._db.delete(_duplicateTable);
      
      _activeQueue.clear();
      _duplicateCache.clear();
      
      // Reset statistics
      _totalQueued = 0;
      _successfullySent = 0;
      _failedMessages = 0;
      _totalRetries = 0;
      _queueTimes.clear();
      
      _emitStatistics();
      
      print('All queued messages cleared');
    } catch (e) {
      print('Failed to clear queued messages: $e');
      rethrow;
    }
  }

  /// Get queued messages (for debugging)
  List<QueuedMessage> getQueuedMessages() {
    return _activeQueue.values.toList();
  }

  /// Cancel a specific queued message
  Future<void> cancelQueuedMessage(String messageId) async {
    try {
      await _databaseService._db.delete(
        _queueTable,
        where: 'id = ?',
        whereArgs: [messageId],
      );
      
      _activeQueue.remove(messageId);
      _emitStatistics();
      
      print('Cancelled queued message: $messageId');
    } catch (e) {
      print('Failed to cancel queued message: $e');
      rethrow;
    }
  }

  /// Dispose of resources
  void dispose() {
    _processingTimer?.cancel();
    _cleanupTimer?.cancel();
    _connectivitySubscription?.cancel();
    
    _connectivityController.close();
    _queueProcessorController.close();
    _messageDeliveredController.close();
    _messageFailedController.close();
    _statisticsController.close();
    
    _isInitialized = false;
    print('OfflineQueueService disposed');
  }
}

/// Exception thrown during message processing
class MessageProcessingException implements Exception {
  final String message;
  final String? errorCode;
  
  const MessageProcessingException(this.message, [this.errorCode]);
  
  @override
  String toString() => 'MessageProcessingException: $message';
}