# Offline Queue Service

A comprehensive offline message queuing service for network-resilient messaging applications. This service provides automatic message queuing when network connectivity is unavailable, with intelligent retry mechanisms and priority-based delivery.

## Features

### ✅ Core Requirements Implemented

1. **Queue messages when network is unavailable** - Messages are automatically queued when send operations fail due to network issues
2. **Automatic retry when connectivity returns** - Exponential backoff retry mechanism with configurable attempts
3. **Priority-based message ordering** - Four priority levels (urgent, high, normal, low) with intelligent ordering
4. **Storage of queued messages in encrypted database** - Uses SQLCipher with AES-256-GCM encryption
5. **Message deduplication to prevent duplicates** - Content-based hashing with database and memory caching
6. **Integration with all transport layers for optimal delivery** - Works with BLE, LibP2P, and LoRa transports

### 🚀 Additional Advanced Features

- **Network connectivity monitoring** - Real-time connectivity state tracking
- **Comprehensive statistics and monitoring** - Detailed metrics on queue performance
- **Message expiration handling** - Configurable expiration times for queued messages
- **Transport preference support** - Preferred transport type for specific messages
- **Robust error handling** - Detailed error tracking and recovery mechanisms
- **Memory and database cleanup** - Automatic cleanup of expired messages and duplicates
- **Event streaming** - Real-time events for UI updates and monitoring
- **Force processing capabilities** - Manual queue processing for testing and urgent delivery

## Architecture

### Core Components

```
┌─────────────────────────────────────────────────────────────┐
│                    OfflineQueueService                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────┐        │
│  │ Connectivity│  │ Message      │  │ Statistics  │        │
│  │ Monitor     │  │ Processor    │  │ Tracker     │        │
│  └─────────────┘  └──────────────┘  └─────────────┘        │
│                                                             │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────┐        │
│  │ Priority    │  │ Deduplication│  │ Retry Logic │        │
│  │ Queue       │  │ Engine       │  │ & Backoff   │        │
│  └─────────────┘  └──────────────┘  └─────────────┘        │
└─────────────────────────────────────────────────────────────┘
         │                    │                     │
         │                    │                     │
┌────────▼────────┐  ┌────────▼────────┐  ┌────────▼────────┐
│ DatabaseService │  │EncryptionService│  │TransportManager │
│ (SQLCipher)     │  │ (X25519+AES)    │  │ (Multi-transport│
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

### Database Schema

The service uses two main tables:

#### `offline_message_queue`
Stores queued messages with all metadata needed for retry and delivery:

```sql
CREATE TABLE offline_message_queue (
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
  preferred_transport_type TEXT
);
```

#### `message_duplicates`
Tracks content hashes to prevent duplicate message processing:

```sql
CREATE TABLE message_duplicates (
  id TEXT PRIMARY KEY,
  content_hash TEXT NOT NULL,
  target_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER
);
```

## Usage Examples

### Basic Integration

```dart
// Initialize the service
await OfflineQueueService.initialize();
final queueService = OfflineQueueService.instance;

// Send a message (automatically queued if offline)
final messageId = await queueService.queueMessage(
  target: TransportTarget(
    id: 'recipient_device_id',
    address: '00:11:22:33:44:55',
    name: 'John Doe',
  ),
  content: utf8.encode('Hello World!'),
  priority: MessagePriority.normal,
  messageType: 'text',
);

// Listen for connectivity changes
queueService.connectivityStream.listen((state) {
  if (state == ConnectivityState.connected) {
    print('Network restored - processing queue');
  }
});

// Listen for delivery notifications
queueService.messageDeliveredStream.listen((message) {
  print('Message delivered: ${message.id}');
});
```

### Priority-based Messaging

```dart
// Urgent message (highest priority)
await queueService.queueMessage(
  target: target,
  content: utf8.encode('Emergency message'),
  priority: MessagePriority.urgent,
);

// High priority message
await queueService.queueMessage(
  target: target,
  content: utf8.encode('Important update'),
  priority: MessagePriority.high,
);

// Normal priority (default)
await queueService.queueMessage(
  target: target,
  content: utf8.encode('Regular message'),
  priority: MessagePriority.normal,
);

