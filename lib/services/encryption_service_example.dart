import 'dart:typed_data';
import 'encryption_service.dart';

/// Example demonstrating how to use the EncryptionService
/// 
/// This example shows:
/// 1. Key generation and storage
/// 2. QR code generation for public key sharing
/// 3. Shared secret derivation between two parties
/// 4. Encryption and decryption of messages
/// 5. Key fingerprint generation for verification
/// 
/// Run this example to test the encryption functionality.
class EncryptionServiceExample {
  static Future<void> run() async {
    print('=== Encryption Service Example ===\n');

    // Initialize two separate instances to simulate two users
    final user1 = EncryptionService();
    final user2 = EncryptionService();

    // User 1: Generate and initialize keys
    print('1. Generating keys for User 1...');
    await user1.initialize();
    final user1Fingerprint = await user1.getPublicKeyFingerprint();
    print('   User 1 Key Fingerprint: $user1Fingerprint');
    
    // User 2: Generate and initialize keys
    print('\n2. Generating keys for User 2...');
    await user2.initialize();
    final user2Fingerprint = await user2.getPublicKeyFingerprint();
    print('   User 2 Key Fingerprint: $user2Fingerprint');

    // User 1: Generate QR code for public key
    print('\n3. Generating QR code for User 1 public key...');
    final qrDataUser1 = await user1.getPublicKeyQrString();
    print('   QR Code Data: $qrDataUser1');
    print('   (In real app, this would be displayed as a QR code image)');

    // User 2: Generate QR code for public key
    print('\n4. Generating QR code for User 2 public key...');
    final qrDataUser2 = await user2.getPublicKeyQrString();
    print('   QR Code Data: $qrDataUser2');
    print('   (In real app, this would be displayed as a QR code image)');

    // Both users extract public keys from each other's QR codes
    print('\n5. Extracting public keys from QR codes...');
    final user2PublicKey = EncryptionService.parsePublicKeyFromQr(qrDataUser2);
    final user1PublicKey = EncryptionService.parsePublicKeyFromQr(qrDataUser1);
    print('   User 1 extracted User 2\'s public key');
    print('   User 2 extracted User 1\'s public key');

    // Derive shared secrets
    print('\n6. Deriving shared secrets...');
    final user1SharedSecret = await user1.deriveSharedSecret(user2PublicKey);
    final user2SharedSecret = await user2.deriveSharedSecret(user1PublicKey);
    
    // Verify that both users have the same shared secret
    print('   User 1 Shared Secret Length: ${user1SharedSecret.length} bytes');
    print('   User 2 Shared Secret Length: ${user2SharedSecret.length} bytes');
    
    // Convert to hex for comparison
    final user1SecretHex = user1SharedSecret.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final user2SecretHex = user2SharedSecret.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final secretsMatch = user1SecretHex == user2SecretHex;
    print('   Shared secrets match: $secretsMatch');

    // Encrypt and decrypt a message
    print('\n7. Testing encryption and decryption...');
    const message = 'Hello, secure mesh network! This is a secret message.';
    final messageBytes = Uint8List.fromList(message.codeUnits);
    
    print('   Original message: $message');
    
    // User 1 encrypts the message
    print('\n   User 1 encrypting message...');
    final encryptedMessage = await user1.encrypt(messageBytes, user1SharedSecret);
    print('   Encrypted message (base64): $encryptedMessage');
    print('   Encrypted message length: ${encryptedMessage.length} characters');
    
    // User 2 decrypts the message
    print('\n   User 2 decrypting message...');
    final decryptedBytes = await user2.decrypt(encryptedMessage, user2SharedSecret);
    final decryptedMessage = String.fromCharCodes(decryptedBytes);
    print('   Decrypted message: $decryptedMessage');
    
    // Verify the message is correct
    final messageMatches = message == decryptedMessage;
    print('   Message matches original: $messageMatches');

    // Test key rotation
    print('\n8. Testing key rotation...');
    final oldFingerprint = await user1.getPublicKeyFingerprint();
    print('   User 1 old key fingerprint: $oldFingerprint');
    
    await user1.rotateKeys();
    
    final newFingerprint = await user1.getPublicKeyFingerprint();
    print('   User 1 new key fingerprint: $newFingerprint');
    final keyRotated = oldFingerprint != newFingerprint;
    print('   Key successfully rotated: $keyRotated}');

    // Test error handling - try to decrypt with wrong key
    print('\n9. Testing error handling...');
    try {
      final fakeSharedSecret = Uint8List(32); // Fake shared secret
      await user2.decrypt(encryptedMessage, fakeSharedSecret);
      print('   ERROR: Decryption should have failed!');
    } catch (e) {
      print('   Decryption correctly failed with error: ${e.toString()}');
    }

    print('\n=== Example completed successfully! ===');
  }
}

