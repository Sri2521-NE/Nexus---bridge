import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:uuid/uuid.dart';

class ConnectionService extends ChangeNotifier {
  static const String _deviceIdKey = 'nexus_device_id';

  String _timestamp() => DateTime.now().toIso8601String();

  void _traceState(
      String method, String field, Object? previousValue, Object? newValue) {
    debugPrint(
      '[TRACE][ConnectionService] ${_timestamp()} method=$method field=$field previous=$previousValue new=$newValue stack=${StackTrace.current}',
    );
  }

  bool isConnected = false;
  String? deviceId;
  bool _deviceIdReady = false;
  late Future<void> _deviceIdInitialized;

  ConnectionService() {
    _deviceIdInitialized = _initializeDeviceId();
  }

  Future<void> ensureDeviceIdReady() async {
    await _deviceIdInitialized;
  }

  Future<void> _initializeDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      deviceId = prefs.getString(_deviceIdKey);

      if (deviceId == null || deviceId!.isEmpty) {
        // Generate new device ID if not exists
        deviceId = const Uuid().v4();
        await prefs.setString(_deviceIdKey, deviceId!);
        developer.log(
            '[DEVICE] Generated new device ID: ${deviceId!.substring(0, 8)}...');
      } else {
        developer.log(
            '[DEVICE] Loaded persisted device ID: ${deviceId!.substring(0, 8)}...');
      }
      _deviceIdReady = true;
      notifyListeners();
    } catch (e) {
      developer.log('[DEVICE] Error initializing device ID: $e');
      // Fallback: generate a temporary ID
      deviceId = const Uuid().v4();
      _deviceIdReady = true;
    }
  }

  Future<bool> connect(String serverUrl, {bool saveForLater = true}) async {
    // In offline mode, nearby workspace join is local only.
    _traceState('connect', 'isConnected', isConnected, true);
    isConnected = true;
    notifyListeners();
    return true;
  }

  Future<void> tryAutoReconnect() async {
    await _deviceIdInitialized;
    notifyListeners();
  }

  Future<bool> loadSavedSessionToken() async {
    return false;
  }

  Future<bool> login(String username, String password) async {
    return false;
  }

  Future<void> disconnect() async {
    _traceState('disconnect', 'isConnected', isConnected, false);
    isConnected = false;
    notifyListeners();
  }

  Future<void> waitForDeviceId() async {
    if (!_deviceIdReady) {
      await _deviceIdInitialized;
    }
  }

  Future<void> setDeviceId(String id) async {
    if (id.isEmpty) return;
    deviceId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceIdKey, id);
    _deviceIdReady = true;
    developer.log('[DEVICE] Synced device ID: ${id.substring(0, 8)}...');
    notifyListeners();
  }
}
