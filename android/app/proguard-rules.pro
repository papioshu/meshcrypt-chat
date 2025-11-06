# Add project specific ProGuard/R8 rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# Add any project specific keep options here:

# Flutter specific rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Flutter encryption and security libraries
-keep class flutter_secure_storage.** { *; }
-keep class cryptography.** { *; }

# Bluetooth LE and connectivity
-keep class flutter_blue_plus.** { *; }
-keep class connectivity_plus.** { *; }

# Encrypted database (SQLCipher)
-keep class sqflite_sqlcipher.** { *; }

# Encryption and cryptography
-keep class com.example.encrypted_mesh_chat.** { *; }
-keep class org.example.encrypted_mesh_chat.** { *; }

# QR code libraries
-keep class qr_flutter.** { *; }
-keep class qr_code_scanner.** { *; }

# File operations
-keep class file_picker.** { *; }
-keep class share_plus.** { *; }

# State management
-keep class provider.** { *; }

# UUID generation
-keep class uuid.** { *; }
-keep class com.google.gson.** { *; }

# Keep model classes
-keep class * extends java.io.Serializable { *; }
-keep class * implements android.os.Parcelable { *; }

# Keep Flutter engine classes
-keep class * extends io.flutter.embedding.android.FlutterActivity { *; }
-keep class * extends io.flutter.embedding.android.FlutterFragmentActivity { *; }
-keep class * extends io.flutter.embedding.android.FlutterApplication { *; }

# Enable aggressive optimizations for release builds
-optimizations !code/simplification/arithmetic,!code/simplification/cast,!field/*,!class/merging/*
-optimizationpasses 5
-allowaccessmodification

# Remove logging in release builds
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int i(...);
    public static int w(...);
    public static int d(...);
    public static int e(...);
}

# Keep Flutter plugin classes that might be accessed via reflection
-keep class * {
    @androidx.annotation.Keep *;
}

# F-Droid specific optimizations
-dontwarn java.lang.instrument.ClassFileTransformer
-dontwarn sun.misc.SignalHandler
-dontwarn java.lang.instrument.Instrumentation
-dontwarn sun.misc.Signal