import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:typed_data';

class BluetoothService extends ChangeNotifier {
  static BluetoothService? _instance;
  static BluetoothService get instance => _instance!;
  
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  
  bool _isScanning = false;
  bool get isScanning => _isScanning;
  
  List<BluetoothDevice> _discoveredDevices = [];
  List<BluetoothDevice> get discoveredDevices => List.unmodifiable(_discoveredDevices);
  
  List<BluetoothDevice> _connectedDevices = [];
  List<BluetoothDevice> get connectedDevices => List.unmodifiable(_connectedDevices);
  
  static const String SERVICE_UUID = "12345678-1234-5678-9abc-123456789abc";
  static const String CHARACTERISTIC_UUID = "12345678-1234-5678-9abc-123456789def";
  static const int MAX_MESSAGE_SIZE = 180; // MTU considerations
  
  BluetoothService._();
  
  static Future<void> initialize() async {
    if (_instance == null) {
      _instance = BluetoothService._();
    }
    _instance!._isInitialized = true;
  }
  
  Future<bool> checkBluetoothAvailability() async {
    try {
      final isAvailable = await FlutterBluePlus.isSupported;
      return isAvailable;
    } catch (e) {
      debugPrint('Error checking Bluetooth availability: $e');
      return false;
    }
  }
  
  Future<bool> requestBluetoothPermissions() async {
    try {
      final state = await FlutterBluePlus.adapterState.first;
      return state == BluetoothAdapterState.on;
    } catch (e) {
      debugPrint('Error requesting Bluetooth permissions: $e');
      return false;
    }
  }
  
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    if (_isScanning) return;
    
    _isScanning = true;
    notifyListeners();
    
    try {
      FlutterBluePlus.scanResults.listen((results) {
        _discoveredDevices = results.map((r) => r.device).toList();
        notifyListeners();
      });
      
      await FlutterBluePlus.startScan(timeout: timeout);
      
      // Auto stop scanning after timeout
      Future.delayed(timeout, () {
        stopScan();
      });
      
    } catch (e) {
      debugPrint('Error starting scan: $e');
      _isScanning = false;
      notifyListeners();
    }
  }
  
  Future<void> stopScan() async {
    if (!_isScanning) return;
    
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('Error stopping scan: $e');
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }
  
  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect(autoConnect: false);
      
      device.state.listen((state) {
        if (state == BluetoothConnectionState.connected) {
          _connectedDevices.add(device);
        } else if (state == BluetoothConnectionState.disconnected) {
          _connectedDevices.remove(device);
        }
        notifyListeners();
      });
      
      return true;
    } catch (e) {
      debugPrint('Error connecting to device: $e');
      return false;
    }
  }
  
  Future<void> disconnectDevice(BluetoothDevice device) async {
    try {
      await device.disconnect();
      _connectedDevices.remove(device);
      notifyListeners();
    } catch (e) {
      debugPrint('Error disconnecting device: $e');
    }
  }
  
  Future<bool> sendMessage(BluetoothDevice device, String message) async {
    try {
      final services = await device.discoverServices();
      
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.uuid.toString() == CHARACTERISTIC_UUID) {
            final data = Uint8List.fromList(message.codeUnits);
            await characteristic.write(data, withoutResponse: true);
            return true;
          }
        }
      }
      
      return false;
    } catch (e) {
      debugPrint('Error sending message: $e');
      return false;
    }
  }
  
  Future<String?> receiveMessage(BluetoothDevice device) async {
    try {
      final services = await device.discoverServices();
      
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.uuid.toString() == CHARACTERISTIC_UUID) {
            final value = await characteristic.read();
            return String.fromCharCodes(value);
          }
        }
      }
      
      return null;
    } catch (e) {
      debugPrint('Error receiving message: $e');
      return null;
    }
  }
  
  void dispose() {
    FlutterBluePlus.stopScan();
    super.dispose();
  }
}