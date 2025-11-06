# F-Droid Release Build Configuration Guide

## Overview
This document provides comprehensive instructions for F-Droid maintainers to build and distribute the Encrypted Mesh Chat application. The application is configured for maximum security and privacy with end-to-end encryption and peer-to-peer mesh networking capabilities.

## Prerequisites
- Android SDK 21+ (target SDK 34)
- Flutter SDK (latest stable version)
- Gradle 7.3+
- Java 8+

## Build Configuration Summary

### Release Build Settings
The application is configured with the following release optimizations:

```gradle
buildTypes {
    release {
        minifyEnabled true          // Enable code shrinking
        shrinkResources true        // Remove unused resources  
        debuggable false            // Disable debugging
        jniDebuggable false         // Disable JNI debugging
        renderscriptDebuggable false // Disable RenderScript debugging
        signingConfig signingConfigs.release
    }
}
```

### Supported Architectures
- **arm64-v8a**: 64-bit ARM (preferred for modern devices)
- **armeabi-v7a**: 32-bit ARM (backward compatibility)

### Application ID and Package Structure
- **F-Droid Build**: `org.example.encrypted_mesh_chat.fdroid`
- **Google Play Build**: `org.example.encrypted_mesh_chat`
- **Current Package**: `com.example.meshchat` (will be updated to final package name)

## F-Droid Signing Process

### Important: Signing Keys
**F-Droid will automatically handle all signing with their own trusted keys.** No developer keys are required or should be included in the build.

### Placeholder Configuration
The project includes placeholder signing configuration in:
- `android/app/build.gradle` - Signing config section
- `android/key.properties` - Placeholder keystore information

### Build Command for F-Droid
```bash
# Navigate to Flutter project root
cd flutter_app

# Build F-Droid release APK
flutter build apk --release --flavor fDroid

# Or build App Bundle for F-Droid (preferred)
flutter build appbundle --release --flavor fDroid
```

### Gradle Build Command (Alternative)
```bash
cd android
./gradlew assembleF_DroidRelease

# Build App Bundle
./gradlew bundleF_DroidRelease
```

## ProGuard/R8 Configuration

### Code Shrinkage Rules
The `android/app/proguard-rules.pro` file includes:
- Flutter engine protection rules
- Encryption library preservation rules
- Mesh networking component protection
- Removal of debug logging in release builds

### Key Features Preserved
- Flutter plugin classes
- Encryption libraries (cryptography, flutter_secure_storage)
- Bluetooth LE components
- Encrypted database (SQLCipher) classes
- QR code functionality
- Model serialization classes

## Application Features and Permissions

### Core Features
1. **End-to-End Encryption**: AES-256-GCM encryption for all messages
2. **Mesh Networking**: Bluetooth Low Energy peer-to-peer communication
3. **LoRa Support**: Long-range radio communication (where available)
4. **Offline Operation**: No internet required for core functionality
5. **Secure Storage**: Encrypted local database using SQLCipher

### Required Permissions
- **Bluetooth LE**: For mesh networking
- **Location**: Required for Bluetooth device discovery
- **Storage**: For encrypted message persistence
- **Camera**: For QR code sharing
- **Vibration**: For message notifications
- **Network**: For updates and optional features

### Privacy Features
- **No Data Collection**: App processes everything locally
- **No Tracking**: Zero analytics or tracking
- **Encrypted Everything**: All data encrypted before storage
- **Offline First**: Works without internet connection
- **Minimal Permissions**: Only essential permissions requested

## Build Optimization Settings

### Gradle Properties (`gradle.properties`)
- **Build Cache**: Enabled for faster subsequent builds
- **Parallel Compilation**: Multi-core utilization
- **Configuration Cache**: Experimental speed improvements
- **R8 Full Mode**: Maximum code shrinking
- **AndroidX**: Modern Android support
- **Minification**: Aggressive code shrinking enabled

### ABI Configuration
```gradle
android {
    defaultConfig {
        ndk {
            abiFilters 'armeabi-v7a', 'arm64-v8a'
        }
    }
}
```

## F-Droid Specific Configuration

### Metadata in AndroidManifest.xml
The app includes comprehensive F-Droid metadata:
- **Category**: Security (appropriate for encrypted messaging)
- **Features**: Offline mesh chat, end-to-end encryption, BLE connectivity
- **License**: GPL-3.0 (open source)
- **Privacy**: No internet required, no data collection
- **Maintainers**: Configurable contact information

### Security Declarations
- **No Internet Required**: App functions completely offline
- **Offline Only**: Designed for local mesh networking
- **Security Focused**: Privacy-first architecture
- **No Backup**: Sensitive data never backed up

## Build Output

### Expected Artifacts
1. **APK**: `build/app/outputs/flutter-apk/app-fDroid-release.apk`
2. **App Bundle**: `build/app/outputs/bundle/fDroidRelease/app-fDroid-release.aab`

### Size Optimization
- **Code Shrinkage**: ~30-50% reduction in code size
- **Resource Shrinkage**: Unused resources removed
- **ProGuard Optimization**: Method inlining and constant folding
- **R8 Optimization**: Aggressive code optimization

## Troubleshooting

### Common Issues
1. **Flutter SDK Not Found**: Set `flutter.sdk` in `local.properties`
2. **Build Cache**: Clear with `./gradlew clean` if build issues occur
3. **ProGuard Errors**: Check `proguard-rules.pro` for missing keep rules
4. **Missing Dependencies**: Run `flutter pub get` before building

### Build Verification
```bash
# Check APK contents
aapt dump badging app-fDroid-release.apk

# Verify signing
jarsigner -verify -verbose app-fDroid-release.apk

# Check ProGuard output
retrace mapping.txt
```

## Security Considerations

### Code Obfuscation
- **R8 Full Mode**: Maximum obfuscation enabled
- **String Encryption**: Sensitive strings preserved
- **Method Hiding**: Internal APIs hidden
- **Resource Obfuscation**: Resource names randomized

### Secure Defaults
- **No Debug Info**: Debug symbols stripped in release
- **No Backup**: Sensitive data never backed up
- **Network Security**: HTTPS-only network traffic
- **Certificate Pinning**: (If network features used)

## Post-Build Steps

1. **Verify APK Size**: Should be optimized for distribution
2. **Test Installation**: Verify app installs and runs correctly
3. **Check Permissions**: Ensure no excessive permissions requested
4. **Validate Signing**: Confirm F-Droid's signature is applied
5. **Security Scan**: Optional security analysis of the APK

## Contact Information

For questions about this build configuration:
- **Repository**: https://github.com/example/meshchat
- **Issues**: https://github.com/example/meshchat/issues
- **Documentation**: See `/docs` folder for detailed technical documentation

## Build Version
- **Configuration Version**: 1.0
- **F-Droid Optimized**: Yes
- **Security Hardened**: Yes
- **Privacy Compliant**: Yes

---

*This configuration is specifically optimized for F-Droid distribution and follows F-Droid's best practices for privacy-focused, open-source applications.*