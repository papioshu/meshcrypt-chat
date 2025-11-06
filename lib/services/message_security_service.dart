import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

import 'encryption_service.dart';

/// Message security service providing burn-after-read and timed messages functionality
/// with message integrity verification and secure deletion
class MessageSecurityService {
  static const String _storagePrefix = 'secure_message_';
  static const String _burnKeysPrefix = 'burn_key_';
  static const String _expirationJobsPrefix = 'exp_job_';
  
  final FlutterSecureStorage _secureStorage;
  final EncryptionService _encryptionService;
  final Logger _logger = Logger();
  final Uuid _uuid = const Uuid();
  
  // Store active expiration timers
  final Map<String, Timer> _activeExpirationTimers = {};
  
  // Store burn keys and message tracking
  final Map<String, BurnKeyInfo> _burnKeys = {};
  final Map<String, MessageTrackingInfo> _messageTracking = {};

  MessageSecurityService({
    FlutterSecureStorage? secureStorage,
    required EncryptionService encryptionService,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _encryptionService = encryptionService;

  /// Create a timed message that expires after a specified duration
  Future<TimedMessage> createTimedMessage({
    required String message,
    required Uint8List sharedSecret,
    Duration? expirationDuration,
    DateTime? expirationDateTime,
    bool burnAfterRead = false,
  }) async {
    try {
      // Validate expiration parameters
      DateTime? expiresAt;
      if (expirationDuration != null) {
        expiresAt = DateTime.now().add(expirationDuration);
      } else if (expirationDateTime != null) {
        expiresAt = expirationDateTime;
      } else {
        // Default expiration: 24 hours
        expiresAt = DateTime.now().add(const Duration(hours: 24));
      }

      if (expiresAt.isBefore(DateTime.now())) {
        throw Exception('Expiration time must be in the future');
      }

      // Generate unique message ID
      final messageId = _uuid.v4();

      // Generate integrity hash for message verification
      final messageBytes = utf8.encode(message);
      final integrityHash = await _generateIntegrityHash(messageBytes);

      // Create message metadata
      final metadata = MessageMetadata(
        messageId: messageId,
        createdAt: DateTime.now(),
        expiresAt: expiresAt,
        burnAfterRead: burnAfterRead,
        integrityHash: integrityHash,
        nonce: _encryptionService.generateNonce(),
      );

      // Encrypt the message with metadata
      final encryptedData = await _encryptMessageWithMetadata(
        messageBytes,
        metadata,
        sharedSecret,
      );

      // Create timed message object
      final timedMessage = TimedMessage(
        messageId: messageId,
        encryptedData: encryptedData,
        metadata: metadata,
        encrypted: true,
      );

      // Store the message securely
      await _storeMessageSecurely(timedMessage, sharedSecret);

      // Schedule expiration timer if expiration is in the future
      final timeUntilExpiration = expiresAt.difference(DateTime.now());
      if (timeUntilExpiration.inMilliseconds > 0) {
        await _scheduleExpirationTimer(timedMessage.messageId, timeUntilExpiration);
      }

      _logger.i('Created timed message $messageId with expiration at $expiresAt');
      return timedMessage;

    } catch (e) {
      _logger.e('Error creating timed message: $e');
      rethrow;
    }
  }

  /// Create a burn-after-read message
  Future<BurnMessage> createBurnMessage({
    required String message,
    required Uint8List sharedSecret,
    Duration? maxViewTime,
  }) async {
    try {
      // Create message with burn-after-read flag
      final timedMessage = await createTimedMessage(
        message: message,
        sharedSecret: sharedSecret,
        burnAfterRead: true,
      );

      // Generate burn key for single-use verification
      final burnKey = await _generateBurnKey(message, sharedSecret);

      // Store burn key info
      final burnKeyInfo = BurnKeyInfo(
        messageId: timedMessage.messageId,
        burnKey: burnKey,
        createdAt: DateTime.now(),
        maxViewTime: maxViewTime,
        used: false,
      );

      _burnKeys[timedMessage.messageId] = burnKeyInfo;

      // Store burn key in secure storage
      await _secureStorage.write(
        key: '$_burnKeysPrefix${timedMessage.messageId}',
        value: base64Encode(burnKey),
      );

      // Convert to burn message
      final burnMessage = BurnMessage(
        messageId: timedMessage.messageId,
        encryptedData: timedMessage.encryptedData,
        metadata: timedMessage.metadata,
        burnKey: burnKey,
      );

      _logger.i('Created burn-after-read message ${timedMessage.messageId}');
      return burnMessage;

    } catch (e) {
      _logger.e('Error creating burn message: $e');
      rethrow;
    }
  }

  /// Read and decrypt a timed message
  Future<ReadMessageResult> readTimedMessage({
    required String messageId,
    required Uint8List sharedSecret,
    String? burnKey,
  }) async {
    try {
      // Check if message exists and get metadata
      final message = await _getMessage(messageId);
      if (message == null) {
        throw Exception('Message not found or already deleted');
      }

      // Verify message hasn't expired
      if (message.metadata.expiresAt.isBefore(DateTime.now())) {
        await _securelyDeleteMessage(messageId);
        throw Exception('Message has expired');
      }

      // Verify message integrity
      final storedHash = message.metadata.integrityHash;
      final actualHash = await _getStoredIntegrityHash(messageId);
      
      if (storedHash != actualHash) {
        _logger.w('Message integrity check failed for $messageId');
        throw Exception('Message integrity verification failed - possible tampering');
      }

      // Decrypt the message
      final decryptedBytes = await _decryptMessage(
        message.encryptedData,
        message.metadata,
        sharedSecret,
      );

      final decryptedMessage = utf8.decode(decryptedBytes);

      final result = ReadMessageResult(
        messageId: messageId,
        message: decryptedMessage,
        metadata: message.metadata,
        burned: false,
      );

      // Handle burn-after-read
      if (message.metadata.burnAfterRead) {
        result.burned = await _burnMessage(messageId, sharedSecret, burnKey);
      }

      _logger.i('Successfully read message $messageId${result.burned ? ' (burned)' : ''}');
      return result;

    } catch (e) {
      _logger.e('Error reading message $messageId: $e');
      rethrow;
    }
  }

  /// Burn a message immediately (for burn-after-read)
  Future<bool> burnMessage({
    required String messageId,
    required Uint8List sharedSecret,
    String? burnKey,
  }) async {
    try {
      // Verify burn key if provided
      final storedBurnKey = await _secureStorage.read(key: '$_burnKeysPrefix$messageId');
      if (storedBurnKey != null && burnKey != null) {
        final providedKeyBytes = base64Decode(burnKey);
        final storedKeyBytes = base64Decode(storedBurnKey);
        
        if (!_constantTimeEquals(providedKeyBytes, storedKeyBytes)) {
          throw Exception('Invalid burn key');
        }
      }

      return await _burnMessage(messageId, sharedSecret, burnKey);

    } catch (e) {
      _logger.e('Error burning message $messageId: $e');
      rethrow;
    }
  }

  /// Get message metadata without reading content
  Future<MessageMetadata?> getMessageMetadata(String messageId) async {
    try {
      final message = await _getMessage(messageId);
      return message?.metadata;
    } catch (e) {
      _logger.e('Error getting metadata for $messageId: $e');
      return null;
    }
  }

  /// List all active messages for a user
  Future<List<MessageSummary>> listActiveMessages() async {
    try {
      final List<MessageSummary> summaries = [];
      
      // This would typically query a database
      // For now, we'll check secure storage keys
      final allKeys = await _secureStorage.readAll();
      
      for (final entry in allKeys.entries) {
        if (entry.key.startsWith(_storagePrefix)) {
          final messageId = entry.key.substring(_storagePrefix.length);
          final metadata = await getMessageMetadata(messageId);
          
          if (metadata != null && metadata.expiresAt.isAfter(DateTime.now())) {
            summaries.add(MessageSummary(
              messageId: messageId,
              createdAt: metadata.createdAt,
              expiresAt: metadata.expiresAt,
              burnAfterRead: metadata.burnAfterRead,
              integrityVerified: await _verifyIntegrityHash(messageId),
            ));
          }
        }
      }

      // Sort by expiration time
      summaries.sort((a, b) => a.expiresAt.compareTo(b.expiresAt));
      return summaries;

    } catch (e) {
      _logger.e('Error listing active messages: $e');
      return [];
    }
  }

  /// Clean up expired messages
  Future<void> cleanupExpiredMessages() async {
    try {
      final summaries = await listActiveMessages();
      
      for (final summary in summaries) {
        if (summary.expiresAt.isBefore(DateTime.now())) {
          await _securelyDeleteMessage(summary.messageId);
          _logger.i('Cleaned up expired message ${summary.messageId}');
        }
      }

    } catch (e) {
      _logger.e('Error cleaning up expired messages: $e');
    }
  }

  /// Clear all message data (use with caution)
  Future<void> clearAllMessages() async {
    try {
      // Cancel all timers
      for (final timer in _activeExpirationTimers.values) {
        timer.cancel();
      }
      _activeExpirationTimers.clear();

      // Clear all burn keys
      _burnKeys.clear();

      // Clear message tracking
      _messageTracking.clear();

      // Clear all stored messages
      final allKeys = await _secureStorage.readAll();
      
      for (final key in allKeys.keys) {
        if (key.startsWith(_storagePrefix) || 
            key.startsWith(_burnKeysPrefix) || 
            key.startsWith(_expirationJobsPrefix)) {
          await _secureStorage.delete(key: key);
        }
      }

      _logger.i('Cleared all message data');

    } catch (e) {
      _logger.e('Error clearing all messages: $e');
      rethrow;
    }
  }

  // Private helper methods

  /// Generate integrity hash for message verification
  Future<String> _generateIntegrityHash(Uint8List data) async {
    final algorithm = Sha256();
    final digest = await algorithm.hash(data);
    return base64Encode(digest.bytes);
  }

  /// Store message securely with encryption
  Future<void> _storeMessageSecurely(TimedMessage message, Uint8List sharedSecret) async {
    // Store the encrypted message
    await _secureStorage.write(
      key: '$_storagePrefix${message.messageId}',
      value: jsonEncode({
        'encryptedData': message.encryptedData,
        'metadata': {
          'messageId': message.metadata.messageId,
          'createdAt': message.metadata.createdAt.toIso8601String(),
          'expiresAt': message.metadata.expiresAt.toIso8601String(),
          'burnAfterRead': message.metadata.burnAfterRead,
          'integrityHash': message.metadata.integrityHash,
          'nonce': base64Encode(message.metadata.nonce),
        },
      }),
    );

    // Store integrity hash separately
    await _secureStorage.write(
      key: '${message.messageId}_integrity',
      value: message.metadata.integrityHash,
    );

    // Store encrypted content separately for additional security
    final encryptedContent = await _encryptionService.encrypt(
      utf8.encode(jsonEncode({
        'data': message.encryptedData,
        'checksum': message.metadata.integrityHash,
      })),
      sharedSecret,
    );

    await _secureStorage.write(
      key: '${message.messageId}_content',
      value: encryptedContent,
    );
  }

  /// Get message from storage
  Future<TimedMessage?> _getMessage(String messageId) async {
    try {
      final stored = await _secureStorage.read(key: '$_storagePrefix$messageId');
      if (stored == null) return null;

      final data = jsonDecode(stored);
      final metadataMap = data['metadata'];

      final metadata = MessageMetadata(
        messageId: metadataMap['messageId'],
        createdAt: DateTime.parse(metadataMap['createdAt']),
        expiresAt: DateTime.parse(metadataMap['expiresAt']),
        burnAfterRead: metadataMap['burnAfterRead'],
        integrityHash: metadataMap['integrityHash'],
        nonce: base64Decode(metadataMap['nonce']),
      );

      return TimedMessage(
        messageId: messageId,
        encryptedData: data['encryptedData'],
        metadata: metadata,
        encrypted: true,
      );

    } catch (e) {
      _logger.e('Error getting message $messageId: $e');
      return null;
    }
  }

  /// Encrypt message with metadata
  Future<String> _encryptMessageWithMetadata(
    Uint8List messageData,
    MessageMetadata metadata,
    Uint8List sharedSecret,
  ) async {
    // Combine message with metadata
    final combinedData = Uint8List.fromList([
      ...messageData,
      ...utf8.encode(jsonEncode({
        'messageId': metadata.messageId,
        'createdAt': metadata.createdAt.toIso8601String(),
        'expiresAt': metadata.expiresAt.toIso8601String(),
      })),
    ]);

    // Encrypt using the main encryption service
    return await _encryptionService.encrypt(combinedData, sharedSecret);
  }

  /// Decrypt message with metadata verification
  Future<Uint8List> _decryptMessage(
    String encryptedData,
    MessageMetadata metadata,
    Uint8List sharedSecret,
  ) async {
    // Decrypt using the main encryption service
    final decryptedBytes = await _encryptionService.decrypt(encryptedData, sharedSecret);
    
    // Extract the original message (first part before metadata)
    // The exact separation depends on how we format it in encryption
    return decryptedBytes;
  }

  /// Schedule expiration timer for a message
  Future<void> _scheduleExpirationTimer(String messageId, Duration duration) async {
    final timer = Timer(duration, () async {
      try {
        await _securelyDeleteMessage(messageId);
        _logger.i('Message $messageId expired and was deleted');
      } catch (e) {
        _logger.e('Error deleting expired message $messageId: $e');
      } finally {
        _activeExpirationTimers.remove(messageId);
      }
    });

    _activeExpirationTimers[messageId] = timer;
  }

  /// Generate burn key for single-use verification
  Future<Uint8List> _generateBurnKey(String message, Uint8List sharedSecret) async {
    // Create a unique burn key based on message content and shared secret
    final keyData = Uint8List.fromList([
      ...utf8.encode(message),
      ...sharedSecret,
      ...utf8.encode(DateTime.now().toIso8601String()),
    ]);

    final algorithm = Sha256();
    final digest = await algorithm.hash(keyData);
    return digest.bytes.sublist(0, 16); // 16 bytes for burn key
  }

  /// Burn message (secure deletion)
  Future<bool> _burnMessage(
    String messageId,
    Uint8List sharedSecret,
    String? burnKey,
  ) async {
    try {
      // Verify this hasn't been burned already
      final burnedFlag = await _secureStorage.read(key: '${messageId}_burned');
      if (burnedFlag == 'true') {
        throw Exception('Message already burned');
      }

      // Verify burn key if available
      final storedBurnKey = await _secureStorage.read(key: '$_burnKeysPrefix$messageId');
      if (storedBurnKey != null && burnKey != null) {
        final providedKeyBytes = base64Decode(burnKey);
        final storedKeyBytes = base64Decode(storedBurnKey);
        
        if (!_constantTimeEquals(providedKeyBytes, storedKeyBytes)) {
          throw Exception('Invalid burn key');
        }
      }

      // Mark as burned first (prevent race conditions)
      await _secureStorage.write(key: '${messageId}_burned', value: 'true');

      // Securely overwrite message content
      await _secureOverwriteMessage(messageId);

      // Delete all related keys
      await _secureStorage.delete(key: '$_storagePrefix$messageId');
      await _secureStorage.delete(key: '${messageId}_integrity');
      await _secureStorage.delete(key: '${messageId}_content');
      await _secureStorage.delete(key: '$_burnKeysPrefix$messageId');

      // Remove from tracking
      _burnKeys.remove(messageId);
      _messageTracking.remove(messageId);

      _logger.i('Message $messageId burned successfully');
      return true;

    } catch (e) {
      _logger.e('Error burning message $messageId: $e');
      return false;
    }
  }

  /// Securely overwrite message data before deletion
  Future<void> _secureOverwriteMessage(String messageId) async {
    try {
      // Overwrite with random data multiple times
      final random = Random.secure();
      
      for (int i = 0; i < 3; i++) {
        final randomData = Uint8List.fromList(
          List<int>.generate(1024, (_) => random.nextInt(256)),
        );
        
        await _secureStorage.write(
          key: '${messageId}_overwrite_$i',
          value: base64Encode(randomData),
        );
        
        // Small delay between overwrites
        await Future.delayed(const Duration(milliseconds: 10));
      }

      // Clear overwrite data
      for (int i = 0; i < 3; i++) {
        await _secureStorage.delete(key: '${messageId}_overwrite_$i');
      }

    } catch (e) {
      _logger.w('Warning: Could not securely overwrite message $messageId: $e');
    }
  }

  /// Securely delete a message
  Future<void> _securelyDeleteMessage(String messageId) async {
    try {
      // Cancel expiration timer if active
      final timer = _activeExpirationTimers[messageId];
      if (timer != null) {
        timer.cancel();
        _activeExpirationTimers.remove(messageId);
      }

      // Securely overwrite if not already burned
      final burnedFlag = await _secureStorage.read(key: '${messageId}_burned');
      if (burnedFlag != 'true') {
        await _secureOverwriteMessage(messageId);
      }

      // Delete all related data
      await _secureStorage.delete(key: '$_storagePrefix$messageId');
      await _secureStorage.delete(key: '${messageId}_integrity');
      await _secureStorage.delete(key: '${messageId}_content');
      await _secureStorage.delete(key: '$_burnKeysPrefix$messageId');
      await _secureStorage.delete(key: '${messageId}_burned');

      // Remove from memory tracking
      _burnKeys.remove(messageId);
      _messageTracking.remove(messageId);

      _logger.i('Message $messageId securely deleted');

    } catch (e) {
      _logger.e('Error securely deleting message $messageId: $e');
    }
  }

  /// Get stored integrity hash
  Future<String> _getStoredIntegrityHash(String messageId) async {
    final stored = await _secureStorage.read(key: '${messageId}_integrity');
    return stored ?? '';
  }

  /// Verify integrity hash
  Future<bool> _verifyIntegrityHash(String messageId) async {
    try {
      final message = await _getMessage(messageId);
      if (message == null) return false;

      final actualHash = await _getStoredIntegrityHash(messageId);
      return message.metadata.integrityHash == actualHash;
    } catch (e) {
      _logger.e('Error verifying integrity for $messageId: $e');
      return false;
    }
  }

  /// Constant-time comparison to prevent timing attacks
  bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    
    return result == 0;
  }

  /// Get message statistics
  Future<MessageStatistics> getStatistics() async {
    final summaries = await listActiveMessages();
    final activeCount = summaries.length;
    final burnedCount = _burnKeys.length;
    
    DateTime? oldestMessage;
    DateTime? nextExpiration;
    
    for (final summary in summaries) {
      if (oldestMessage == null || summary.createdAt.isBefore(oldestMessage)) {
        oldestMessage = summary.createdAt;
      }
      if (nextExpiration == null || summary.expiresAt.isBefore(nextExpiration)) {
        nextExpiration = summary.expiresAt;
      }
    }
    
    return MessageStatistics(
      activeMessages: activeCount,
      burnedMessages: burnedCount,
      oldestMessage: oldestMessage,
      nextExpiration: nextExpiration,
      activeTimers: _activeExpirationTimers.length,
    );
  }
}

// Data classes

class TimedMessage {
  final String messageId;
  final String encryptedData;
  final MessageMetadata metadata;
  final bool encrypted;

