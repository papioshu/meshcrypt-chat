import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:crypto/crypto.dart';

/// Encryption service providing X25519 keypair generation, shared secret derivation,
/// AES256-GCM encryption/decryption, secure key storage, and QR code generation
class EncryptionService {
  static const String _privateKeyKey = 'x25519_private_key';
  static const String _publicKeyKey = 'x25519_public_key';
  
  static const int _nonceLength = 12; // 96 bits for AES-GCM
  static const int _tagLength = 16; // 128 bits for AES-GCM
  
  final FlutterSecureStorage _secureStorage;
  final X25519 _x25519 = X25519();
  final AesGcm _aesGcm = AesGcm.with256bits();
  final Hkdf _hkdf = Hkdf(Sha256());

  EncryptionService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// Initialize the service and ensure keys are generated
  Future<void> initialize() async {
    final hasPrivateKey = await _secureStorage.containsKey(key: _privateKeyKey);
    final hasPublicKey = await _secureStorage.containsKey(key: _publicKeyKey);

    if (!hasPrivateKey || !hasPublicKey) {
      await generateKeyPair();
    }
  }

  /// Generate a new X25519 keypair and store it securely
  Future<KeyPair> generateKeyPair() async {
    final keyPair = await _x25519.newKeyPair();
    
    // Convert to list for storage
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
    final publicKeyBytes = await keyPair.extractPublicKey();
    
    // Store securely
    await _secureStorage.write(
      key: _privateKeyKey,
      value: base64Encode(privateKeyBytes),
    );
    
    await _secureStorage.write(
      key: _publicKeyKey,
      value: base64Encode(publicKeyBytes),
    );
    
    return keyPair;
  }

  /// Get the stored public key
  Future<Uint8List> getPublicKey() async {
    final publicKeyBase64 = await _secureStorage.read(key: _publicKeyKey);
    
    if (publicKeyBase64 == null) {
      throw Exception('Public key not found. Call generateKeyPair() first.');
    }
    
    return base64Decode(publicKeyBase64);
  }

  /// Get the stored private key
  Future<Uint8List> getPrivateKey() async {
    final privateKeyBase64 = await _secureStorage.read(key: _privateKeyKey);
    
    if (privateKeyBase64 == null) {
      throw Exception('Private key not found. Call generateKeyPair() first.');
    }
    
    return base64Decode(privateKeyBase64);
  }

  /// Derive shared secret from own private key and peer's public key
  Future<Uint8List> deriveSharedSecret(Uint8List peerPublicKey) async {
    final privateKeyBytes = await getPrivateKey();
    
    // Reconstruct the key pair
    final keyPair = SimpleKeyPairData(
      privateKeyBytes,
      publicKey: SimplePublicKey(
        peerPublicKey,
        type: KeyPairType.x25519,
      ),
      type: KeyPairType.x25519,
    );
    
    // Perform key agreement
    final sharedSecret = await _x25519.sharedSecret(
      keyPair: keyPair,
      peerPublicKey: SimplePublicKey(
        peerPublicKey,
        type: KeyPairType.x25519,
      ),
    );
    
    return sharedSecret.bytes;
  }

  /// Derive AES-256-GCM key from shared secret using HKDF
  Future<SecretKey> deriveAesKey(Uint8List sharedSecret) async {
    const salt = 'mesh_chat_salt'; // Context-specific salt
    const info = 'encryption_key'; // Derivation context
    
    final derivedKey = await _hkdf.deriveKey(
      secretKey: SecretKey(sharedSecret),
      outputLength: 32, // 256 bits
      salt: utf8.encode(salt),
      info: utf8.encode(info),
    );
    
    return derivedKey;
  }

