/// Example Usage of Offline Queue Service
/// 
/// This file demonstrates how to integrate and use the OfflineQueueService
/// for reliable message delivery across network conditions.

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/offline_queue_service.dart';
import '../services/transport_manager.dart';
import '../services/transport.dart';

/// Example demonstrating complete integration of the offline queue service
class OfflineQueueExample extends StatefulWidget {
  @override
  _OfflineQueueExampleState createState() => _OfflineQueueExampleState();
}

class _OfflineQueueExampleState extends State<OfflineQueueExample> {
  late OfflineQueueService _queueService;
  late TransportManager _transportManager;
  
  StreamSubscription<ConnectivityState>? _connectivitySubscription;
  StreamSubscription<QueuedMessage>? _messageDeliveredSubscription;
  StreamSubscription<QueuedMessage>? _messageFailedSubscription;
  StreamSubscription<QueueStatistics>? _statisticsSubscription;
  
  List<QueuedMessage> _recentMessages = [];
  QueueStatistics? _currentStats;
  ConnectivityState _currentConnectivity = ConnectivityState.unknown;
  
  @override
  void initState() {
    super.initState();
    _initializeServices();
  }
  
  /// Initialize the offline queue service and set up event listeners
  Future<void> _initializeServices() async {
    try {
      // Initialize transport manager
      _transportManager = TransportManager();
      
      // Initialize offline queue service
      await OfflineQueueService.initialize();
      _queueService = OfflineQueueService.instance;
      
      // Set up event listeners
      _setupEventListeners();
      
      setState(() {});
      
      print('Services initialized successfully');
    } catch (e) {
      print('Failed to initialize services: $e');
    }
  }
  
  /// Set up event listeners for queue events
  void _setupEventListeners() {
    // Listen for connectivity changes
    _connectivitySubscription = _queueService.connectivityStream.listen(
      (state) {
        setState(() {
          _currentConnectivity = state;
        });
        _showConnectivitySnackBar(state);
      },
    );
    
    // Listen for successfully delivered messages
    _messageDeliveredSubscription = _queueService.messageDeliveredStream.listen(
      (message) {
        setState(() {
          _recentMessages.insert(0, message);
          if (_recentMessages.length > 10) {
            _recentMessages.removeLast();
          }
        });
        _showSuccessSnackBar('Message delivered: ${message.id}');
      },
    );
    
    // Listen for failed messages
    _messageFailedSubscription = _queueService.messageFailedStream.listen(
      (message) {
        setState(() {
          _recentMessages.insert(0, message);
          if (_recentMessages.length > 10) {
            _recentMessages.removeLast();
          }
        });
        _showErrorSnackBar('Message failed: ${message.id}');
      },
    );
    
    // Listen for statistics updates
    _statisticsSubscription = _queueService.statisticsStream.listen(
      (stats) {
        setState(() {
          _currentStats = stats;
        });
      },
    );
  }
  
  /// Send a test message using the offline queue
  Future<void> _sendTestMessage(MessagePriority priority) async {
    try {
      // Create a test target (recipient)
      final target = TransportTarget(
        id: 'test_device_${DateTime.now().millisecondsSinceEpoch}',
        address: '00:11:22:33:44:55',
        name: 'Test Device',
        metadata: {
          'device_type': 'smartphone',
          'transport_preference': 'ble',
        },
      );
      
      // Create test message content
      final content = utf8.encode('Hello from Offline Queue Service! Priority: ${priority.toString()}');
      
      // Queue the message
      final messageId = await _queueService.queueMessage(
        target: target,
        content: Uint8List.fromList(content),
        priority: priority,
        messageType: 'text',
        metadata: {
          'example': true,
          'timestamp': DateTime.now().toIso8601String(),
        },
        preferredTransportType: 'BLE',
        expiresIn: Duration(hours: 24), // Message expires in 24 hours
      );
      
      if (messageId != null) {
        _showSuccessSnackBar('Message queued: $messageId');
      } else {
        _showInfoSnackBar('Message was duplicate and not queued');
      }
    } catch (e) {
      _showErrorSnackBar('Failed to queue message: $e');
    }
  }
  
  /// Send an attachment message
  Future<void> _sendAttachmentMessage() async {
    try {
      final target = TransportTarget(
        id: 'attachment_device',
        address: '00:11:22:33:44:66',
        name: 'Attachment Device',
      );
      
      // Create attachment metadata
      final attachmentData = Uint8List.fromList([1, 2, 3, 4, 5]); // Fake file data
      final metadata = {
        'file_name': 'test_image.jpg',
        'file_size': attachmentData.length,
        'mime_type': 'image/jpeg',
      };
      
      final messageId = await _queueService.queueMessage(
        target: target,
        content: attachmentData,
        priority: MessagePriority.high,
        messageType: 'attachment',
        metadata: metadata,
        expiresIn: Duration(days: 7),
      );
      
      if (messageId != null) {
        _showSuccessSnackBar('Attachment queued: $messageId');
      }
    } catch (e) {
      _showErrorSnackBar('Failed to queue attachment: $e');
    }
  }
  
