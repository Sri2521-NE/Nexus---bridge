import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class DiscoveredServer {
  final String name;
  final String ip;
  final int port;
  final String deviceId;

  DiscoveredServer({
    required this.name,
    required this.ip,
    required this.port,
    required this.deviceId,
  });

  String get url => 'http://$ip:$port';
}

class DiscoveryService extends ChangeNotifier {
  static const List<int> discoveryPorts = [37020, 37021];
  static const String discoveryMessage = 'NEXUS_DISCOVER';

  List<DiscoveredServer> discoveredServers = [];
  bool isDiscovering = false;
  RawDatagramSocket? _socket;

  // Deduplication map: tracks recently received responses to prevent duplicates
  // Key: "IP:PORT", Value: timestamp of last response
  final Map<String, int> _recentResponses = {};
  static const int dedupWindowMs = 2000; // 2 second deduplication window

  Future<void> startDiscovery() async {
    if (isDiscovering) return;

    isDiscovering = true;
    discoveredServers.clear();
    _recentResponses.clear(); // Clear deduplication cache
    notifyListeners();

    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final status = await Permission.locationWhenInUse.request();
        if (!status.isGranted) {
          developer.log(
              '[DISCOVERY] Location permission denied - discovery may not work');
        }
      }

      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _socket?.broadcastEnabled = true;

      developer.log('[DISCOVERY] Socket bound to port: ${_socket?.port}');

      _socket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket?.receive();
          if (datagram != null) {
            final response = utf8.decode(datagram.data);
            developer.log(
                '[DISCOVERY] Received: "$response" from ${datagram.address.address}:${datagram.port}');
            _parseResponse(response, datagram.address.address);
          }
        }
      });

      final discoveryBytes = utf8.encode(discoveryMessage);
      final broadcastTargets = <InternetAddress>[];

      // Add common broadcast addresses
      broadcastTargets.addAll([
        InternetAddress('255.255.255.255'), // Global broadcast
        InternetAddress('192.168.1.255'), // Common subnet
        InternetAddress('192.168.0.255'), // Common subnet
        InternetAddress('10.0.0.255'), // Common subnet
        InternetAddress('172.16.255.255'), // Common subnet
      ]);

      try {
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLoopback: false,
        );

        developer
            .log('[DISCOVERY] Found ${interfaces.length} network interfaces');

        for (final iface in interfaces) {
          developer.log('[DISCOVERY] Interface: ${iface.name}');
          for (final addr in iface.addresses) {
            developer.log('[DISCOVERY]   Address: ${addr.address}');
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              final first = int.tryParse(parts[0]) ?? 0;
              final second = int.tryParse(parts[1]) ?? 0;
              if (first == 10 ||
                  (first == 192 && second == 168) ||
                  (first == 172 && second >= 16 && second <= 31)) {
                final broadcast =
                    InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255');
                if (!broadcastTargets
                    .any((target) => target.address == broadcast.address)) {
                  broadcastTargets.add(broadcast);
                  developer.log(
                      '[DISCOVERY]   Added broadcast: ${broadcast.address}');
                }
              }
            }
          }
        }
      } catch (e) {
        developer.log('[DISCOVERY] Could not enumerate network interfaces: $e');
      }

      developer.log(
          '[DISCOVERY] Broadcast targets: ${broadcastTargets.map((target) => target.address).join(', ')}');

      // Send discovery packets multiple times to each target
      for (int attempt = 0; attempt < 3; attempt++) {
        developer.log('[DISCOVERY] Attempt ${attempt + 1}/3');
        for (final target in broadcastTargets) {
          for (final port in discoveryPorts) {
            try {
              _socket?.send(discoveryBytes, target, port);
              developer.log('[DISCOVERY] Sent to ${target.address}:$port');
              await Future.delayed(const Duration(milliseconds: 100));
            } catch (e) {
              developer.log(
                  '[DISCOVERY] Failed to send to ${target.address}:$port: $e');
            }
          }
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Wait for responses
      developer.log('[DISCOVERY] Waiting for responses...');
      await Future.delayed(const Duration(seconds: 5));

      _socket?.close();
      _socket = null;

      isDiscovering = false;
      notifyListeners();

      developer.log(
          '[DISCOVERY] Discovery complete. Found ${discoveredServers.length} servers');
    } catch (e) {
      developer.log('[DISCOVERY] Error during discovery: $e');
      isDiscovering = false;
      notifyListeners();
    }
  }

  void _parseResponse(String response, String senderIp) {
    // Expected format: NEXUS_BRIDGE:IP:PORT
    response = response.trim();
    if (response.startsWith('NEXUS_BRIDGE:')) {
      final parts = response.split(':');
      if (parts.length >= 3) {
        final ip = parts[1].trim();
        final port = int.tryParse(parts[2].trim());
        if (port != null && ip.isNotEmpty) {
          final serverKey = '$ip:$port';
          final now = DateTime.now().millisecondsSinceEpoch;

          // Check if this response was recently received (within dedup window)
          final lastResponseTime = _recentResponses[serverKey];
          if (lastResponseTime != null &&
              (now - lastResponseTime) < dedupWindowMs) {
            developer.log(
                '[DISCOVERY] Duplicate response ignored: $serverKey (received ${now - lastResponseTime}ms ago)');
            return;
          }

          // Update the last response time
          _recentResponses[serverKey] = now;

          // Clean up old entries (older than 10 seconds)
          _recentResponses.removeWhere((key, time) => (now - time) > 10000);

          addServer(DiscoveredServer(
            name: 'Nexus Bridge',
            ip: ip,
            port: port,
            deviceId: 'discovered',
          ));
        }
      }
    }
  }

  void addServer(DiscoveredServer server) {
    // Check if server already exists
    if (!discoveredServers.any(
      (s) => s.ip == server.ip && s.port == server.port,
    )) {
      discoveredServers.add(server);
      notifyListeners();
    }
  }

  void clearServers() {
    discoveredServers.clear();
    notifyListeners();
  }
}