// Low priority message
await queueService.queueMessage(
  target: target,
  content: utf8.encode('Background sync'),
  priority: MessagePriority.low,
);
```

### Attachment Handling

```dart
// Send file attachment
final fileData = await File('document.pdf').readAsBytes();
await queueService.queueMessage(
  target: target,
  content: Uint8List.fromList(fileData),
  priority: MessagePriority.high,
  messageType: 'attachment',
  metadata: {
    'file_name': 'document.pdf',
    'mime_type': 'application/pdf',
    'file_size': fileData.length,
  },
  expiresIn: Duration(days: 7), // Expire in 1 week
);
```

### Transport Preferences

```dart
// Prefer BLE transport for short-range messaging
await queueService.queueMessage(
  target: nearbyDevice,
  content: utf8.encode('Local message'),
  preferredTransportType: 'BLE',
  priority: MessagePriority.high,
);

// Prefer LoRa for long-range communication
await queueService.queueMessage(
  target: remoteDevice,
  content: utf8.encode('Remote message'),
  preferredTransportType: 'LoRa',
  priority: MessagePriority.normal,
);
```

### Error Handling and Retry

```dart
// Listen for failed messages
queueService.messageFailedStream.listen((message) {
  if (message.attemptCount >= message.maxAttempts) {
    print('Message failed permanently: ${message.id}');
    print('Last error: ${message.lastError}');
    
    // Show user notification about delivery failure
    showFailureNotification(message);
  }
});

// Force process queue (useful for testing)
await queueService.forceProcessQueue();
```

### Statistics and Monitoring

```dart
// Get current statistics
final stats = queueService.getCurrentStatistics();
print('Queue size: ${stats.currentQueueSize}');
print('Success rate: ${stats.successRate}%');
print('Average queue time: ${stats.averageQueueTime}');

// Listen for statistics updates
queueService.statisticsStream.listen((stats) {
  updateStatsUI(stats);
});
```

## Configuration Options

### Message Priorities

- **MessagePriority.urgent** - Highest priority, processed first
- **MessagePriority.high** - High priority, processed after urgent
- **MessagePriority.normal** - Default priority level
- **MessagePriority.low** - Lowest priority, processed last

### Retry Configuration

```dart
// Default retry behavior
message.maxAttempts = 5;                    // Maximum retry attempts
message.backoffMultiplier = 2;              // Exponential backoff base
message.getRetryDelay();                    // Calculate next retry delay

// Example: 2s, 4s, 8s, 16s, 32s (capped at 30 minutes)
```

### Message Expiration

```dart
// Messages can expire to prevent indefinite queuing
await queueService.queueMessage(
  target: target,
  content: content,
  expiresIn: Duration(hours: 24),  // Expire in 24 hours
);
```

## Integration with Transport Layers

### BLE Transport
- **Best for**: Short-range, high-frequency communication
- **Queue integration**: Automatic queueing when device not connected
- **Retry logic**: Handles connection failures gracefully

### LibP2P Transport
- **Best for**: Peer-to-peer communication with multiple protocols
- **Queue integration**: Supports multi-protocol message delivery
- **Retry logic**: Leverages LibP2P's built-in reliability

### LoRa Transport
- **Best for**: Long-range, low-power communication
- **Queue integration**: Optimized for mesh networking patterns
- **Retry logic**: Appropriate for radio communication delays

## Database Security

All queued messages are encrypted using the application's encryption service:

1. **Content Encryption**: Messages are encrypted using AES-256-GCM
2. **Key Management**: Uses the same X25519 keypair as the main application
3. **Database Encryption**: SQLCipher provides full database encryption
4. **Secure Storage**: Passwords are managed via FlutterSecureStorage

## Performance Characteristics

### Memory Usage
- In-memory cache for active queue (configurable size)
- Efficient data structures for priority ordering
- Automatic cleanup of expired entries

### Database Performance
- Indexed queries for priority and timestamp sorting
- Batch operations for bulk cleanup
- Optimized deduplication lookups

### Network Efficiency
- Exponential backoff prevents network congestion
- Batch processing reduces overhead
- Transport-specific optimization

## Error Handling

### Network Errors
- Automatic retry with exponential backoff
- Graceful degradation when transports unavailable
- Detailed error logging and user feedback

### Database Errors
- Transaction rollback on failures
- Integrity checking and repair
- Backup and recovery mechanisms

### Encryption Errors
- Key validation before operations
- Secure key rotation support
- Graceful handling of corrupted data

## Testing and Debugging

### Debug Features
- Comprehensive logging throughout the service
- Statistics tracking for performance analysis
- Event streaming for real-time monitoring

### Manual Testing
```dart
// Force process queue for testing
await queueService.forceProcessQueue();