  /// Force process the queue (useful for testing)
  Future<void> _forceProcessQueue() async {
    try {
      await _queueService.forceProcessQueue();
      _showInfoSnackBar('Queue processing triggered');
    } catch (e) {
      _showErrorSnackBar('Failed to force process queue: $e');
    }
  }
  
  /// Clear all queued messages
  Future<void> _clearAllMessages() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear All Messages'),
        content: Text('Are you sure you want to clear all queued messages?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Clear All'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      try {
        await _queueService.clearAllQueuedMessages();
        setState(() {
          _recentMessages.clear();
        });
        _showSuccessSnackBar('All messages cleared');
      } catch (e) {
        _showErrorSnackBar('Failed to clear messages: $e');
      }
    }
  }
  
  /// Show connectivity status snack bar
  void _showConnectivitySnackBar(ConnectivityState state) {
    String message;
    Color color;
    
    switch (state) {
      case ConnectivityState.connected:
        message = 'Network connectivity restored';
        color = Colors.green;
        break;
      case ConnectivityState.disconnected:
        message = 'Network connectivity lost';
        color = Colors.red;
        break;
      case ConnectivityState.unknown:
        message = 'Network connectivity unknown';
        color = Colors.orange;
        break;
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: Duration(seconds: 3),
      ),
    );
  }
  
  /// Show success snack bar
  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }
  
  /// Show error snack bar
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 4),
      ),
    );
  }
  
  /// Show info snack bar
  void _showInfoSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 2),
      ),
    );
  }
  
  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _messageDeliveredSubscription?.cancel();
    _messageFailedSubscription?.cancel();
    _statisticsSubscription?.cancel();
    _queueService.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Offline Queue Service Demo'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _forceProcessQueue,
            tooltip: 'Force Process Queue',
          ),
          IconButton(
            icon: Icon(Icons.clear_all),
            onPressed: _clearAllMessages,
            tooltip: 'Clear All Messages',
          ),
        ],
      ),
      body: Column(
        children: [
          // Connectivity Status Card
          _buildConnectivityCard(),
          
          // Statistics Card
          if (_currentStats != null) _buildStatisticsCard(_currentStats!),
          
          // Quick Actions
          _buildQuickActionsCard(),
          
          // Recent Messages
          Expanded(child: _buildRecentMessagesList()),
        ],
      ),
    );
  }
  
  Widget _buildConnectivityCard() {
    Color statusColor;
    IconData statusIcon;
    String statusText;
    
    switch (_currentConnectivity) {
      case ConnectivityState.connected:
        statusColor = Colors.green;
        statusIcon = Icons.wifi;
        statusText = 'Connected';
        break;
      case ConnectivityState.disconnected:
        statusColor = Colors.red;
        statusIcon = Icons.wifi_off;
        statusText = 'Disconnected';
        break;
      case ConnectivityState.unknown:
        statusColor = Colors.orange;
        statusIcon = Icons.help;
        statusText = 'Unknown';
        break;
    }
    
    return Card(
      margin: EdgeInsets.all(16),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(statusIcon, color: statusColor, size: 32),
            SizedBox(width: 16),
            Text(
              'Network Status: $statusText',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatisticsCard(QueueStatistics stats) {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Queue Statistics',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Queued', stats.totalQueued.toString(), Colors.blue),
                _buildStatItem('In Queue', stats.currentQueueSize.toString(), Colors.orange),
                _buildStatItem('Success', stats.successfullySent.toString(), Colors.green),
                _buildStatItem('Failed', stats.failedMessages.toString(), Colors.red),
              ],
            ),
            SizedBox(height: 8),
            Text('Success Rate: ${stats.successRate.toStringAsFixed(1)}%'),
            Text('Average Queue Time: ${stats.averageQueueTime.inMinutes}m ${stats.averageQueueTime.inSeconds % 60}s'),
            Text('Total Retries: ${stats.totalRetries}'),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(color: Colors.grey[600])),
      ],
    );
  }
  
  Widget _buildQuickActionsCard() {
    return Card(
      margin: EdgeInsets.all(16),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Actions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildActionButton('Urgent', Icons.priority_high, Colors.red, 
                  () => _sendTestMessage(MessagePriority.urgent)),
                _buildActionButton('High', Icons.trending_up, Colors.orange, 
                  () => _sendTestMessage(MessagePriority.high)),
                _buildActionButton('Normal', Icons.remove, Colors.blue, 
                  () => _sendTestMessage(MessagePriority.normal)),
                _buildActionButton('Low', Icons.keyboard_arrow_down, Colors.grey, 
                  () => _sendTestMessage(MessagePriority.low)),
                _buildActionButton('Attachment', Icons.attach_file, Colors.purple, 
                  _sendAttachmentMessage),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onPressed) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
    );
  }
  
  Widget _buildRecentMessagesList() {
    if (_recentMessages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.message_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No recent messages', style: TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 16),
      itemCount: _recentMessages.length,
      itemBuilder: (context, index) {
        final message = _recentMessages[index];
        return _buildMessageListItem(message);
      },
    );
  }
  
  Widget _buildMessageListItem(QueuedMessage message) {
    final isDelivered = message.attemptCount > 0;
    final hasFailed = message.attemptCount >= message.maxAttempts;
    
    return Card(
      margin: EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getPriorityColor(message.priority),
          child: Icon(_getPriorityIcon(message.priority), color: Colors.white),
        ),
        title: Text('${message.messageType} - ${message.target.name ?? message.target.id}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Priority: ${message.priority.toString()}'),
            Text('Attempts: ${message.attemptCount}/${message.maxAttempts}'),
            if (message.lastError != null) 
              Text('Last Error: ${message.lastError}', 
                style: TextStyle(color: Colors.red)),
            Text('Created: ${message.createdAt.toLocal()}'),
          ],
        ),
        trailing: hasFailed 
          ? Icon(Icons.error, color: Colors.red)
          : isDelivered 
            ? Icon(Icons.check_circle, color: Colors.green)
            : Icon(Icons.schedule, color: Colors.orange),
      ),
    );
  }
  
  Color _getPriorityColor(MessagePriority priority) {
    switch (priority) {
      case MessagePriority.urgent:
        return Colors.red;
      case MessagePriority.high:
        return Colors.orange;
      case MessagePriority.normal:
        return Colors.blue;
      case MessagePriority.low:
        return Colors.grey;
    }
  }
  
  IconData _getPriorityIcon(MessagePriority priority) {
    switch (priority) {
      case MessagePriority.urgent:
        return Icons.priority_high;
      case MessagePriority.high:
        return Icons.trending_up;
      case MessagePriority.normal:
        return Icons.remove;
      case MessagePriority.low:
        return Icons.keyboard_arrow_down;
    }
  }
}