  /// Generate a random nonce for AES-GCM
  Uint8List generateNonce() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(_nonceLength, (_) => random.nextInt(256)),
    );
  }

  /// Encrypt data using AES-256-GCM
  /// Returns formatted string: base64(nonce || ciphertext || tag)
  Future<String> encrypt(Uint8List data, Uint8List sharedSecret) async {
    // Derive AES key from shared secret
    final aesKey = await deriveAesKey(sharedSecret);
    
    // Generate fresh nonce
    final nonce = generateNonce();
    
    // Create AAD (e.g., timestamp or additional context)
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final aad = utf8.encode('mesh_chat_$timestamp');
    
    // Encrypt the data
    final secretBox = await _aesGcm.encrypt(
      data,
      secretKey: aesKey,
      nonce: nonce,
      aad: aad,
    );
    
    // Pack nonce || ciphertext || tag
    final packed = Uint8List(nonce.length + secretBox.cipherText.length + secretBox.mac.bytes.length);
    packed.setAll(0, nonce);
    packed.setAll(nonce.length, secretBox.cipherText);
    packed.setAll(nonce.length + secretBox.cipherText.length, secretBox.mac.bytes);
    
    // Return base64 encoded string
    return base64Encode(packed);
  }

  /// Decrypt data using AES-256-GCM
  /// Expects formatted string: base64(nonce || ciphertext || tag)
  Future<Uint8List> decrypt(String encryptedData, Uint8List sharedSecret) async {
    // Decode from base64
    final packed = base64Decode(encryptedData);
    
    // Extract components
    final nonce = packed.sublist(0, _nonceLength);
    final tag = packed.sublist(packed.length - _tagLength);
    final ciphertext = packed.sublist(_nonceLength, packed.length - _tagLength);
    
    // Reconstruct SecretBox
    final secretBox = SecretBox(
      ciphertext,
      nonce: nonce,
      mac: Mac(tag),
    );
    
    // Derive AES key from shared secret
    final aesKey = await deriveAesKey(sharedSecret);
    
    // Create AAD (same as used for encryption)
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final aad = utf8.encode('mesh_chat_$timestamp');
    
    // Decrypt
    try {
      final result = await _aesGcm.decrypt(
        secretBox,
        secretKey: aesKey,
        aad: aad,
      );
      return result;
    } catch (e) {
      throw Exception('Decryption failed. Data may be corrupted or tampered.');
    }
  }

  /// Generate QR code for public key sharing
  /// Returns encoded image data for QR code display
  Future<Uint8List> generatePublicKeyQrCode() async {
    final publicKey = await getPublicKey();
    
    // Create QR code data (format: MESH_PUBLIC_KEY:<base64_public_key>)
    final qrData = 'MESH_PUBLIC_KEY:${base64Encode(publicKey)}';
    
    // Generate QR code using QrPainter
    final painter = QrPainter(
      data: qrData,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.high,
      gapless: false,
      color: const Color(0xFF000000),
      emptyColor: const Color(0xFFFFFFFF),
    );
    
    // Convert to image
    final image = await painter.toImage(256);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Get QR code data string (useful for debugging)
  Future<String> getPublicKeyQrString() async {
    final publicKey = await getPublicKey();
    return 'MESH_PUBLIC_KEY:${base64Encode(publicKey)}';
  }

  /// Parse public key from QR code data string
  /// Returns the public key bytes if valid, throws exception otherwise
  static Uint8List parsePublicKeyFromQr(String qrData) {
    if (!qrData.startsWith('MESH_PUBLIC_KEY:')) {
      throw Exception('Invalid QR code format. Expected MESH_PUBLIC_KEY: prefix.');
    }
    
    final publicKeyBase64 = qrData.substring('MESH_PUBLIC_KEY:'.length);
    
    if (publicKeyBase64.isEmpty) {
      throw Exception('Public key data is empty.');
    }
    
    try {
      return base64Decode(publicKeyBase64);
    } catch (e) {
      throw Exception('Invalid base64 encoding in public key.');
    }
  }

  /// Generate a fingerprint (hash) of the public key for verification
  Future<String> getPublicKeyFingerprint() async {
    final publicKey = await getPublicKey();
    
    // Use SHA-256 to create a fingerprint
    final digest = sha256.convert(publicKey.bytes);
    
    // Convert to hex string for easy reading
    return digest.toString();
  }

  /// Rotate keys by generating a new keypair
  Future<void> rotateKeys() async {
    await generateKeyPair();
  }

  /// Delete all stored keys (use with caution)
  Future<void> deleteKeys() async {
    await _secureStorage.delete(key: _privateKeyKey);
    await _secureStorage.delete(key: _publicKeyKey);
  }

  /// Check if keys exist
  Future<bool> hasKeys() async {
    return await _secureStorage.containsKey(key: _privateKeyKey) &&
           await _secureStorage.containsKey(key: _publicKeyKey);
  }
}

/// Extension to convert Uint8List to List<int> for compatibility
extension Uint8ListExtension on Uint8List {
  List<int> get bytes => this;
}