// Clear all queued messages (use carefully!)
await queueService.clearAllQueuedMessages();

// Get all queued messages for inspection
final queuedMessages = queueService.getQueuedMessages();
```

### Unit Testing
The service is designed for easy unit testing with mock dependencies:
- Mock DatabaseService for testing storage operations
- Mock EncryptionService for testing encryption/decryption
- Mock TransportManager for testing delivery logic

## Monitoring and Alerting

### Key Metrics
- Queue size and growth rate
- Success/failure rates
- Average queue time
- Connectivity state transitions
- Retry attempt patterns

### Health Checks
- Database connectivity and integrity
- Encryption service availability
- Transport layer status
- Memory usage and cleanup effectiveness

## Best Practices

### Message Design
- Keep message sizes reasonable for transport constraints
- Use appropriate priority levels for different message types
- Set reasonable expiration times
- Include useful metadata for debugging

### Error Handling
- Always handle potential failures in queue operations
- Provide user feedback for failed deliveries
- Monitor statistics for performance issues
- Implement appropriate timeout handling

### Security
- Never log sensitive message content
- Ensure proper key management
- Regular database backups
- Secure deletion of expired messages

## Dependencies

### Required Dependencies
```yaml
dependencies:
  connectivity_plus: ^5.0.2      # Network connectivity monitoring
  cryptography: ^2.5.0            # Encryption operations
  sqflite_sqlcipher: ^2.2.2      # Encrypted database storage
  crypto: ^3.0.3                  # Hash functions for deduplication
  flutter_secure_storage: ^9.2.1  # Secure credential storage
```

### Transport Dependencies
```yaml
dependencies:
  flutter_blue_plus: ^1.32.0      # BLE transport implementation
  # LibP2P and LoRa transport dependencies
```

## Troubleshooting

### Common Issues

#### Messages Not Being Processed
1. Check connectivity status
2. Verify transport availability
3. Examine error logs
4. Check queue statistics

#### High Memory Usage
1. Monitor queue growth rate
2. Verify cleanup timers are running
3. Check for message leaks
4. Analyze priority distribution

#### Database Performance
1. Monitor database size
2. Check index usage
3. Verify cleanup operations
4. Consider batch operations

#### Encryption Errors
1. Verify key availability
2. Check key format compatibility
3. Test encryption/decryption operations
4. Monitor memory usage during encryption

### Debug Commands

```dart
// Check current connectivity
final connectivity = queueService.connectivityState;

// Get queue size
final queueSize = queueService.queueSize;

// Check if processing
final isProcessing = queueService.isProcessing;

// Force cleanup
await queueService.forceProcessQueue();

// Check statistics
final stats = queueService.getCurrentStatistics();
```

## Future Enhancements

### Planned Features
- **Message Groups**: Support for broadcast messages to multiple recipients
- **Delivery Receipts**: Acknowledgment tracking for critical messages
- **Message History**: Persistent history of all queued/delivered messages
- **Advanced Routing**: Intelligent routing based on recipient capabilities
- **Compression**: Automatic compression for large messages
- **QoS Support**: Quality of Service levels beyond basic priorities

### Scalability Improvements
- **Distributed Queuing**: Multi-device message synchronization
- **Cloud Backup**: Encrypted backup of queued messages
- **Analytics**: Advanced analytics and reporting
- **Machine Learning**: Intelligent retry timing and priority adjustment

---

## Summary

The OfflineQueueService provides a comprehensive solution for network-resilient messaging with:

✅ **All required features implemented**
✅ **Robust integration with existing transport layer architecture**
✅ **Enterprise-grade security with encryption at rest and in transit**
✅ **Comprehensive error handling and recovery mechanisms**
✅ **Real-time monitoring and statistics tracking**
✅ **Flexible configuration and customization options**

The service seamlessly integrates with the existing Flutter mesh networking application, providing automatic offline queuing, intelligent retry logic, and optimal delivery across all transport layers (BLE, LibP2P, LoRa) while maintaining security through end-to-end encryption.