/// Integration example showing how to use the offline queue service
/// in a production application
class ProductionIntegrationExample {
  late OfflineQueueService _queueService;
  
  /// Initialize the service with proper dependency injection
  Future<void> initialize() async {
    await OfflineQueueService.initialize();
    _queueService = OfflineQueueService.instance;
    
    // Set up event listeners for app-wide notifications
    _setupEventListeners();
  }
  
  /// Set up application-wide event listeners
  void _setupEventListeners() {
    // Handle connectivity changes
    _queueService.connectivityStream.listen((state) {
      switch (state) {
        case ConnectivityState.connected:
          print('App: Network restored - starting message delivery');
          _queueService.forceProcessQueue();
          break;
        case ConnectivityState.disconnected:
          print('App: Network lost - messages will be queued');
          break;
        case ConnectivityState.unknown:
          print('App: Network state unknown');
          break;
      }
    });
    
    // Handle delivered messages for user feedback
    _queueService.messageDeliveredStream.listen((message) {
      print('App: Message delivered successfully: ${message.id}');
      // Show user notification, update UI, etc.
    });
    
    // Handle failed messages for user notification
    _queueService.messageFailedStream.listen((message) {
      print('App: Message failed permanently: ${message.id}');
      // Show user notification about delivery failure
    });
  }
  
  /// Send message with automatic offline queuing
  Future<String?> sendMessage({
    required String recipientId,
    required String recipientAddress,
    required String content,
    MessagePriority priority = MessagePriority.normal,
    Map<String, dynamic> metadata = const {},
  }) async {
    try {
      final target = TransportTarget(
        id: recipientId,
        address: recipientAddress,
        metadata: metadata,
      );
      
      final contentBytes = Uint8List.fromList(utf8.encode(content));
      
      return await _queueService.queueMessage(
        target: target,
        content: contentBytes,
        priority: priority,
        messageType: 'text',
        metadata: metadata,
      );
    } catch (e) {
      print('Failed to send message: $e');
      return null;
    }
  }
  
  /// Send attachment with automatic offline queuing
  Future<String?> sendAttachment({
    required String recipientId,
    required String recipientAddress,
    required Uint8List fileData,
    required String fileName,
    required String mimeType,
    MessagePriority priority = MessagePriority.high,
  }) async {
    try {
      final target = TransportTarget(
        id: recipientId,
        address: recipientAddress,
        metadata: {
          'file_name': fileName,
          'mime_type': mimeType,
        },
      );
      
      final metadata = {
        'file_name': fileName,
        'mime_type': mimeType,
        'file_size': fileData.length,
      };
      
      return await _queueService.queueMessage(
        target: target,
        content: fileData,
        priority: priority,
        messageType: 'attachment',
        metadata: metadata,
        expiresIn: Duration(days: 30), // Attachments expire in 30 days
      );
    } catch (e) {
      print('Failed to send attachment: $e');
      return null;
    }
  }
  
  /// Get current queue status for UI display
  QueueStatistics getQueueStatus() {
    return _queueService.getCurrentStatistics();
  }
  
  /// Check if network is available for immediate sending
  bool get isNetworkAvailable {
    return _queueService.connectivityState == ConnectivityState.connected;
  }
}