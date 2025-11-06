import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DatabaseService {
  static DatabaseService? _instance;
  static DatabaseService get instance => _instance!;
  
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String KEY_NAME = 'database_password';
  
  Database? _database;
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  
  DatabaseService._();
  
  static Future<void> initialize() async {
    if (_instance == null) {
      _instance = DatabaseService._();
    }
    await _instance!._initDatabase();
  }
  
  Future<void> _initDatabase() async {
    try {
      // Generate or load database password
      String? password = await _secureStorage.read(key: KEY_NAME);
      if (password == null) {
        password = _generatePassword();
        await _secureStorage.write(key: KEY_NAME, value: password);
      }
      
      // Get database directory
      final directory = await getApplicationDocumentsDirectory();
      final dbPath = '${directory.path}/encrypted_mesh_chat.db';
      
      // Open database with encryption
      _database = await openDatabase(
        dbPath,
        password: password,
        onCreate: _onCreate,
        version: 1,
      );
      
      _isInitialized = true;
    } catch (e) {
      print('Error initializing database: $e');
    }
  }
  
  String _generatePassword() {
    final random = DateTime.now().microsecondsSinceEpoch;
    final hash = sha256.convert(utf8.encode(random.toString())).toString();
    return hash.substring(0, 32); // 32 characters for strong password
  }
  
  Future<void> _onCreate(Database db, int version) async {
    // Create contacts table
    await db.execute('''
      CREATE TABLE contacts (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        public_key TEXT,
        bluetooth_id TEXT,
        status TEXT DEFAULT 'offline',
        last_seen INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        avatar_url TEXT,
        metadata TEXT,
        is_blocked INTEGER DEFAULT 0,
        nickname TEXT,
        message_count INTEGER DEFAULT 0
      )
    ''');
    
    // Create messages table
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        sender_id TEXT NOT NULL,
        recipient_id TEXT NOT NULL,
        content TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'text',
        timestamp INTEGER NOT NULL,
        is_encrypted INTEGER DEFAULT 1,
        encrypted_content TEXT,
        status TEXT DEFAULT 'pending',
        metadata TEXT,
        FOREIGN KEY (sender_id) REFERENCES contacts (id),
        FOREIGN KEY (recipient_id) REFERENCES contacts (id)
      )
    ''');
    
    // Create attachments table
    await db.execute('''
      CREATE TABLE attachments (
        id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        type TEXT NOT NULL,
        file_name TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        file_path TEXT,
        thumbnail BLOB,
        metadata TEXT,
        is_encrypted INTEGER DEFAULT 0,
        encrypted_data TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (message_id) REFERENCES messages (id)
      )
    ''');
    
    // Create index for faster queries
    await db.execute('CREATE INDEX idx_messages_sender ON messages (sender_id)');
    await db.execute('CREATE INDEX idx_messages_recipient ON messages (recipient_id)');
    await db.execute('CREATE INDEX idx_messages_timestamp ON messages (timestamp)');
    await db.execute('CREATE INDEX idx_contacts_status ON contacts (status)');
  }
  
  Database get _db {
    if (!_isInitialized || _database == null) {
      throw Exception('Database not initialized');
    }
    return _database!;
  }
  
  // Contact operations
  Future<void> insertContact(Map<String, dynamic> contact) async {
    await _db.insert('contacts', contact, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  
  Future<List<Map<String, dynamic>>> getAllContacts() async {
    final result = await _db.query('contacts', orderBy: 'name ASC');
    return result;
  }
  
  Future<Map<String, dynamic>?> getContact(String id) async {
    final result = await _db.query('contacts', where: 'id = ?', whereArgs: [id]);
    return result.isNotEmpty ? result.first : null;
  }
  
  Future<void> updateContact(String id, Map<String, dynamic> updates) async {
    await _db.update('contacts', updates, where: 'id = ?', whereArgs: [id]);
  }
  
  Future<void> deleteContact(String id) async {
    // Delete associated messages and attachments first
    await _db.delete('messages', where: 'sender_id = ? OR recipient_id = ?', whereArgs: [id, id]);
    await _db.delete('contacts', where: 'id = ?', whereArgs: [id]);
  }
  
  // Message operations
  Future<void> insertMessage(Map<String, dynamic> message) async {
    await _db.insert('messages', message, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  
  Future<List<Map<String, dynamic>>> getMessagesForContact(String contactId) async {
    final result = await _db.query(
      'messages',
      where: '(sender_id = ? AND recipient_id = ?) OR (sender_id = ? AND recipient_id = ?)',
      whereArgs: [contactId, _getCurrentUserId(), _getCurrentUserId(), contactId],
      orderBy: 'timestamp ASC',
    );
    return result;
  }
  
  Future<List<Map<String, dynamic>>> getAllMessages() async {
    final result = await _db.query('messages', orderBy: 'timestamp DESC');
    return result;
  }
  
  Future<void> updateMessageStatus(String id, String status) async {
    await _db.update('messages', {'status': status}, where: 'id = ?', whereArgs: [id]);
  }
  
  Future<void> deleteMessage(String id) async {
    // Delete associated attachments first
    await _db.delete('attachments', where: 'message_id = ?', whereArgs: [id]);
    await _db.delete('messages', where: 'id = ?', whereArgs: [id]);
  }
  
  // Attachment operations
  Future<void> insertAttachment(Map<String, dynamic> attachment) async {
    await _db.insert('attachments', attachment, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  
  Future<List<Map<String, dynamic>>> getAttachmentsForMessage(String messageId) async {
    final result = await _db.query('attachments', where: 'message_id = ?', whereArgs: [messageId]);
    return result;
  }
  
  Future<void> deleteAttachment(String id) async {
    await _db.delete('attachments', where: 'id = ?', whereArgs: [id]);
  }
  
  // Utility methods
  String _getCurrentUserId() {
    // This should be implemented based on your user management
    // For now, return a placeholder
    return 'current_user_id';
  }
  
  // Backup and restore
  Future<void> backupDatabase(String backupPath) async {
    if (!_isInitialized || _database == null) {
      throw Exception('Database not initialized');
    }
    
    // Close database
    await _db.close();
    
    // Copy database file
    final sourcePath = '${(await getApplicationDocumentsDirectory()).path}/encrypted_mesh_chat.db';
    final sourceFile = File(sourcePath);
    final backupFile = File(backupPath);
    
    await backupFile.writeAsBytes(await sourceFile.readAsBytes());
    
    // Reopen database
    String? password = await _secureStorage.read(key: KEY_NAME);
    _database = await openDatabase(
      '${(await getApplicationDocumentsDirectory()).path}/encrypted_mesh_chat.db',
      password: password,
      onCreate: _onCreate,
      version: 1,
    );
  }
  
  Future<void> restoreDatabase(String backupPath) async {
    // Close current database
    if (_database != null) {
      await _db.close();
    }
    
    // Restore backup
    final targetPath = '${(await getApplicationDocumentsDirectory()).path}/encrypted_mesh_chat.db';
    final backupFile = File(backupPath);
    final targetFile = File(targetPath);
    
    await targetFile.writeAsBytes(await backupFile.readAsBytes());
    
    // Reopen with restored database
    String? password = await _secureStorage.read(key: KEY_NAME);
    _database = await openDatabase(
      targetPath,
      password: password,
      onCreate: _onCreate,
      version: 1,
    );
  }
  
  // Database maintenance
  Future<void> vacuum() async {
    await _db.execute('VACUUM');
  }
  
  Future<void> close() async {
    if (_database != null) {
      await _db.close();
      _database = null;
      _isInitialized = false;
    }
  }
  
  // Check database integrity
  Future<Map<String, dynamic>> getDatabaseInfo() async {
    final contactsCount = Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM contacts'));
    final messagesCount = Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM messages'));
    final attachmentsCount = Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM attachments'));
    
    return {
      'contacts_count': contactsCount ?? 0,
      'messages_count': messagesCount ?? 0,
      'attachments_count': attachmentsCount ?? 0,
      'is_initialized': _isInitialized,
    };
  }
}