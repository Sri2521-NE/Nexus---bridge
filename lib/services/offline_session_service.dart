import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionMemberState {
  SessionMemberState({
    required this.deviceId,
    required this.name,
    required this.role,
    required this.connected,
    required this.lastSeenAt,
  });

  final String deviceId;
  final String name;
  final String role;
  bool connected;
  DateTime lastSeenAt;

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'name': name,
        'role': role,
        'connected': connected,
        'lastSeenAt': lastSeenAt.toIso8601String(),
      };

  factory SessionMemberState.fromJson(Map<String, dynamic> map) =>
      SessionMemberState(
        deviceId: map['deviceId']?.toString() ?? '',
        name: map['name']?.toString() ?? 'Member',
        role: map['role']?.toString() ?? 'contributor',
        connected: map['connected'] == true,
        lastSeenAt: DateTime.tryParse(map['lastSeenAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}

class OfflineSessionService extends ChangeNotifier {
  static const String _prefKey = 'offline_session_service_state';

  String _timestamp() => DateTime.now().toIso8601String();

  void _traceState(
      String method, String field, Object? previousValue, Object? newValue) {
    debugPrint(
      '[TRACE][OfflineSessionService] ${_timestamp()} method=$method field=$field previous=$previousValue new=$newValue stack=${StackTrace.current}',
    );
  }

  bool _isDispatching = false;
  bool _pendingNotification = false;

  bool sessionActive = false;
  String workspaceId = '';
  String workspaceName = '';
  String ownerName = '';
  String ownerDeviceId = '';
  String localDeviceId = '';
  String sessionRole = 'viewer';
  String connectionState = 'disconnected';
  String hostStatus = 'offline';
  bool discoveryActive = false;
  bool advertisingActive = false;
  int retryAttempts = 0;
  int heartbeatFailures = 0;
  DateTime? lastHeartbeatAt;
  DateTime? lastSyncAt;
  String lastError = '';
  final Map<String, SessionMemberState> members = {};
  final List<String> logs = [];

  Future<void> load() async {
    debugPrint(
      '[TRACE][OfflineSessionService] ${_timestamp()} method=load field=sessionActive previous=$sessionActive new=$sessionActive stack=${StackTrace.current}',
    );
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null || raw.isEmpty) {
      _scheduleNotification();
      return;
    }

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      sessionActive = decoded['sessionActive'] == true;
      workspaceId = decoded['workspaceId']?.toString() ?? '';
      workspaceName = decoded['workspaceName']?.toString() ?? '';
      ownerName = decoded['ownerName']?.toString() ?? '';
      ownerDeviceId = decoded['ownerDeviceId']?.toString() ?? '';
      localDeviceId = decoded['localDeviceId']?.toString() ?? '';
      sessionRole = decoded['sessionRole']?.toString() ?? 'viewer';
      connectionState =
          decoded['connectionState']?.toString() ?? 'disconnected';
      hostStatus = decoded['hostStatus']?.toString() ?? 'offline';
      discoveryActive = decoded['discoveryActive'] == true;
      advertisingActive = decoded['advertisingActive'] == true;
      retryAttempts =
          int.tryParse(decoded['retryAttempts']?.toString() ?? '0') ?? 0;
      heartbeatFailures =
          int.tryParse(decoded['heartbeatFailures']?.toString() ?? '0') ?? 0;
      lastHeartbeatAt =
          DateTime.tryParse(decoded['lastHeartbeatAt']?.toString() ?? '');
      lastSyncAt = DateTime.tryParse(decoded['lastSyncAt']?.toString() ?? '');
      lastError = decoded['lastError']?.toString() ?? '';
      members.clear();
      final memberMaps = decoded['members'] as List<dynamic>? ?? const [];
      for (final memberMap in memberMaps) {
        if (memberMap is Map<String, dynamic>) {
          final member = SessionMemberState.fromJson(memberMap);
          members[member.deviceId] = member;
        }
      }
      final logList = decoded['logs'] as List<dynamic>? ?? const [];
      logs
        ..clear()
        ..addAll(logList.map((entry) => entry.toString()).toList());
    } catch (e) {
      debugPrint('OfflineSessionService load failed: $e');
    }

    _scheduleNotification();
  }

  Future<void> save() async {
    debugPrint(
      '[TRACE][OfflineSessionService] ${_timestamp()} method=save field=sessionActive previous=$sessionActive new=$sessionActive stack=${StackTrace.current}',
    );
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'sessionActive': sessionActive,
      'workspaceId': workspaceId,
      'workspaceName': workspaceName,
      'ownerName': ownerName,
      'ownerDeviceId': ownerDeviceId,
      'localDeviceId': localDeviceId,
      'sessionRole': sessionRole,
      'connectionState': connectionState,
      'hostStatus': hostStatus,
      'discoveryActive': discoveryActive,
      'advertisingActive': advertisingActive,
      'retryAttempts': retryAttempts,
      'heartbeatFailures': heartbeatFailures,
      'lastHeartbeatAt': lastHeartbeatAt?.toIso8601String(),
      'lastSyncAt': lastSyncAt?.toIso8601String(),
      'lastError': lastError,
      'members': members.values.map((member) => member.toJson()).toList(),
      'logs': logs.take(100).toList(),
    };
    await prefs.setString(_prefKey, jsonEncode(payload));
    _scheduleNotification();
  }

  void setLocalDeviceId(String deviceId) {
    localDeviceId = deviceId;
    recordEvent('Device id registered');
    save();
  }

  void setDiscoveryActive(bool active) {
    debugPrint(
        '[DEBUG_LOG] DISCOVERY ${active ? 'STARTED' : 'STOPPED'} (OfflineSessionService)');
    discoveryActive = active;
    recordEvent(active ? 'Discovery started' : 'Discovery stopped');
    save();
  }

  void setAdvertisingActive(bool active) {
    debugPrint(
        '[DEBUG_LOG] ADVERTISING ${active ? 'STARTED' : 'STOPPED'} (OfflineSessionService)');
    advertisingActive = active;
    recordEvent(active ? 'Advertising started' : 'Advertising stopped');
    save();
  }

  void beginHostSession({
    required String workspaceId,
    required String workspaceName,
    required String ownerName,
    required String ownerDeviceId,
  }) {
    _traceState('beginHostSession', 'sessionActive', sessionActive, true);
    _traceState('beginHostSession', 'workspaceId', workspaceId, workspaceId);
    this.workspaceId = workspaceId;
    this.workspaceName = workspaceName;
    this.ownerName = ownerName;
    this.ownerDeviceId = ownerDeviceId;
    sessionActive = true;
    sessionRole = 'owner';
    connectionState = 'connected';
    hostStatus = 'online';
    heartbeatFailures = 0;
    lastSyncAt = DateTime.now();
    registerMember(
      deviceId: ownerDeviceId,
      name: ownerName,
      role: 'owner',
      connected: true,
    );
    debugPrint(
        '[DEBUG_LOG] SESSION_ACTIVE_TRUE (host) workspaceId=$workspaceId');
    recordEvent('Session created');
    save();
  }

  void beginClientSession({
    required String workspaceId,
    required String workspaceName,
    required String ownerName,
    required String ownerDeviceId,
  }) {
    _traceState('beginClientSession', 'sessionActive', sessionActive, true);
    _traceState('beginClientSession', 'workspaceId', workspaceId, workspaceId);
    this.workspaceId = workspaceId;
    this.workspaceName = workspaceName;
    this.ownerName = ownerName;
    this.ownerDeviceId = ownerDeviceId;
    sessionActive = true;
    sessionRole = 'contributor';
    connectionState = 'connected';
    hostStatus = 'online';
    heartbeatFailures = 0;
    lastSyncAt = DateTime.now();
    registerMember(
      deviceId: ownerDeviceId,
      name: ownerName,
      role: 'owner',
      connected: true,
    );
    debugPrint(
        '[DEBUG_LOG] SESSION_ACTIVE_TRUE (client) workspaceId=$workspaceId');
    recordEvent('Client session joined');
    save();
  }

  void registerMember({
    required String deviceId,
    required String name,
    required String role,
    bool connected = true,
  }) {
    if (deviceId.isEmpty) return;
    members[deviceId] = SessionMemberState(
      deviceId: deviceId,
      name: name,
      role: role,
      connected: connected,
      lastSeenAt: DateTime.now(),
    );
    lastSyncAt = DateTime.now();
    save();
  }

  void markMemberDisconnected(String deviceId) {
    final member = members[deviceId];
    if (member == null) return;
    member.connected = false;
    member.lastSeenAt = DateTime.now();
    save();
  }

  void markHeartbeatReceived({required String from}) {
    if (from.isNotEmpty) {
      final existing = members[from];
      if (existing != null) {
        existing.connected = true;
        existing.lastSeenAt = DateTime.now();
      }
    }
    lastHeartbeatAt = DateTime.now();
    heartbeatFailures = 0;
    hostStatus = 'online';
    connectionState = 'connected';
    lastSyncAt = DateTime.now();
    recordEvent('Heartbeat received');
    save();
  }

  void markHeartbeatLost() {
    heartbeatFailures += 1;
    if (heartbeatFailures >= 3) {
      hostStatus = 'offline';
      connectionState = 'reconnecting';
      recordEvent('Heartbeat lost');
    }
    save();
  }

  void recordError(String message) {
    lastError = message;
    recordEvent(message);
    save();
  }

  void endSession() {
    _traceState('endSession', 'sessionActive', sessionActive, false);
    stopSession();
    recordEvent('Session ended');
    save();
  }

  void stopSession() {
    _traceState('stopSession', 'sessionActive', sessionActive, false);
    if (!sessionActive) return;
    sessionActive = false;
    connectionState = 'disconnected';
    hostStatus = 'offline';
    heartbeatFailures = 0;
    lastHeartbeatAt = null;
    lastSyncAt = null;
    lastError = '';
    members.clear();
  }

  void recordEvent(String message) {
    final stamp = DateTime.now().toIso8601String();
    logs.add('$stamp $message');
    if (logs.length > 80) {
      logs.removeRange(0, logs.length - 80);
    }
    _scheduleNotification();
  }

  void clearSession() {
    _traceState('clearSession', 'sessionActive', sessionActive, false);
    if (!sessionActive) return;
    debugPrint(
        '[DEBUG_LOG] WORKSPACE_CLEARED (OfflineSessionService) workspaceId=$workspaceId');
    sessionActive = false;
    connectionState = 'disconnected';
    hostStatus = 'offline';
    heartbeatFailures = 0;
    lastHeartbeatAt = null;
    lastSyncAt = null;
    lastError = '';
    members.clear();
    logs.clear();
    recordEvent('Session cleared');
    save();
  }

  void _scheduleNotification() {
    if (_isDispatching) {
      _pendingNotification = true;
      return;
    }

    _isDispatching = true;
    unawaited(Future<void>.delayed(Duration.zero, () {
      if (!hasListeners) {
        _isDispatching = false;
        _pendingNotification = false;
        return;
      }

      _isDispatching = false;
      if (_pendingNotification) {
        _pendingNotification = false;
      }
      notifyListeners();
    }));
  }
}