/// Example usage in a Flutter widget:
/*
class MyWidget extends StatefulWidget {
  @override
  _MyWidgetState createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  late EncryptionService encryptionService;
  Uint8List? qrCodeImage;
  String? publicKeyQrString;
  
  @override
  void initState() {
    super.initState();
    initializeEncryption();
  }
  
  Future<void> initializeEncryption() async {
    encryptionService = EncryptionService();
    await encryptionService.initialize();
    
    // Generate QR code image
    qrCodeImage = await encryptionService.generatePublicKeyQrCode();
    
    // Or get QR code data string
    publicKeyQrString = await encryptionService.getPublicKeyQrString();
    
    setState(() {});
  }
  
  @override
  Widget build(BuildContext context) {
    if (qrCodeImage == null) {
      return CircularProgressIndicator();
    }
    
    return Scaffold(
      appBar: AppBar(title: Text('Encryption Example')),
      body: Column(
        children: [
          // Display QR code
          Image.memory(qrCodeImage!),
          
          // Display QR code string
          SelectableText('QR Code Data: $publicKeyQrString'),
          
          // Generate fingerprint
          FutureBuilder<String>(
            future: encryptionService.getPublicKeyFingerprint(),
            builder: (context, snapshot) {
              return Text('Key Fingerprint: ${snapshot.data ?? "Loading..."}');
            },
          ),
          
          // Test encryption/decryption
          ElevatedButton(
            onPressed: () => testEncryption(),
            child: Text('Test Encryption'),
          ),
        ],
      ),
    );
  }
  
  Future<void> testEncryption() async {
    // Get public key
    final publicKey = await encryptionService.getPublicKey();
    
    // Simulate another user
    final otherUser = EncryptionService();
    await otherUser.initialize();
    
    // Exchange keys (in real app, this would be via QR codes)
    final otherPublicKey = await otherUser.getPublicKey();
    
    // Derive shared secret
    final sharedSecret = await encryptionService.deriveSharedSecret(otherPublicKey);
    
    // Encrypt message
    final message = Uint8List.fromList('Hello World'.codeUnits);
    final encrypted = await encryptionService.encrypt(message, sharedSecret);
    
    // Decrypt message
    final decrypted = await otherUser.decrypt(encrypted, 
      await otherUser.deriveSharedSecret(publicKey));
    
    print('Original: ${String.fromCharCodes(message)}');
    print('Decrypted: ${String.fromCharCodes(decrypted)}');
  }
}
*/

/// Example of secure key sharing workflow:
/*
Future<void> secureKeySharingExample() async {
  // User A wants to share a key with User B
  
  // User A generates QR code
  final userA = EncryptionService();
  await userA.initialize();
  final qrImage = await userA.generatePublicKeyQrCode();
  
  // Display qrImage to User A
  // User A shows it to User B (out of band)
  
  // User B scans QR code and extracts public key
  final scannedQrData = '...'; // From QR scanner
  final userAPublicKey = EncryptionService.parsePublicKeyFromQr(scannedQrData);
  
  // User B generates their own keypair and QR code
  final userB = EncryptionService();
  await userB.initialize();
  final userBQrImage = await userB.generatePublicKeyQrCode();
  
  // User B shows their QR code to User A
  // User A scans and extracts User B's public key
  final userBPublicKey = EncryptionService.parsePublicKeyFromQr('...');
  
  // Now both users can derive the same shared secret
  final userASharedSecret = await userA.deriveSharedSecret(userBPublicKey);
  final userBSharedSecret = await userB.deriveSharedSecret(userAPublicKey);
  
  // Use the shared secret for encrypted communication
  // ... send encrypted messages using userASharedSecret and userBSharedSecret
}
*/
