import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class NearbyService {
  static const MethodChannel _channel = MethodChannel('com.nexusbridge/nearby');

  final StreamController<Map<String, dynamic>> _joinRequests =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _joinResponses =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _endpointFound =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _endpointLost =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _discoveryStateController =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _advertisingStateController =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _controlMessages =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _uploadProgressController =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _payloadBytes =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _payloadUpdates =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _fileListController =
      StreamController.broadcast();

  NearbyService() {
    debugPrint('[DEBUG_LOG] NEARBY_SERVICE_CREATED');
    _channel.setMethodCallHandler(_platformCallHandler);
  }

  Stream<Map<String, dynamic>> get onJoinRequest => _joinRequests.stream;
  Stream<Map<String, dynamic>> get onJoinResponse => _joinResponses.stream;
  Stream<Map<String, dynamic>> get onEndpointFound => _endpointFound.stream;
  Stream<Map<String, dynamic>> get onEndpointLost => _endpointLost.stream;
  Stream<Map<String, dynamic>> get onDiscoveryState =>
      _discoveryStateController.stream;
  Stream<Map<String, dynamic>> get onAdvertisingState =>
      _advertisingStateController.stream;
  Stream<Map<String, dynamic>> get onControlMessage => _controlMessages.stream;
  Stream<Map<String, dynamic>> get onUploadProgress =>
      _uploadProgressController.stream;
  Stream<Map<String, dynamic>> get onPayloadBytes => _payloadBytes.stream;
  Stream<Map<String, dynamic>> get onPayloadTransferUpdate =>
      _payloadUpdates.stream;
  Stream<Map<String, dynamic>> get onFileList => _fileListController.stream;

  Future<void> _platformCallHandler(MethodCall call) async {
    final args = call.arguments as Map<dynamic, dynamic>?;
    final payload = args != null
        ? Map<String, dynamic>.from(args.cast<String, dynamic>())
        : <String, dynamic>{};
    debugPrint(
        '[DEBUG_LOG] ANDROID_CALLBACK_RECEIVED: method=${call.method} payload=$payload');

    switch (call.method) {
      case 'onJoinRequest':
        _joinRequests.add(payload);
        break;
      case 'onJoinResponse':
        _joinResponses.add(payload);
        break;
      case 'onControl':
        _controlMessages.add(payload);
        break;
      case 'onEndpointFound':
        debugPrint('[DEBUG_LOG] ENDPOINT_FOUND_NATIVE: payload=$payload');
        _endpointFound.add(payload);
        break;
      case 'onEndpointLost':
        debugPrint('[DEBUG_LOG] ENDPOINT_LOST_NATIVE: payload=$payload');
        _endpointLost.add(payload);
        break;
      case 'onDiscoveryState':
        debugPrint('[DEBUG_LOG] ON_DISCOVERY_STATE_NATIVE: payload=$payload');
        _discoveryStateController.add(payload);
        break;
      case 'onAdvertisingState':
        debugPrint('[DEBUG_LOG] ON_ADVERTISING_STATE_NATIVE: payload=$payload');
        _advertisingStateController.add(payload);
        break;
      case 'onPayloadBytes':
        _payloadBytes.add(payload);
        break;
      case 'onPayloadTransferUpdate':
        _payloadUpdates.add(payload);
        break;
      case 'onFileList':
        _fileListController.add(payload);
        break;
      default:
        break;
    }
  }

  int _androidSdkInt() {
    final version = Platform.operatingSystemVersion.toLowerCase();
    final sdkMatch = RegExp(r'(?:sdk|api)\s*(\d+)').firstMatch(version);
    if (sdkMatch != null) {
      return int.tryParse(sdkMatch.group(1)!) ?? 0;
    }

    final digits = RegExp(r'\d+')
        .allMatches(version)
        .map((match) => int.tryParse(match.group(0)!)!)
        .toList();
    if (digits.isNotEmpty) {
      return digits.length > 1 ? digits.last : digits.first;
    }
    return 0;
  }

  Future<bool> _ensureNearbyPermissions() async {
    if (!Platform.isAndroid) return true;

    final sdkInt = _androidSdkInt();
    final permissions = <Permission>[];

    permissions.add(Permission.locationWhenInUse);
    if (sdkInt < 31) {
      permissions.add(Permission.bluetooth);
    } else {
      permissions.addAll([
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
      ]);
      if (sdkInt >= 33) {
        permissions.add(Permission.nearbyWifiDevices);
      }
    }

    final statuses = await permissions.request();
    debugPrint(
        'Nearby permission statuses: ${statuses.map((k, v) => MapEntry(k.toString(), v)).toString()}');

    final denied = statuses.entries
        .where((entry) => !(entry.value.isGranted || entry.value.isLimited))
        .map((entry) => entry.key.toString())
        .toList();

    if (denied.isNotEmpty) {
      final deniedList = denied.join(', ');
      debugPrint('Nearby permissions denied: $deniedList');
      final permanentlyDenied = statuses.entries.any(
        (entry) => entry.value.isPermanentlyDenied,
      );
      if (permanentlyDenied) {
        openAppSettings();
      }
      return false;
    }

    final bluetoothServiceStatus = await Permission.bluetooth.serviceStatus;
    if (bluetoothServiceStatus != ServiceStatus.enabled) {
      debugPrint('Bluetooth service is not enabled');
      throw PlatformException(
        code: 'BLUETOOTH_DISABLED',
        message: 'Bluetooth service is not enabled',
      );
    }

    return true;
  }

  Future<void> startAdvertising(String communityId, String name) async {
    debugPrint('[Nearby] Starting advertising as: $name');
    if (!await _ensureNearbyPermissions()) {
      throw PlatformException(
        code: 'PERMISSION_DENIED',
        message: 'Nearby permissions not granted',
      );
    }

    debugPrint('[Nearby] Invoking startAdvertising method');
    await _channel.invokeMethod('startAdvertising', {
      'communityId': communityId,
      'name': name,
    });
    debugPrint('[Nearby] startAdvertising completed');
  }

  Future<void> stopAdvertising() async {
    debugPrint('[Nearby] Stopping advertising');
    await _channel.invokeMethod('stopAdvertising');
    debugPrint('[Nearby] stopAdvertising completed');
  }

  Future<void> startDiscovery() async {
    debugPrint('[Nearby] Starting discovery');
    if (!await _ensureNearbyPermissions()) {
      throw PlatformException(
        code: 'PERMISSION_DENIED',
        message: 'Nearby permissions not granted',
      );
    }

    debugPrint('[Nearby] Invoking startDiscovery method');
    await _channel.invokeMethod('startDiscovery');
    debugPrint('[Nearby] startDiscovery completed');
  }

  Future<void> stopDiscovery() async {
    debugPrint('[Nearby] Stopping discovery');
    await _channel.invokeMethod('stopDiscovery');
    debugPrint('[Nearby] stopDiscovery completed');
  }

  Future<void> requestJoin(
      String hostDevice, Map<String, dynamic> payload) async {
    debugPrint('[Nearby] Requesting join from hostDevice: $hostDevice');
    await _channel.invokeMethod('requestJoin', {
      'hostDevice': hostDevice,
      'payload': payload,
      'requested_rights': payload['requested_rights'] ?? ['read']
    });
    debugPrint('[Nearby] requestJoin completed');
  }

  Future<void> respondJoin(
      String targetDevice, Map<String, dynamic> response) async {
    await _channel.invokeMethod('respondJoin', {
      'targetDevice': targetDevice,
      'response': response,
    });
  }

  Future<void> sendControl(String? target, Map<String, dynamic> control) async {
    await _channel.invokeMethod('sendControl', {
      'target': target,
      'control': control,
    });
  }

  Future<void> sendPayload(String? target, List<int> bytes) async {
    await _channel.invokeMethod('sendPayload', {
      'target': target,
      'bytes': bytes,
    });
  }

  Future<void> requestFileList(String hostDevice) async {
    await sendControl(hostDevice, {'type': 'FILE_LIST_REQUEST'});
  }

  Future<void> requestFileChunk(
      String hostDevice, String fileId, int seq) async {
    await sendControl(hostDevice, {
      'type': 'FILE_CHUNK_REQUEST',
      'file_id': fileId,
      'seq': seq,
    });
  }

  Future<void> sendFileChunkRaw(
      String? target, String fileId, int seq, List<int> chunk) async {
    // Build header: idLen(1) + id bytes + seq(4 big-endian) + payload
    final idBytes = fileId.codeUnits;
    final header = <int>[];
    header.add(idBytes.length & 0xff);
    header.addAll(idBytes);
    header.addAll([
      (seq >> 24) & 0xff,
      (seq >> 16) & 0xff,
      (seq >> 8) & 0xff,
      seq & 0xff
    ]);
    final frame = <int>[...header, ...chunk];
    await sendPayload(target, frame);
  }

  static const int chunkSize = 64 * 1024;

  Future<void> sendFileUpload(String hostDevice, String localPath,
      {String? destFileId}) async {
    final file = File(localPath);
    if (!await file.exists()) throw Exception('File not found');
    final fileId = destFileId ?? file.uri.pathSegments.last;
    final size = await file.length();
    // inform host we'll upload and wait for host to be ready
    await sendControl(hostDevice, {
      'type': 'FILE_UPLOAD_REQUEST',
      'file_id': fileId,
      'name': file.uri.pathSegments.last,
      'size': size,
    });

    // wait for FILE_UPLOAD_RESPONSE from host via onControlMessage
    final completer = Completer<bool>();
    StreamSubscription? sub;
    int resumeSeq = 0;
    sub = _controlMessages.stream.listen((evt) {
      try {
        final controlStr = evt['control'] as String?;
        if (controlStr == null) return;
        final obj = jsonDecode(controlStr) as Map<String, dynamic>;
        if (obj['type'] == 'FILE_UPLOAD_RESPONSE' && obj['file_id'] == fileId) {
          if (obj['status'] == 'ok') {
            if (obj.containsKey('resume_seq')) {
              resumeSeq = (obj['resume_seq'] is int)
                  ? obj['resume_seq'] as int
                  : int.tryParse(obj['resume_seq'].toString()) ?? 0;
            }
            completer.complete(true);
          } else {
            completer.complete(false);
          }
        }
      } catch (_) {}
    });

    // fallback timeout
    Future.delayed(const Duration(seconds: 5)).then((_) {
      if (!completer.isCompleted) completer.complete(true);
    });

    final ready = await completer.future;
    await sub.cancel();
    if (!ready) throw Exception('Host rejected upload');

    // stream file and wait for CHUNK_ACK for each chunk (with retries)
    final stream = file.openRead();
    int seq = 0;
    int sentBytes = (resumeSeq * chunkSize);
    await for (final chunk in stream) {
      final bytes = chunk;
      if (seq < resumeSeq) {
        seq += 1;
        continue; // skip already-present chunks on host
      }

      int attempts = 0;
      bool acked = false;
      while (attempts < 6 && !acked) {
        attempts += 1;
        await sendFileChunkRaw(hostDevice, fileId, seq, bytes);
        // optimistic progress update (shows sent bytes even before ack)
        sentBytes += bytes.length;
        try {
          _uploadProgressController
              .add({'file_id': fileId, 'sent_bytes': sentBytes, 'seq': seq});
        } catch (_) {}
        // wait for CHUNK_ACK
        final ackCompleter = Completer<bool>();
        StreamSubscription? ackSub;
        ackSub = _controlMessages.stream.listen((evt) {
          try {
            final controlStr = evt['control'] as String?;
            if (controlStr == null) return;
            final obj = jsonDecode(controlStr) as Map<String, dynamic>;
            final t = obj['type'];
            if (t == 'CHUNK_ACK' &&
                obj['transfer_id'] == fileId &&
                obj['seq'].toString() == seq.toString()) {
              ackCompleter.complete(true);
            } else if (t == 'FILE_UPLOAD_RESULT' &&
                obj['transfer_id'] == fileId) {
              // server finished the upload; treat as ack for last chunk and end
              ackCompleter.complete(true);
            }
          } catch (_) {}
        });
        // timeout for ack with exponential backoff
        final timeoutSec = 6 + (attempts - 1) * 2; // 6s,8s,10s...
        try {
          await ackCompleter.future.timeout(Duration(seconds: timeoutSec));
          acked = true;
        } catch (_) {
          // retry with backoff
          acked = false;
          final backoffMs = 500 * (1 << (attempts - 1));
          await Future.delayed(
              Duration(milliseconds: math.min(backoffMs, 8000)));
        }
        await ackSub.cancel();
      }
      if (!acked) throw Exception('Chunk $seq not ACKed');
      seq += 1;
      await Future.delayed(const Duration(milliseconds: 25));
    }
  }

  // Helper: parse JSON-like string into Map
  Map<String, dynamic>? objFromString(String s) {
    try {
      return Map<String, dynamic>.from(jsonDecode(s) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> openBluetoothSettings() async {
    await _channel.invokeMethod('openBluetoothSettings');
  }
}
