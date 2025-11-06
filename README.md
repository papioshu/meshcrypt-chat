# MeshCrypt Chat

**MeshCrypt Chat** is a privacy-first, encrypted mesh messaging app designed for offline and decentralized communication. It uses LoRa mesh, BLE, and libp2p-style routing to deliver secure messages without relying on centralized servers or cloud infrastructure.

---

## 🔐 Features

- End-to-end encryption using Curve25519 + AES256-GCM (libsodium)
- Peer-to-peer messaging over BLE, LoRa, and libp2p
- Offline-capable with local encrypted storage
- Terminal-style UI with blinking cursor and monospaced font
- Modular transport layer with fallback routing
- Fully open-source and F-Droid compliant

---

## 📦 Platforms

| Platform | Status |
|----------|--------|
| Android  | ✅ `.apk` ready for F-Droid and sideloading |
| Windows  | ✅ `.exe` build available |
| macOS    | 🔜 Planned |
| Linux    | 🔜 Planned |
| iOS      | 🔜 Pending Apple Developer license |

---

## 🛠️ Build Instructions

### Android
```bash
flutter build apk --release
```

### Windows
```bash
flutter build windows
```

### macOS
```bash
flutter build macos
```

### Linux
```bash
flutter build linux
```

---

## 🏗️ Architecture

### Transport Layer
- **BLE Transport**: Short-range peer discovery and messaging
- **LoRa Transport**: Long-range radio communication via ESP32/LoRa boards
- **LibP2P Transport**: WiFi Direct and mDNS for local mesh networking
- **Transport Manager**: Automatic fallback and optimal transport selection

### Security
- **X25519**: Elliptic curve cryptography for key exchange
- **AES-256-GCM**: Strong symmetric encryption for all messages
- **SQLCipher**: Encrypted local database storage
- **Perfect Forward Secrecy**: Session-specific encryption keys
- **Tor/I2P-style routing**: Untraceable relay communication

### UI Components
- **Terminal Interface**: Command-line inspired design with monospaced fonts
- **Blinking Cursor**: Real-time typing indicators
- **Status Indicators**: Connection and encryption status
- **Message History**: Encrypted chat history with search

---

## 📱 Usage

### Initial Setup
1. Generate your encryption keypair on first launch
2. Share your public key via QR code or manual input
3. Add contacts by scanning their QR codes or exchanging keys
4. Start messaging with end-to-end encryption

### Communication Methods
- **Direct Messaging**: One-on-one encrypted conversations
- **Group Chats**: Multi-party encrypted group communication
- **File Transfer**: Encrypted file sharing with chunked transmission
- **Mesh Routing**: Multi-hop message routing for extended range

### Transport Selection
The app automatically selects the best transport:
1. **Primary**: BLE (short-range, low power)
2. **Secondary**: WiFi Direct (medium-range)
3. **Tertiary**: LoRa (long-range, optional hardware)
4. **Fallback**: Relay routing through mesh network

---

## 🔧 Development

### Prerequisites
- Flutter SDK 3.10.0 or higher
- Android Studio / VS Code
- F-Droid compatible environment

### Setup
```bash
cd flutter_app
flutter pub get
flutter run
```

### Testing
```bash
flutter test
flutter build apk --debug  # For testing builds
```

---

## 📚 Documentation

### Technical Documentation
- **[Security Architecture](docs/security_architecture.md)**: Detailed encryption implementation
- **[Transport Protocols](docs/transport_protocols.md)**: BLE, LoRa, and libp2p specifications
- **[API Reference](docs/api_reference.md)**: Complete API documentation
- **[F-Droid Deployment](docs/fdroid_deployment.md)**: Distribution guidelines

### User Guides
- **[Installation Guide](docs/installation.md)**: Platform-specific installation
- **[Getting Started](docs/getting_started.md)**: First-time user guide
- **[Privacy Features](docs/privacy.md)**: Security and privacy capabilities

---

## 🛡️ Security

### Cryptographic Standards
- **Encryption**: AES-256-GCM with 256-bit keys
- **Key Exchange**: X25519 elliptic curve cryptography
- **Hash Functions**: SHA-256 for integrity verification
- **Random Generation**: Cryptographically secure random number generation

### Privacy Protections
- **No Metadata Collection**: Zero tracking or analytics
- **Local Storage Only**: All data stays on your device
- **Obfuscation**: R8 code obfuscation for release builds
- **Memory Protection**: Secure memory handling and cleanup

### Threat Model
- **Surveillance Resistance**: Works offline without internet
- **Traffic Analysis**: Onion routing prevents pattern analysis
- **Device Compromise**: Encrypted storage protects data at rest
- **Man-in-the-Middle**: X25519 prevents message interception

---

## 🤝 Contributing

We welcome contributions from developers committed to privacy and security:

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Commit** your changes (`git commit -m 'Add amazing feature'`)
4. **Push** to the branch (`git push origin feature/amazing-feature`)
5. **Open** a Pull Request

### Development Guidelines
- Follow F-Droid inclusion guidelines
- Maintain GPL-3.0 license compliance
- Add tests for new features
- Document security implications
- Use secure coding practices

---

## 📄 License

```
MeshCrypt Chat
Copyright (c) 2025 Tevin

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.
```

---

## 🌟 Community

- **Issues**: Report bugs and request features
- **Discussions**: Community support and ideas
- **Security**: Responsible disclosure
- **Privacy**: Always consider user privacy first

---

**Built with ❤️ for privacy-conscious users worldwide**

*Your conversations, your data, your privacy - protected by design.*