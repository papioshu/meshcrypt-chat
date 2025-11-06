import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'services/bluetooth_service.dart';
import 'services/encryption_service.dart';
import 'services/database_service.dart';
import 'screens/home_screen.dart';
import 'utils/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Request necessary permissions
  await _requestPermissions();
  
  // Initialize services
  await _initializeServices();
  
  runApp(const EncryptedMeshChatApp());
}

Future<void> _requestPermissions() async {
  // Request Bluetooth permissions
  await [
    Permission.bluetooth,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.bluetoothAdvertise,
    Permission.location,
    Permission.storage,
    Permission.camera,
  ].request();
}

Future<void> _initializeServices() async {
  // Initialize database service
  await DatabaseService.initialize();
  
  // Initialize encryption service
  await EncryptionService.initialize();
  
  // Initialize Bluetooth service
  await BluetoothService.initialize();
}

class EncryptedMeshChatApp extends StatelessWidget {
  const EncryptedMeshChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BluetoothService()),
        Provider(create: (_) => EncryptionService()),
        Provider(create: (_) => DatabaseService()),
      ],
      child: MaterialApp(
        title: 'Encrypted Mesh Chat',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const HomeScreen(),
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.noScaling,
            ),
            child: child!,
          );
        },
      ),
    );
  }
}