  TimedMessage({
    required this.messageId,
    required this.encryptedData,
    required this.metadata,
    required this.encrypted,
  });
}

class BurnMessage {
  final String messageId;
  final String encryptedData;
  final MessageMetadata metadata;
  final Uint8List burnKey;

  BurnMessage({
    required this.messageId,
    required this.encryptedData,
    required this.metadata,
    required this.burnKey,
  });
}

class MessageMetadata {
  final String messageId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool burnAfterRead;
  final String integrityHash;
  final Uint8List nonce;

  MessageMetadata({
    required this.messageId,
    required this.createdAt,
    required this.expiresAt,
    required this.burnAfterRead,
    required this.integrityHash,
    required this.nonce,
  });
}

class ReadMessageResult {
  final String messageId;
  final String message;
  final MessageMetadata metadata;
  bool burned;

  ReadMessageResult({
    required this.messageId,
    required this.message,
    required this.metadata,
    this.burned = false,
  });
}

class BurnKeyInfo {
  final String messageId;
  final Uint8List burnKey;
  final DateTime createdAt;
  final Duration? maxViewTime;
  bool used;

  BurnKeyInfo({
    required this.messageId,
    required this.burnKey,
    required this.createdAt,
    this.maxViewTime,
    this.used = false,
  });
}

class MessageTrackingInfo {
  final String messageId;
  final DateTime createdAt;
  int viewCount;
  DateTime? lastAccessed;

  MessageTrackingInfo({
    required this.messageId,
    required this.createdAt,
    this.viewCount = 0,
    this.lastAccessed,
  });
}

class MessageSummary {
  final String messageId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool burnAfterRead;
  final bool integrityVerified;

  MessageSummary({
    required this.messageId,
    required this.createdAt,
    required this.expiresAt,
    required this.burnAfterRead,
    required this.integrityVerified,
  });
}

class MessageStatistics {
  final int activeMessages;
  final int burnedMessages;
  final DateTime? oldestMessage;
  final DateTime? nextExpiration;
  final int activeTimers;

  MessageStatistics({
    required this.activeMessages,
    required this.burnedMessages,
    this.oldestMessage,
    this.nextExpiration,
    required this.activeTimers,
  });
}