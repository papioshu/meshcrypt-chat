import 'package:flutter_test/flutter_test.dart';
import 'package:encrypted_mesh_chat/services/encryption_service.dart';

void main() {
  group('EncryptionService Tests', () {
    late EncryptionService userA;
    late EncryptionService userB;

    setUp(() async {
      userA = EncryptionService();
      userB = EncryptionService();
      
      // Initialize both users
      await userA.initialize();
      await userB.initialize();
    });

    test('should generate keypairs', () async {
      final publicKeyA = await userA.getPublicKey();
      final publicKeyB = await userB.getPublicKey();
      
      expect(publicKeyA, isNotEmpty);
      expect(publicKeyB, isNotEmpty);
      expect(publicKeyA.length, 32); // X25519 public key is 32 bytes
      expect(publicKeyB.length, 32);
    });

    test('should derive same shared secret for both parties', () async {
      // Get public keys
      final publicKeyA = await userA.getPublicKey();
      final publicKeyB = await userB.getPublicKey();
      
      // Derive shared secrets
      final sharedSecretA = await userA.deriveSharedSecret(publicKeyB);
      final sharedSecretB = await userB.deriveSharedSecret(publicKeyA);
      
      // Both should be identical
      expect(sharedSecretA, equals(sharedSecretB));
      expect(sharedSecretA.length, 32); // X25519 shared secret is 32 bytes
    });

    test('should encrypt and decrypt messages', () async {
      // Get public keys
      final publicKeyA = await userA.getPublicKey();
      final publicKeyB = await userB.getPublicKey();
      
      // Derive shared secret
      final sharedSecret = await userA.deriveSharedSecret(publicKeyB);
      
      // Original message
      final originalMessage = Uint8List.fromList('Hello, secure world!'.codeUnits);
      
      // Encrypt
      final encrypted = await userA.encrypt(originalMessage, sharedSecret);
      expect(encrypted, isNotEmpty);
      
      // Decrypt (using user's shared secret)
      final decrypted = await userB.decrypt(encrypted, 
        await userB.deriveSharedSecret(publicKeyA));
      
      // Verify
      expect(decrypted, equals(originalMessage));
      expect(String.fromCharCodes(decrypted), equals('Hello, secure world!'));
    });

    test('should generate different fingerprints for different keypairs', () async {
      final fingerprintA = await userA.getPublicKeyFingerprint();
      final fingerprintB = await userB.getPublicKeyFingerprint();
      
      expect(fingerprintA, isNotEmpty);
      expect(fingerprintB, isNotEmpty);
      expect(fingerprintA, isNot(equals(fingerprintB)));
    });

    test('should rotate keys successfully', () async {
      final oldPublicKey = await userA.getPublicKey();
      final oldFingerprint = await userA.getPublicKeyFingerprint();
      
      // Rotate keys
      await userA.rotateKeys();
      
      final newPublicKey = await userA.getPublicKey();
      final newFingerprint = await userA.getPublicKeyFingerprint();
      
      // Verify key changed
      expect(oldPublicKey, isNot(equals(newPublicKey)));
      expect(oldFingerprint, isNot(equals(newFingerprint)));
    });

    test('should parse valid QR code data', () async {
      final publicKey = await userA.getPublicKey();
      final qrData = 'MESH_PUBLIC_KEY:${base64Encode(publicKey)}';
      
      final parsedKey = EncryptionService.parsePublicKeyFromQr(qrData);
      
      expect(parsedKey, equals(publicKey));
    });

    test('should reject invalid QR code data', () {
      expect(
        () => EncryptionService.parsePublicKeyFromQr('INVALID_FORMAT'),
        throwsA(isA<Exception>()),
      );
      
      expect(
        () => EncryptionService.parsePublicKeyFromQr('MESH_PUBLIC_KEY:'),
        throwsA(isA<Exception>()),
      );
    });

    test('should reject malformed base64 data', () {
      expect(
        () => EncryptionService.parsePublicKeyFromQr('MESH_PUBLIC_KEY:!!!INVALID!!!'),
        throwsA(isA<Exception>()),
      );
    });

    test('should generate valid QR code data string', () async {
      final qrString = await userA.getPublicKeyQrString();
      
      expect(qrString, startsWith('MESH_PUBLIC_KEY:'));
      expect(qrString.length, greaterThan('MESH_PUBLIC_KEY:'.length));
    });

    test('should detect key rotation and update shared secret', () async {
      final userC = EncryptionService();
      await userC.initialize();
      
      final publicKeyA1 = await userA.getPublicKey();
      final publicKeyC = await userC.getPublicKey();
      
      // Derive initial shared secret
      final sharedSecret1 = await userA.deriveSharedSecret(publicKeyC);
      
      // Rotate user A's keys
      await userA.rotateKeys();
      final publicKeyA2 = await userA.getPublicKey();
      
      // Derive new shared secret
      final sharedSecret2 = await userA.deriveSharedSecret(publicKeyC);
      
      // Should be different
      expect(publicKeyA1, isNot(equals(publicKeyA2)));
      expect(sharedSecret1, isNot(equals(sharedSecret2)));
    });

    test('should handle encryption/decryption with additional authenticated data', () async {
      final publicKeyA = await userA.getPublicKey();
      final publicKeyB = await userB.getPublicKey();
      final sharedSecret = await userA.deriveSharedSecret(publicKeyB);
      
      final message = Uint8List.fromList('Test message with AAD'.codeUnits);
      final encrypted = await userA.encrypt(message, sharedSecret);
      final decrypted = await userB.decrypt(encrypted, 
        await userB.deriveSharedSecret(publicKeyA));
      
      expect(decrypted, equals(message));
    });

    test('should fail decryption with wrong shared secret', () async {
      final publicKeyA = await userA.getPublicKey();
      final publicKeyB = await userB.getPublicKey();
      final publicKeyC = await EncryptionService().getPublicKey();
      
      final sharedSecret = await userA.deriveSharedSecret(publicKeyB);
      final message = Uint8List.fromList('Secret message'.codeUnits);
      final encrypted = await userA.encrypt(message, sharedSecret);
      
      // Try to decrypt with wrong public key
      final wrongSharedSecret = await userC.deriveSharedSecret(publicKeyB);
      
      expect(
        () => userA.decrypt(encrypted, wrongSharedSecret),
        throwsA(isA<Exception>()),
      );
    });

    test('should provide fingerprint for public key verification', () async {
      final fingerprint1 = await userA.getPublicKeyFingerprint();
      final fingerprint2 = await userA.getPublicKeyFingerprint();
      
      // Fingerprint should be deterministic
      expect(fingerprint1, equals(fingerprint2));
      expect(fingerprint1.length, greaterThan(0));
      
      // Should be hex string
      expect(RegExp(r'^[a-f0-9]+$').hasMatch(fingerprint1), isTrue);
    });

    test('should generate unique nonces for encryption', () async {
      final publicKeyA = await userA.getPublicKey();
      final publicKeyB = await userB.getPublicKey();
      final sharedSecret = await userA.deriveSharedSecret(publicKeyB);
      
      final message1 = Uint8List.fromList('Message 1'.codeUnits);
      final message2 = Uint8List.fromList('Message 2'.codeUnits);
      
      final encrypted1 = await userA.encrypt(message1, sharedSecret);
      final encrypted2 = await userA.encrypt(message2, sharedSecret);
      
      // Different messages should produce different ciphertexts
      expect(encrypted1, isNot(equals(encrypted2)));
    });
  });
}
