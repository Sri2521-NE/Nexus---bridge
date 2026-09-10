import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'nearby_service.dart';
import 'offline_session_service.dart';
import 'workspace_service.dart';

class WorkspaceSessionManager extends ChangeNotifier {
  WorkspaceSessionManager({
    required this.nearbyService,
    required this.workspaceService,
    required this.offlineSessionService,
  }) {
    debugPrint('[DEBUG_LOG] SESSION_MANAGER_CREATED');
    workspaceService.addListener(_syncFromWorkspaceService);
    _initStreamListeners();
    _startCleanupTimer();
    debugPrint('[DEBUG_LOG] SESSION_MANAGER_INITIALIZED');
  }

  static const String _prefKey = 'workspace_session_manager_state';
  final NearbyService nearbyService;
  final WorkspaceService workspaceService;
  final OfflineSessionService offlineSessionService;

  String _timestamp() => DateTime.now().toIso8601String();

  void _traceState(
      String method, String field, Object? previousValue, Object? newValue) {
    debugPrint(
      '[TRACE][WorkspaceSessionManager] ${_timestamp()} method=$method field=$field previous=$previousValue new=$newValue stack=${StackTrace.current}',
    );
  }

  WorkspaceModel? currentWorkspace;
  String currentRole = 'viewer';
  String connectedHost = '';
  List<WorkspaceMember> workspaceMembers = const [];
  List<String> permissions = const [];
  List<WorkspaceFolder> sharedFolders = const [];
  List<ResourceItem> sharedResources = const [];
  String connectionState = 'disconnected';
  final Map<String, String> endpointMap = {};
  Timer? _heartbeatTimer;
  Timer? _disconnectTimer;
  DateTime? _lastHeartbeatAt;

  // Persistent P2P Discovery and connection states
  final Map<String, Map<String, dynamic>> nearbyEndpoints = {};
  final Map<String, List<String>> endpointRights = {};
  final Map<String, DateTime> endpointTimestamps = {};
  bool nearbyDiscovering = false;
  bool advertisingNearby = false;
  bool isHostMode = false;
  bool joinRequestPending = false;
  String joinRequestStatus = 'idle';
  final Set<String> _processedApprovalKeys = {};
  bool workspaceSessionActive = false;
  // prevents concurrent executions when multiple approval messages arrive simultaneously
  bool _isActivatingApprovedJoin = false;
  // maps Nearby endpoint ID → persistent app device UUID for member identity
  final Map<String, String> _endpointAppIds = {};
  String? approvalPendingWorkspaceId;
  Completer<Map<String, dynamic>>? snapshotCompleter;
  String? joinedWorkspaceName;
  String joinedWorkspaceType = 'Personal';
  String joinedOwnerName = 'Nearby Host';
  int joinedMembers = 1;
  int joinedResources = 0;
  bool _isApplyingNetworkSync = false;

  // Stream Subscriptions
  StreamSubscription<Map<String, dynamic>>? _endpointFoundSub;
  StreamSubscription<Map<String, dynamic>>? _endpointLostSub;
  StreamSubscription<Map<String, dynamic>>? _joinRequestSub;
  StreamSubscription<Map<String, dynamic>>? _joinResponseSub;
  StreamSubscription<Map<String, dynamic>>? _fileListSub;
  StreamSubscription<Map<String, dynamic>>? _payloadSub;
  StreamSubscription<Map<String, dynamic>>? _controlSub;
  StreamSubscription<Map<String, dynamic>>? _uploadProgressSub;

  // File Transfer State (moved from UI to manager)
  final Map<String, List<int>> downloadBuffers = {};
  final Map<String, int> uploadTotals = {};
  final Map<String, int> uploadAcked = {};
  final Map<String, List<dynamic>> remoteFiles = {};

  // For UI callbacks/events
  final StreamController<String> _uiEventController =
      StreamController<String>.broadcast();
  Stream<String> get uiEvents => _uiEventController.stream;

  Timer? _evictTimer;

  void _initStreamListeners() {
    _endpointFoundSub =
        nearbyService.onEndpointFound.listen(_handleEndpointFound);
    _endpointLostSub = nearbyService.onEndpointLost.listen(_handleEndpointLost);
    _joinRequestSub = nearbyService.onJoinRequest.listen(_handleJoinRequest);
    _joinResponseSub = nearbyService.onJoinResponse.listen(_handleJoinResponse);
    nearbyService.onDiscoveryState.listen(_handleDiscoveryState);
    nearbyService.onAdvertisingState.listen(_handleAdvertisingState);
    _fileListSub = nearbyService.onFileList.listen(_handleFileList);
    _payloadSub = nearbyService.onPayloadBytes.listen(_handlePayloadBytes);
    _controlSub = nearbyService.onControlMessage.listen(_handleControl);
    _uploadProgressSub =
        nearbyService.onUploadProgress.listen(_handleUploadProgress);
    debugPrint('[DEBUG_LOG] LISTENERS_REGISTERED');
  }

  void _handleDiscoveryState(Map<String, dynamic> payload) {
    final running = payload['running'] == true;
    final error = payload['error']?.toString();
    debugPrint(
        '[DISCOVERY_DEBUG] onDiscoveryState: running=$running error=$error');
    nearbyDiscovering = running;
    offlineSessionService.setDiscoveryActive(running);
    if (!running && error != null) {
      offlineSessionService.lastError =
          'Discovery failed: ${payload['error']} ${payload['missingPermissions'] ?? ''}'
              .trim();
      offlineSessionService.save();
    }
    notifyListeners();
  }

  void _handleAdvertisingState(Map<String, dynamic> payload) {
    final running = payload['running'] == true;
    final error = payload['error']?.toString();
    debugPrint(
        '[ADVERTISING_DEBUG] onAdvertisingState: running=$running error=$error');
    advertisingNearby = running;
    offlineSessionService.setAdvertisingActive(running);
    if (!running && error != null) {
      offlineSessionService.lastError =
          'Advertising failed: ${payload['error']}'.trim();
      offlineSessionService.save();
    }
    notifyListeners();
  }

  void _startCleanupTimer() {
    _evictTimer?.cancel();
    _evictTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final now = DateTime.now();
      final expired = endpointTimestamps.entries
          .where((e) => now.difference(e.value).inSeconds > 30)
          .map((e) => e.key)
          .toList();
      if (expired.isNotEmpty) {
        for (final key in expired) {
          nearbyEndpoints.remove(key);
          endpointTimestamps.remove(key);
        }
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _endpointFoundSub?.cancel();
    _endpointLostSub?.cancel();
    _joinRequestSub?.cancel();
    _joinResponseSub?.cancel();
    _fileListSub?.cancel();
    _payloadSub?.cancel();
    _controlSub?.cancel();
    _uploadProgressSub?.cancel();
    _evictTimer?.cancel();
    _uiEventController.close();
    super.dispose();
  }

  void _syncFromWorkspaceService() {
    final serviceWorkspace = workspaceService.activeWorkspace;
    if (serviceWorkspace == null) {
      if (currentWorkspace != null) {
        debugPrint('[STATE] ACTIVE_WORKSPACE_CLEARED');
        return;
      }
      currentWorkspace = null;
      workspaceMembers = const [];
      sharedFolders = const [];
      sharedResources = const [];
      return;
    }

    // If we're currently applying a network sync, avoid suppressing
    // local host-originated broadcasts. Record the flag and use it
    // later when deciding whether to send outbound updates.
    final bool suppressNetworkEcho = _isApplyingNetworkSync;

    // Capture previous counts so we can detect local changes (e.g. new folder)
    // and force an immediate re-broadcast with the updated payload. This
    // helps when createFolder() updates the workspace and we need to ensure
    // the host sends the new folder promptly (avoids races where outgoing
    // payloads appear empty to clients).
    final int previousFoldersCount = sharedFolders.length;
    final int previousResourcesCount = sharedResources.length;

    _traceState('_syncFromWorkspaceService', 'currentWorkspace',
        currentWorkspace?.id ?? 'null', serviceWorkspace.id);
    currentWorkspace = serviceWorkspace;
    workspaceMembers = serviceWorkspace.members;
    sharedFolders = serviceWorkspace.folders;
    sharedResources = serviceWorkspace.resources;

    final bool foldersChanged =
      serviceWorkspace.folders.length != previousFoldersCount;
    final bool resourcesChanged =
      serviceWorkspace.resources.length != previousResourcesCount;
    // ROOT CAUSE FIX (connectedHost corruption): only bootstrap connectedHost from
    // ownerDeviceId when we don't already have a live Nearby transport target set.
    // Previously this ran unconditionally on every workspaceService change (e.g. adding
    // a resource, completing a transfer), overwriting the correct Nearby endpointId
    // (set in _activateApprovedJoin / activateWorkspaceFromPayload) with the host's
    // persistent App UUID (ownerDeviceId), which is NOT a valid Nearby sendControl target.
    // That silently broke the client's heartbeat and its outgoing WORKSPACE_SYNC push
    // a few lines below in this same function.
    if (connectedHost.isEmpty &&
        currentWorkspace != null &&
        currentWorkspace!.id.isNotEmpty) {
      connectedHost = currentWorkspace!.ownerDeviceId;
    }

    // Trigger automatic background synchronization
    if (connectionState == 'connected') {
      final localDeviceId = offlineSessionService.localDeviceId;
      final isLocalHost =
          isHostMode || serviceWorkspace.ownerDeviceId == localDeviceId;
      if (isLocalHost) {
        // Host broadcasts updates to all connected clients.
        // If folders/resources changed locally, always re-broadcast even
        // if we're currently applying a network sync to avoid losing
        // recently-created items.
        if (!suppressNetworkEcho || foldersChanged || resourcesChanged) {
          broadcastWorkspaceSync(
            workspace: serviceWorkspace,
            role: 'owner',
            hostEndpointId: localDeviceId,
            members: serviceWorkspace.members,
            permissions: permissions,
            folders: serviceWorkspace.folders,
            resources: serviceWorkspace.resources,
          );
        } else {
          // suppressed network-driven echo; do not send outbound update
        }
      } else if (connectedHost.isNotEmpty) {
        // Client sends its local update to the host
        // If we're currently applying a network sync, avoid echoing
        // back intermediate network-driven state to the host. Allow
        // client->host sends only when not suppressed.
        if (suppressNetworkEcho) return;
        final payload = {
          'workspaceId': serviceWorkspace.id,
          'workspaceName': serviceWorkspace.name,
          'hostEndpointId': connectedHost,
          'workspaceMembers':
              serviceWorkspace.members.map((m) => m.toJson()).toList(),
          'sharedFolders':
              serviceWorkspace.folders.map((f) => f.toJson()).toList(),
          'sharedResources':
              serviceWorkspace.resources.map((r) => r.toJson()).toList(),
          'announcements':
              serviceWorkspace.announcements.map((a) => a.toJson()).toList(),
          'activityLogs':
              serviceWorkspace.activityLogs.map((a) => a.toJson()).toList(),
          'inboxMessages':
              serviceWorkspace.inboxMessages.map((m) => m.toJson()).toList(),
          'notifications':
              serviceWorkspace.notifications.map((n) => n.toJson()).toList(),
          'transferHistory':
              serviceWorkspace.transferHistory.map((t) => t.toJson()).toList(),
          'workspaceRole': currentRole,
        };
        nearbyService.sendControl(connectedHost, {
          'type': 'WORKSPACE_SYNC',
          ...payload,
        });
      }
    }

    notifyListeners();
  }

  Future<void> load() async {
    debugPrint(
      '[TRACE][WorkspaceSessionManager] ${_timestamp()} method=restoreSession field=currentWorkspace previous=${currentWorkspace?.id ?? 'null'} new=${currentWorkspace?.id ?? 'null'} stack=${StackTrace.current}',
    );
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null || raw.isEmpty) {
      notifyListeners();
      return;
    }

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      currentRole = decoded['currentRole']?.toString() ?? 'viewer';
      connectedHost = decoded['connectedHost']?.toString() ?? '';
      connectionState =
          decoded['connectionState']?.toString() ?? 'disconnected';
      final workspaceId = decoded['workspaceId']?.toString();
      if (workspaceId != null && workspaceId.isNotEmpty) {
        final persistedWorkspace = workspaceService.workspaces.firstWhere(
          (entry) => entry.id == workspaceId,
          orElse: () => WorkspaceModel(
            id: workspaceId,
            name: decoded['workspaceName']?.toString() ?? 'Workspace',
            description: '',
            visibility: 'Local',
            password: '',
            type: 'Connected',
            icon: 'workspaces',
            ownerName: '',
            ownerDeviceId: connectedHost,
            createdAt: DateTime.now().toIso8601String(),
          ),
        );
        _traceState('restoreSession', 'currentWorkspace',
            currentWorkspace?.id ?? 'null', persistedWorkspace.id);
        currentWorkspace = persistedWorkspace;
        workspaceService.refreshActiveWorkspace(persistedWorkspace);
        debugPrint('[STATE] WORKSPACE_RESTORED');
      }
      workspaceMembers =
          List<Map<String, dynamic>>.from(decoded['members'] ?? [])
              .map((entry) => WorkspaceMember(
                    id: entry['id']?.toString() ?? '',
                    name: entry['name']?.toString() ?? 'Member',
                    deviceId: entry['deviceId']?.toString() ?? '',
                    role: WorkspaceRole.values.firstWhere(
                      (role) => role.name == entry['role'],
                      orElse: () => WorkspaceRole.contributor,
                    ),
                  ))
              .toList();
      permissions = List<String>.from(decoded['permissions'] ?? []);
      sharedFolders =
          List<Map<String, dynamic>>.from(decoded['sharedFolders'] ?? [])
              .map(WorkspaceFolder.fromJson)
              .toList();
      sharedResources =
          List<Map<String, dynamic>>.from(decoded['sharedResources'] ?? [])
              .map(ResourceItem.fromJson)
              .toList();

      if (connectionState == 'connected' && connectedHost.isNotEmpty) {
        workspaceSessionActive = true;
        _startHeartbeat();
        tryAutoReconnect();
      }
    } catch (e) {
      debugPrint('WorkspaceSessionManager load failed: $e');
    }

    notifyListeners();
  }

  Future<void> save() async {
    debugPrint(
      '[TRACE][WorkspaceSessionManager] ${_timestamp()} method=save field=currentWorkspace previous=${currentWorkspace?.id ?? 'null'} new=${currentWorkspace?.id ?? 'null'} stack=${StackTrace.current}',
    );
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'workspaceId': currentWorkspace?.id,
      'workspaceName': currentWorkspace?.name,
      'currentRole': currentRole,
      'connectedHost': connectedHost,
      'connectionState': connectionState,
      'members': workspaceMembers
          .map((member) => {
                'id': member.id,
                'name': member.name,
                'deviceId': member.deviceId,
                'role': member.role.name,
              })
          .toList(),
      'permissions': permissions,
      'sharedFolders': sharedFolders.map((folder) => folder.toJson()).toList(),
      'sharedResources':
          sharedResources.map((resource) => resource.toJson()).toList(),
    };
    await prefs.setString(_prefKey, jsonEncode(payload));
    notifyListeners();
  }

  Future<void> clearWorkspaceSessionState() async {
    debugPrint(
      '[TRACE][WorkspaceSessionManager] ${_timestamp()} method=clearWorkspaceSessionState field=currentWorkspace previous=${currentWorkspace?.id ?? 'null'} new=null stack=${StackTrace.current}',
    );
    if (currentWorkspace == null) {
      return;
    }
    currentRole = 'viewer';
    connectedHost = '';
    workspaceMembers = const [];
    permissions = const [];
    sharedFolders = const [];
    sharedResources = const [];
    connectionState = 'disconnected';
    endpointMap.clear();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _disconnectTimer?.cancel();
    _disconnectTimer = null;
    _lastHeartbeatAt = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);

    notifyListeners();
  }

  Future<WorkspaceModel> activateWorkspaceFromPayload(
    Map<String, dynamic> payload, {
    required String endpointId,
    required String localDeviceId,
    required String localMemberName,
    required WorkspaceRole localRole,
    String? overrideWorkspaceId,
    bool isHost = false,
  }) async {
    debugPrint(
      '[TRACE][WorkspaceSessionManager] ${_timestamp()} method=joinWorkspace field=currentWorkspace previous=${currentWorkspace?.id ?? 'null'} new=${payload['workspaceId']?.toString() ?? 'null'} stack=${StackTrace.current}',
    );
    final ownerDeviceId = payload['ownerDeviceId']?.toString() ??
        payload['hostEndpointId']?.toString() ??
        endpointId;
    final inferredRoleName = payload['workspaceRole']?.toString() ??
        payload['role']?.toString() ??
        localRole.name;
    final resolvedRole = WorkspaceRole.values.firstWhere(
      (value) => value.name == inferredRoleName,
      orElse: () => localRole,
    );

    final permissionsPayload = payload['permissions'];
    final resolvedPermissions = <String>[];
    if (permissionsPayload is List) {
      for (final item in permissionsPayload) {
        if (item is String && item.isNotEmpty) {
          resolvedPermissions.add(item);
        }
      }
    } else if (permissionsPayload is Map) {
      permissionsPayload.forEach((deviceId, value) {
        if (value is String && value.isNotEmpty) {
          resolvedPermissions.add('$deviceId:$value');
        } else if (value is List) {
          for (final entry in value) {
            if (entry is String && entry.isNotEmpty) {
              resolvedPermissions.add('$deviceId:$entry');
            }
          }
        }
      });
    }

    final appliedWorkspace = await workspaceService.applyWorkspaceSnapshot(
      payload,
      localDeviceId: localDeviceId,
      localMemberName: localMemberName,
      localRole: localRole,
      overrideWorkspaceId: overrideWorkspaceId,
      setActive: true,
    );

    final activatedWorkspace = await workspaceService.activateWorkspaceSession(
      workspaceId: appliedWorkspace.id,
      name: appliedWorkspace.name,
      description: appliedWorkspace.description,
      visibility: appliedWorkspace.visibility,
      password: appliedWorkspace.password,
      type: appliedWorkspace.type,
      icon: appliedWorkspace.icon,
      ownerName: appliedWorkspace.ownerName,
      ownerDeviceId: appliedWorkspace.ownerDeviceId,
      localDeviceId: localDeviceId,
      localMemberName: localMemberName,
      localRole: localRole,
      members: appliedWorkspace.members,
      resources: appliedWorkspace.resources,
      folders: appliedWorkspace.folders,
      announcements: appliedWorkspace.announcements,
      inboxMessages: appliedWorkspace.inboxMessages,
      activityLogs: appliedWorkspace.activityLogs,
      notifications: appliedWorkspace.notifications,
      transferHistory: appliedWorkspace.transferHistory,
      joinRequests: appliedWorkspace.joinRequests,
    );

    await workspaceService.setActiveWorkspace(activatedWorkspace.id);

    _traceState('activateWorkspaceFromPayload', 'currentWorkspace',
        currentWorkspace?.id ?? 'null', activatedWorkspace.id);
    currentWorkspace = activatedWorkspace;
    currentRole = resolvedRole.name;
    // ROOT CAUSE FIX (connectedHost corruption): prefer the live Nearby endpointId
    // (the actual transport target) over ownerDeviceId (a persistent App UUID that is
    // NOT a valid Nearby sendControl target). Previously this preferred ownerDeviceId,
    // which broke outgoing control messages (heartbeat/WORKSPACE_SYNC) whenever it
    // differed from the endpoint id.
    connectedHost = endpointId.isNotEmpty ? endpointId : ownerDeviceId;
    workspaceMembers = activatedWorkspace.members;
    workspaceService.refreshActiveWorkspace(activatedWorkspace);
    permissions = resolvedPermissions.isNotEmpty
        ? resolvedPermissions
        : activatedWorkspace.members
            .expand((member) => member.permissions
                .map((permission) => '${member.deviceId}:$permission'))
            .toList();
    sharedFolders = activatedWorkspace.folders;
    sharedResources = activatedWorkspace.resources;
    connectionState = 'connected';

    if (localDeviceId.isNotEmpty) {
      offlineSessionService.localDeviceId = localDeviceId;
    }
    if (isHost) {
      offlineSessionService.beginHostSession(
        workspaceId: activatedWorkspace.id,
        workspaceName: activatedWorkspace.name,
        ownerName: activatedWorkspace.ownerName,
        ownerDeviceId: activatedWorkspace.ownerDeviceId,
      );
    } else {
      offlineSessionService.beginClientSession(
        workspaceId: activatedWorkspace.id,
        workspaceName: activatedWorkspace.name,
        ownerName: activatedWorkspace.ownerName,
        ownerDeviceId: activatedWorkspace.ownerDeviceId,
      );
    }
    offlineSessionService.connectionState = 'connected';
    offlineSessionService.recordEvent('Workspace activated');
    await offlineSessionService.save();

    registerEndpoint(
      connectedHost,
      activatedWorkspace.ownerName.isEmpty
          ? 'Host'
          : activatedWorkspace.ownerName,
    );

    notifyWorkspaceActivated();
    notifyMembersUpdated();
    notifyResourcesUpdated();
    notifyFoldersUpdated();
    notifyPermissionUpdated();
    notifyConnectionStateChanged();
    await save();
    _startHeartbeat();

    return activatedWorkspace;
  }

  Future<void> applyWorkspaceSync(Map<String, dynamic> payload,
      {required String endpointId}) async {
    debugPrint('Workspace Sync Received: $payload');
    final workspaceId = payload['workspaceId']?.toString() ?? '';
    final workspaceName = payload['workspaceName']?.toString() ?? 'Workspace';
    final hostEndpointId = payload['hostEndpointId']?.toString() ?? endpointId;
    final workspaceMembersPayload =
        payload['workspaceMembers'] as List<dynamic>? ?? const [];
    final rolesPayload = payload['roles'] as Map<String, dynamic>? ?? const {};
    final dynamic permissionsPayload = payload['permissions'];
    final foldersPayload = (payload['folders'] as List<dynamic>?) ??
        (payload['sharedFolders'] as List<dynamic>?) ??
        const [];
    final resourcesPayload = (payload['resources'] as List<dynamic>?) ??
        (payload['sharedResources'] as List<dynamic>?) ??
        const [];
    final announcementsPayload =
        payload['announcements'] as List<dynamic>? ?? const [];
    final inboxPayload = payload['inboxMessages'] as List<dynamic>? ?? const [];
    final activityPayload =
        payload['activityLogs'] as List<dynamic>? ?? const [];
    final notificationsPayload =
        payload['notifications'] as List<dynamic>? ?? const [];
    final transferPayload =
        payload['transferHistory'] as List<dynamic>? ?? const [];
    final settings =
        payload['workspaceSettings'] as Map<String, dynamic>? ?? const {};
    final role = payload['workspaceRole']?.toString() ?? 'contributor';

    final resolvedMembers =
        workspaceMembersPayload.map<WorkspaceMember>((entry) {
      final map = Map<String, dynamic>.from(entry as Map);
      final deviceId =
          map['deviceId']?.toString() ?? map['id']?.toString() ?? '';
      final memberRole = rolesPayload[deviceId]?.toString() ??
          map['role']?.toString() ??
          'contributor';
      return WorkspaceMember(
        id: map['id']?.toString() ?? deviceId,
        name: map['name']?.toString() ?? 'Member',
        deviceId: deviceId,
        role: WorkspaceRole.values.firstWhere(
          (value) => value.name == memberRole,
          orElse: () => WorkspaceRole.contributor,
        ),
      );
    }).toList();

    final resolvedPermissions = <String>[];
    if (permissionsPayload is List) {
      for (final item in permissionsPayload) {
        if (item is String && item.isNotEmpty) {
          resolvedPermissions.add(item);
        }
      }
    } else if (permissionsPayload is Map) {
      permissionsPayload.forEach((deviceId, value) {
        if (value is String && value.isNotEmpty) {
          resolvedPermissions.add('$deviceId:$value');
        } else if (value is List) {
          for (final entry in value) {
            if (entry is String && entry.isNotEmpty) {
              resolvedPermissions.add('$deviceId:$entry');
            }
          }
        }
      });
    }

    final resolvedFolders = foldersPayload
        .map((entry) =>
            WorkspaceFolder.fromJson(Map<String, dynamic>.from(entry as Map)))
        .toList();
    final resolvedResources = resourcesPayload
        .map((entry) =>
            ResourceItem.fromJson(Map<String, dynamic>.from(entry as Map)))
        .toList();

    // ROOT CAUSE #4 FIX: Parse all workspace data fields
    final resolvedAnnouncements = announcementsPayload
        .map((entry) =>
            AnnouncementItem.fromJson(Map<String, dynamic>.from(entry as Map)))
        .toList();
    final resolvedInbox = inboxPayload
        .map((entry) =>
            InboxMessage.fromJson(Map<String, dynamic>.from(entry as Map)))
        .toList();
    final resolvedActivity = activityPayload
        .map((entry) =>
            ActivityLogEntry.fromJson(Map<String, dynamic>.from(entry as Map)))
        .toList();
    final resolvedNotifications = notificationsPayload
        .map((entry) => LocalNotificationItem.fromJson(
            Map<String, dynamic>.from(entry as Map)))
        .toList();
    final resolvedTransfer = transferPayload
        .map((entry) =>
            TransferRecord.fromJson(Map<String, dynamic>.from(entry as Map)))
        .toList();

    final ownerMember = resolvedMembers.firstWhere(
      (member) => member.role == WorkspaceRole.owner,
      orElse: () => resolvedMembers.isNotEmpty
          ? resolvedMembers.first
          : WorkspaceMember(
              id: hostEndpointId,
              name: 'Host',
              deviceId: hostEndpointId,
              role: WorkspaceRole.owner),
    );

    await activateWorkspaceFromPayload(
      {
        'workspaceId': workspaceId,
        'workspaceName': workspaceName,
        'workspaceDescription': '',
        'ownerName': ownerMember.name,
        'ownerDeviceId': hostEndpointId,
        'workspaceMembers':
            resolvedMembers.map((member) => member.toJson()).toList(),
        'members': resolvedMembers.map((member) => member.toJson()).toList(),
        'resources':
            resolvedResources.map((resource) => resource.toJson()).toList(),
        'folders': resolvedFolders.map((folder) => folder.toJson()).toList(),
        'announcements': resolvedAnnouncements
            .map((announcement) => announcement.toJson())
            .toList(),
        'inboxMessages':
            resolvedInbox.map((message) => message.toJson()).toList(),
        'activityLogs':
            resolvedActivity.map((entry) => entry.toJson()).toList(),
        'notifications': resolvedNotifications
            .map((notification) => notification.toJson())
            .toList(),
        'transferHistory':
            resolvedTransfer.map((transfer) => transfer.toJson()).toList(),
        'joinRequests': const [],
        'workspaceSettings': {
          'visibility': settings['visibility']?.toString() ?? 'Local',
          'type': settings['type']?.toString() ?? 'Connected',
          'icon': settings['icon']?.toString() ?? 'workspaces',
          'ownerName': ownerMember.name,
        },
        'permissions': resolvedPermissions,
        'workspaceRole': role,
      },
      endpointId: hostEndpointId,
      localDeviceId: offlineSessionService.localDeviceId.isEmpty
          ? hostEndpointId
          : offlineSessionService.localDeviceId,
      localMemberName: 'You',
      localRole: WorkspaceRole.values.firstWhere(
        (value) => value.name == role,
        orElse: () => WorkspaceRole.contributor,
      ),
      overrideWorkspaceId: workspaceId,
      isHost: false,
    );
  }

  Future<void> activateWorkspace({
    required WorkspaceModel workspace,
    required String role,
    required String hostEndpointId,
    required List<WorkspaceMember> members,
    required List<String> permissions,
    required List<WorkspaceFolder> folders,
    required List<ResourceItem> resources,
    List<AnnouncementItem>? announcements,
    List<InboxMessage>? inboxMessages,
    List<ActivityLogEntry>? activityLogs,
    List<LocalNotificationItem>? notifications,
    List<TransferRecord>? transferHistory,
    required bool isHost,
    required String localDeviceId,
    required String localMemberName,
  }) async {
    debugPrint('Workspace Activated: ${workspace.name}');
    _traceState('activateWorkspace', 'currentWorkspace',
        currentWorkspace?.id ?? 'null', workspace.id);
    currentWorkspace = workspace;
    currentRole = role;
    connectedHost = hostEndpointId;
    workspaceMembers = members;
    workspaceService.refreshActiveWorkspace(workspace);
    this.permissions = permissions;
    sharedFolders = folders;
    sharedResources = resources;
    connectionState = 'connected';
    registerEndpoint(hostEndpointId,
        workspace.ownerName.isEmpty ? 'Host' : workspace.ownerName);

    await workspaceService.activateWorkspaceSession(
      workspaceId: workspace.id,
      name: workspace.name,
      description: workspace.description,
      visibility: workspace.visibility,
      password: workspace.password,
      type: workspace.type,
      icon: workspace.icon,
      ownerName: workspace.ownerName,
      ownerDeviceId: workspace.ownerDeviceId,
      localDeviceId: localDeviceId,
      localMemberName: localMemberName,
      localRole: WorkspaceRole.values.firstWhere(
        (value) => value.name == role,
        orElse: () => WorkspaceRole.contributor,
      ),
      members: members,
      folders: folders,
      resources: resources,
      announcements: announcements ?? const [],
      inboxMessages: inboxMessages ?? const [],
      activityLogs: activityLogs ?? const [],
      notifications: notifications ?? const [],
      transferHistory: transferHistory ?? const [],
      joinRequests: const [],
    );
    await workspaceService.setActiveWorkspace(workspace.id);

    if (isHost) {
      offlineSessionService.beginHostSession(
        workspaceId: workspace.id,
        workspaceName: workspace.name,
        ownerName: workspace.ownerName,
        ownerDeviceId: workspace.ownerDeviceId,
      );
    } else {
      offlineSessionService.beginClientSession(
        workspaceId: workspace.id,
        workspaceName: workspace.name,
        ownerName: workspace.ownerName,
        ownerDeviceId: workspace.ownerDeviceId,
      );
    }
    offlineSessionService.connectionState = 'connected';
    offlineSessionService.recordEvent('Workspace activated');
    await offlineSessionService.save();
    await save();
    _startHeartbeat();
    notifyWorkspaceActivated();
    notifyMembersUpdated();
    notifyResourcesUpdated();
    notifyFoldersUpdated();
    notifyPermissionUpdated();
    notifyConnectionStateChanged();
  }

  Future<void> broadcastWorkspaceSync({
    required WorkspaceModel workspace,
    required String role,
    required String hostEndpointId,
    required List<WorkspaceMember> members,
    required List<String> permissions,
    required List<WorkspaceFolder> folders,
    required List<ResourceItem> resources,
  }) async {
    debugPrint('Workspace Sync Sent to ${endpointMap.keys.toList()}');
    final payload = {
      'workspaceId': workspace.id,
      'workspaceName': workspace.name,
      'hostEndpointId': hostEndpointId,
      'workspaceMembers': members
          .map((member) => {
                'id': member.id,
                'name': member.name,
                'deviceId': member.deviceId,
                'role': member.role.name,
              })
          .toList(),
      'roles': {
        for (final member in members) member.deviceId: member.role.name,
      },
      'permissions': {
        for (final permission in permissions)
          permission.split(':').first: permission.split(':').skip(1).join(':'),
      },
      'sharedFolders': folders.map((folder) => folder.toJson()).toList(),
      'sharedResources':
          resources.map((resource) => resource.toJson()).toList(),
      // Provide legacy/variant keys so receivers that look for different
      // field names will still pick up data. Some clients send/expect
      // `folders`/`resources` while others use `sharedFolders`/`sharedResources`.
      'folders': folders.map((folder) => folder.toJson()).toList(),
      'resources': resources.map((resource) => resource.toJson()).toList(),
      'members': members
          .map((member) => {
                'id': member.id,
                'name': member.name,
                'deviceId': member.deviceId,
                'role': member.role.name,
              })
          .toList(),
      'workspaceSettings': {
        'visibility': workspace.visibility,
        'type': workspace.type,
        'icon': workspace.icon,
      },
      'workspaceRole': role,
    };

    // Summarize payload counts for easier debugging
    final int outgoingFolders = (payload['folders'] as List).length;
    final int outgoingResources = (payload['resources'] as List).length;
    final int outgoingMembers = (payload['members'] as List).length;
    debugPrint(
      '[OUTGOING] WORKSPACE_SYNC payload folders=$outgoingFolders resources=$outgoingResources members=$outgoingMembers workspaceId=${payload['workspaceId']}');

    for (final endpoint in endpointMap.entries) {
      debugPrint(
        '[OUTGOING] Sending WORKSPACE_SYNC -> ${endpoint.key} folders=$outgoingFolders resources=$outgoingResources members=$outgoingMembers');
      // Flat spread so _handleControl can read workspaceId/resources/etc at top level.
      await nearbyService
          .sendControl(endpoint.key, {'type': 'WORKSPACE_SYNC', ...payload});
    }
  }

  void registerEndpoint(String endpointId, String name) {
    if (endpointId.isEmpty) return;
    endpointMap[endpointId] = name;
    debugPrint('Endpoint Found: $endpointId -> $name');
  }

  /// Returns the client's persistent app UUID for a given Nearby endpoint ID.
  /// Falls back to the endpoint ID if no UUID was recorded.
  String clientDeviceId(String endpointId) =>
      _endpointAppIds[endpointId] ?? endpointId;

  /// Returns the live Nearby endpoint ID for a persistent client app UUID.
  String? endpointIdForClientDeviceId(String deviceId) {
    for (final entry in _endpointAppIds.entries) {
      if (entry.value == deviceId) return entry.key;
    }
    return null;
  }

  void removeEndpoint(String endpointId) {
    endpointMap.remove(endpointId);
    debugPrint('Endpoint Lost: $endpointId');
  }

  void notifyWorkspaceActivated() {
    debugPrint('Workspace Activated: ${currentWorkspace?.name}');
    onWorkspaceActivated?.call(this);
  }

  void notifyWorkspaceUpdated() {
    debugPrint('Workspace Updated: ${currentWorkspace?.name}');
    onWorkspaceUpdated?.call(this);
  }

  void notifyMembersUpdated() {
    debugPrint('Members Synced: ${workspaceMembers.length}');
    onMembersUpdated?.call(this);
  }

  void notifyPermissionUpdated() {
    debugPrint('ACL Synced: $permissions');
    onPermissionUpdated?.call(this);
  }

  void notifyResourcesUpdated() {
    debugPrint('Resources Synced: ${sharedResources.length}');
    onResourcesUpdated?.call(this);
  }

  void notifyFoldersUpdated() {
    debugPrint('Folders Synced: ${sharedFolders.length}');
    onFoldersUpdated?.call(this);
  }

  void notifyConnectionStateChanged() {
    debugPrint('Connection State Changed: $connectionState');
    onConnectionStateChanged?.call(this);
  }

  void handleJoinApproved(String fromEndpointId) {
    debugPrint(
      '[TRACE][WorkspaceSessionManager] ${_timestamp()} method=handleJoinApproved field=currentWorkspace previous=${currentWorkspace?.id ?? 'null'} new=${currentWorkspace?.id ?? 'null'} stack=${StackTrace.current}',
    );
  }

  void handleHeartbeatReceived(String fromEndpointId) {
    _lastHeartbeatAt = DateTime.now();
    offlineSessionService.markHeartbeatReceived(from: fromEndpointId);
    debugPrint(
        '[STATE] HEARTBEAT_RECEIVED from $fromEndpointId at ${_lastHeartbeatAt!.toIso8601String()}');
    connectionState = 'connected';
    offlineSessionService.connectionState = 'connected';
    notifyConnectionStateChanged();
  }

  void disconnect() {
    debugPrint(
      '[TRACE][WorkspaceSessionManager] ${_timestamp()} method=disconnect field=currentWorkspace previous=${currentWorkspace?.id ?? 'null'} new=${currentWorkspace?.id ?? 'null'} stack=${StackTrace.current}',
    );
    markDisconnected();
  }

  void markDisconnected() {
    if (connectionState == 'disconnected') return;
    if (connectedHost.isNotEmpty && endpointMap.containsKey(connectedHost)) {
      connectionState = 'connected';
      offlineSessionService.connectionState = 'connected';
      notifyConnectionStateChanged();
      return;
    }
    connectionState = 'disconnected';
    offlineSessionService.connectionState = 'disconnected';
    debugPrint('Workspace disconnected');
    notifyConnectionStateChanged();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (connectedHost.isEmpty) return;
      debugPrint('[STATE] HEARTBEAT_SENT to $connectedHost');
      await nearbyService.sendControl(connectedHost, {'type': 'PING'});
      if (endpointMap.containsKey(connectedHost) && currentWorkspace != null) {
        connectionState = 'connected';
        offlineSessionService.connectionState = 'connected';
        notifyConnectionStateChanged();
      }
    });
  }

  void stop() {
    _heartbeatTimer?.cancel();
    _disconnectTimer?.cancel();
  }

  Future<void> terminateWorkspaceSession() async {
    debugPrint(
      '[TRACE][WorkspaceSessionManager] ${_timestamp()} method=terminateWorkspaceSession field=currentWorkspace previous=${currentWorkspace?.id ?? 'null'} new=null stack=${StackTrace.current}',
    );
    if (currentWorkspace == null) return;
    stop();
    currentRole = 'viewer';
    connectedHost = '';
    workspaceMembers = const [];
    permissions = const [];
    sharedFolders = const [];
    sharedResources = const [];
    endpointMap.clear();
    connectionState = 'disconnected';
    offlineSessionService.endSession();
    await save();
    notifyWorkspaceUpdated();
    notifyMembersUpdated();
    notifyResourcesUpdated();
    notifyFoldersUpdated();
    notifyPermissionUpdated();
    notifyConnectionStateChanged();
  }

  void Function(WorkspaceSessionManager manager)? onWorkspaceActivated;
  void Function(WorkspaceSessionManager manager)? onWorkspaceUpdated;
  void Function(WorkspaceSessionManager manager)? onMembersUpdated;
  void Function(WorkspaceSessionManager manager)? onPermissionUpdated;
  void Function(WorkspaceSessionManager manager)? onResourcesUpdated;
  void Function(WorkspaceSessionManager manager)? onFoldersUpdated;
  void Function(WorkspaceSessionManager manager)? onConnectionStateChanged;

  // Stream subscription callbacks and P2P connection logic
  void _handleEndpointFound(Map<String, dynamic> endpoint) {
    final endpointId = endpoint['endpointId'] as String?;
    final endpointName = endpoint['endpointName']?.toString() ?? 'unknown';
    debugPrint(
        '[ENDPOINT_DEBUG] _handleEndpointFound: id=$endpointId name=$endpointName totalKnown=${nearbyEndpoints.length}');
    if (endpointId == null) {
      debugPrint(
          '[ENDPOINT_DEBUG] _handleEndpointFound ABORT: endpointId is null');
      return;
    }
    nearbyEndpoints[endpointId] = endpoint;
    endpointTimestamps[endpointId] = DateTime.now();
    registerEndpoint(endpointId, endpointName);
    debugPrint(
        '[ENDPOINT_DEBUG] _handleEndpointFound stored: totalKnown=${nearbyEndpoints.length}');
    notifyListeners();
  }

  void _handleEndpointLost(Map<String, dynamic> endpoint) {
    final endpointId = endpoint['endpointId'] as String?;
    debugPrint('[ENDPOINT_DEBUG] _handleEndpointLost: id=$endpointId');
    debugPrint(
        '[ENDPOINT_DEBUG] _handleEndpointLost BEFORE: nearbyEndpoints.keys=${nearbyEndpoints.keys.toList()}');
    if (endpointId == null) {
      debugPrint(
          '[ENDPOINT_DEBUG] _handleEndpointLost ABORT: endpointId==null');
      return;
    }
    nearbyEndpoints.remove(endpointId);
    endpointTimestamps.remove(endpointId);
    endpointRights.remove(endpointId);
    final appUuid = _endpointAppIds.remove(endpointId);
    if (appUuid != null) {
      offlineSessionService.markMemberDisconnected(appUuid);
    }
    removeEndpoint(endpointId);
    if (endpointId == connectedHost) {
      markDisconnected();
    }
    debugPrint(
        '[ENDPOINT_DEBUG] _handleEndpointLost removed $endpointId, remaining=${nearbyEndpoints.length}');
    notifyListeners();
  }

  Future<void> _handleJoinRequest(Map<String, dynamic> request) async {
    final endpointId = request['fromEndpointId'] as String?;
    final endpointName =
        request['fromEndpointName'] as String? ?? 'Nearby device';
    final requestBody = request['request'] as String? ?? '';

    if (endpointId == null) return;

    final ownerDeviceId = offlineSessionService.localDeviceId.isEmpty
        ? 'local-device'
        : offlineSessionService.localDeviceId;

    WorkspaceModel workspace;
    if (isHostMode && offlineSessionService.ownerDeviceId == ownerDeviceId) {
      workspace = workspaceService.activeWorkspace ??
          await workspaceService.createWorkspace(
            name: joinedWorkspaceName ?? 'My Workspace',
            description: 'Offline workspace for nearby collaboration',
            visibility: 'Local',
            password: '',
            type: joinedWorkspaceType,
            icon: 'workspaces',
            ownerName: joinedOwnerName,
            ownerDeviceId: ownerDeviceId,
          );
    } else {
      isHostMode = true;
      workspace = await workspaceService.createWorkspace(
        name: joinedWorkspaceName ?? 'My Workspace',
        description: 'Offline workspace for nearby collaboration',
        visibility: 'Local',
        password: '',
        type: joinedWorkspaceType,
        icon: 'workspaces',
        ownerName: joinedOwnerName,
        ownerDeviceId: ownerDeviceId,
      );

      offlineSessionService.beginHostSession(
        workspaceId: workspace.id,
        workspaceName: workspace.name,
        ownerName: joinedOwnerName,
        ownerDeviceId: ownerDeviceId,
      );
    }

    String requesterName = endpointName;
    // Nearby endpoint ID is the correct target for respondJoin/sendControl; do not override with app UUID.
    String requesterDeviceId = endpointId;
    List<String> requestedRights = ['read', 'list'];
    String timestamp = DateTime.now().toIso8601String();

    try {
      if (requestBody.isNotEmpty) {
        final decoded = jsonDecode(requestBody) as Map<String, dynamic>;
        requesterName = decoded['requesterName']?.toString() ?? requesterName;
        // Record the client's persistent app UUID so the host can use it as
        // WorkspaceMember.deviceId instead of the transient Nearby endpoint ID.
        final decodedAppId = decoded['requesterDeviceId']?.toString();
        if (decodedAppId != null && decodedAppId.isNotEmpty) {
          _endpointAppIds[endpointId] = decodedAppId;
        }
        requesterDeviceId = _endpointAppIds[endpointId] ?? endpointId;
        requestedRights = List<String>.from(decoded['requestedRights'] ??
            decoded['requested_rights'] ??
            requestedRights);
        timestamp = decoded['timestamp']?.toString() ?? timestamp;
      }
    } catch (_) {}

    final workspaceId = workspace.id;
    final existingRequest = workspace.joinRequests.firstWhere(
      (item) =>
          item.requesterDeviceId == requesterDeviceId &&
          item.status == 'pending',
      orElse: () => JoinRequest(
        id: '',
        workspaceId: workspaceId,
        requesterName: requesterName,
        requesterDeviceId: requesterDeviceId,
        requestedRights: requestedRights,
        status: 'pending',
        createdAt: timestamp,
      ),
    );

    if (existingRequest.id.isEmpty) {
      await workspaceService.addJoinRequest(
        workspaceId: workspaceId,
        requesterName: requesterName,
        requesterDeviceId: requesterDeviceId,
        requestedRights: requestedRights,
      );
    }

    offlineSessionService.registerMember(
      deviceId: _endpointAppIds[endpointId] ?? endpointId,
      name: requesterName,
      role: 'contributor',
      connected: true,
    );
    registerEndpoint(endpointId, requesterName);

    debugPrint('[STATE] JOIN_REQUEST');
    debugPrint('[Nearby] JOIN_REQUEST_RECEIVED');

    notifyListeners();
  }

  Future<void> _handleJoinResponse(Map<String, dynamic> response) async {
    final responseData = response['response'];
    bool accepted = false;
    Map<String, dynamic>? approvalPayload;
    List<String> grantedRights = const [];
    final endpointId = response['fromEndpointId']?.toString() ?? '';

    try {
      final respJson =
          responseData is String ? responseData : responseData?.toString();
      if (respJson != null && respJson.isNotEmpty) {
        final jo = jsonDecode(respJson) as Map<String, dynamic>;
        approvalPayload = Map<String, dynamic>.from(jo);
        accepted = jo['accepted'] == true;
        final granted = jo['granted_rights'] as List<dynamic>? ??
            jo['granted_permissions'] as List<dynamic>?;
        grantedRights = granted?.map((e) => e.toString()).toList() ?? const [];
        if (grantedRights.isNotEmpty) {
          if (endpointId.isNotEmpty) {
            endpointRights[endpointId] = grantedRights;
          }
        }
      }
    } catch (_) {}

    if (accepted) {
      final approvedPayload = approvalPayload;
      final workspaceId = approvedPayload?['workspaceId']?.toString();
      if (approvedPayload != null && workspaceId != null) {
        if (_shouldSkipApprovalProcessing(endpointId, workspaceId)) {
          return;
        }
        debugPrint('[Nearby] JOIN_RESPONSE_RECEIVED');
        debugPrint('[STATE] JOIN_APPROVED');
        debugPrint('[Nearby] JOIN_APPROVED_BY_HOST');

        await _activateApprovedJoin(
          endpointId: endpointId,
          workspaceId: workspaceId,
        );
      }
    } else {
      _setJoinRequestState(pending: false, status: 'rejected');
      notifyListeners();
    }
  }

  bool _shouldSkipApprovalProcessing(String endpointId, String? workspaceId) {
    final key =
        '${endpointId.isEmpty ? 'unknown' : endpointId}:${workspaceId ?? 'unknown'}';
    if (_processedApprovalKeys.contains(key) &&
        workspaceSessionActive &&
        currentWorkspace?.id == workspaceId) {
      debugPrint('[Nearby] Skipping duplicate approval for $key');
      return true;
    }
    _processedApprovalKeys.add(key);
    return false;
  }

  void _setJoinRequestState({required bool pending, required String status}) {
    joinRequestPending = pending;
    joinRequestStatus = status;
    if (!pending) {
      debugPrint('[Nearby] JOIN_PENDING_CLEARED');
    }
  }

  Future<void> _activateApprovedJoin({
    required String endpointId,
    required String workspaceId,
  }) async {
    if (_isActivatingApprovedJoin) {
      debugPrint(
          '[STATE] _activateApprovedJoin already running – skipping concurrent call from endpointId=$endpointId workspaceId=$workspaceId');
      return;
    }
    _isActivatingApprovedJoin = true;
    // Arm the completer immediately so any WORKSPACE_SYNC arriving during
    // async setup below completes it rather than falling through to a direct apply.
    snapshotCompleter = Completer<Map<String, dynamic>>();
    try {
      debugPrint('[Nearby] POST_APPROVAL_SEQUENCE_START');

      // Step 1: End discovery mode
      debugPrint('[Nearby] ENDING_DISCOVERY_MODE');
      try {
        await nearbyService.stopDiscovery();
      } catch (_) {}
      // Explicitly clear the Dart-side flag; native onDiscoveryState callback may arrive late.
      nearbyDiscovering = false;
      notifyListeners();

      // Step 2: Mark join request as completed
      _setJoinRequestState(pending: false, status: 'approved');
      approvalPendingWorkspaceId = workspaceId;
      nearbyEndpoints.remove(endpointId);
      endpointTimestamps.remove(endpointId);
      debugPrint('[Nearby] JOIN_REQUEST_MARKED_COMPLETED');

      // Step 3-5: Create/activate OfflineSessionService and WorkspaceService
      debugPrint('[Nearby] ACTIVATING_SESSION_SERVICE');
      offlineSessionService.setDiscoveryActive(false);
      offlineSessionService.connectionState = 'connected';

      // Create or activate workspace
      debugPrint('[Nearby] ACTIVATING_WORKSPACE_SERVICE');
      final activeWorkspace = workspaceService.activeWorkspace;
      WorkspaceModel workspace;
      if (activeWorkspace != null && activeWorkspace.id == workspaceId) {
        workspace = activeWorkspace;
      } else {
        workspace = await workspaceService.createWorkspace(
          name: 'Joined Workspace',
          description: 'Offline workspace joined from nearby',
          visibility: 'Local',
          password: '',
          type: 'Connected',
          icon: 'workspaces',
          ownerName: 'Nearby Host',
          ownerDeviceId: endpointId,
        );
      }

      // Save activeWorkspaceId
      await workspaceService.setActiveWorkspace(workspace.id);
      debugPrint('[Nearby] WORKSPACE_ID_SAVED');

      // Step 6: Request workspace snapshot from host only if WORKSPACE_SYNC
      // has not already completed the completer (which the host sends immediately
      // after approval, so it often arrives before this line is reached).
      debugPrint(
          '[Nearby] REQUESTING_WORKSPACE_SNAPSHOT (completerDone=${snapshotCompleter!.isCompleted})');
      if (!snapshotCompleter!.isCompleted) {
        await nearbyService.sendControl(endpointId, {
          'type': 'WORKSPACE_SNAPSHOT_REQUEST',
          'workspaceId': workspaceId,
        });
      }

      // Step 7: Wait for snapshot data (timeout is a safety net only)
      debugPrint('[Nearby] WAITING_FOR_SNAPSHOT');
      Map<String, dynamic>? snapshotData;
      try {
        snapshotData = await snapshotCompleter!.future
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        debugPrint('[Nearby] Snapshot timeout or error: $e');
        snapshotData = null;
      } finally {
        snapshotCompleter = null;
      }

      // Step 8: Apply snapshot data to WorkspaceModel
      if (snapshotData != null) {
        debugPrint('[Nearby] SNAPSHOT_RECEIVED_APPLYING');
        workspace = await _applyWorkspaceSnapshot(workspace, snapshotData);
      } else {
        debugPrint('[Nearby] NO_SNAPSHOT_USING_MINIMAL_WORKSPACE');
      }

      // Step 9: Persist and mark as active
      debugPrint('[Nearby] PERSISTING_WORKSPACE');
      workspaceService.refreshActiveWorkspace(workspace);
      await workspaceService.setActiveWorkspace(workspace.id);
      await workspaceService.save();

      // Step 9b: Activate the client session so the workspace stays connected
      currentWorkspace = workspace;
      currentRole = 'contributor';
      // endpointId is the Nearby transport target; ownerDeviceId is not an endpoint ID
      connectedHost = endpointId;
      connectionState = 'connected';
      workspaceMembers = workspace.members;
      sharedFolders = workspace.folders;
      sharedResources = workspace.resources;
      permissions = workspace.members
          .expand((member) => member.permissions
              .map((permission) => '${member.deviceId}:$permission'))
          .toList();

      registerEndpoint(
        connectedHost,
        workspace.ownerName.isEmpty ? 'Host' : workspace.ownerName,
      );
      debugPrint('[STATE] ACTIVE_WORKSPACE_SET ${workspace.id}');

      offlineSessionService.beginClientSession(
        workspaceId: workspace.id,
        workspaceName: workspace.name,
        ownerName: workspace.ownerName,
        ownerDeviceId: workspace.ownerDeviceId,
      );
      offlineSessionService.connectionState = 'connected';
      offlineSessionService.recordEvent('Workspace activated');
      await offlineSessionService.save();

      notifyWorkspaceActivated();
      notifyMembersUpdated();
      notifyResourcesUpdated();
      notifyFoldersUpdated();
      notifyPermissionUpdated();
      notifyConnectionStateChanged();

      await save();
      _startHeartbeat();

      approvalPendingWorkspaceId = null;
      workspaceSessionActive = true;

      // Send a UI event to tell the active screen to navigate to dashboard
      _uiEventController.add('NAVIGATE_TO_DASHBOARD');
      notifyListeners();
    } finally {
      _isActivatingApprovedJoin = false;
    }
  }

  Future<WorkspaceModel> _applyWorkspaceSnapshot(
    WorkspaceModel baseWorkspace,
    Map<String, dynamic> snapshot,
  ) async {
    // Preserve workspaceSettings from the incoming message so workspace.type
    // is read by applyWorkspaceSnapshot from workspaceSettings, not payload['type'].
    final snapshotSettings =
        snapshot['workspaceSettings'] as Map<String, dynamic>? ?? const {};
    final snapshotPayload = {
      'workspaceId': baseWorkspace.id,
      'workspaceName': snapshot['workspaceName'] ?? baseWorkspace.name,
      'description': snapshot['description'] ?? baseWorkspace.description,
      'visibility': snapshot['visibility'] ??
          snapshotSettings['visibility']?.toString() ??
          'Local',
      'password': '',
      'workspaceSettings': {
        'type': snapshot['workspaceType'] ??
            snapshotSettings['type']?.toString() ??
            'Connected',
        'visibility': snapshot['visibility'] ??
            snapshotSettings['visibility']?.toString() ??
            'Local',
        'icon': snapshot['icon'] ??
            snapshotSettings['icon']?.toString() ??
            'workspaces',
      },
      'icon': snapshot['icon'] ??
          snapshotSettings['icon']?.toString() ??
          'workspaces',
      'ownerName': snapshot['ownerName'] ?? 'Nearby Host',
      'ownerDeviceId': snapshot['ownerDeviceId'] ?? baseWorkspace.ownerDeviceId,
      'createdAt': snapshot['createdAt'] ?? baseWorkspace.createdAt,
      'workspaceMembers': snapshot['workspaceMembers'] ?? [],
      'sharedResources':
          snapshot['sharedResources'] ?? snapshot['resources'] ?? [],
      'sharedFolders': snapshot['sharedFolders'] ?? snapshot['folders'] ?? [],
      'inboxMessages': snapshot['inboxMessages'] ?? [],
      'announcements': snapshot['announcements'] ?? [],
    };

    final snapshotWorkspace = await workspaceService.applyWorkspaceSnapshot(
      snapshotPayload,
      localDeviceId: offlineSessionService.localDeviceId.isEmpty
          ? 'local-device'
          : offlineSessionService.localDeviceId,
      localMemberName: 'My Device',
      localRole: WorkspaceRole.contributor,
      overrideWorkspaceId: baseWorkspace.id,
      setActive: true,
    );

    return snapshotWorkspace;
  }

  void _handleFileList(Map<String, dynamic> evt) {
    final filesJson = evt['files'] as String?;
    final from = evt['fromEndpointId'] as String? ?? 'host';
    if (filesJson == null) return;

    try {
      final arr = jsonDecode(filesJson) as List<dynamic>;
      remoteFiles[from] = arr;
      _uiEventController.add('FILE_LIST_UPDATED:$from');
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _handlePayloadBytes(Map<String, dynamic> evt) async {
    final endpointId = evt['endpointId'] as String?;
    final bytesRaw = evt['bytes'];
    if (bytesRaw == null) return;
    List<int> bytes;
    if (bytesRaw is List<int>) {
      bytes = bytesRaw;
    } else if (bytesRaw is Uint8List) {
      bytes = bytesRaw.toList();
    } else if (bytesRaw is List<dynamic>) {
      bytes = bytesRaw.cast<int>();
    } else {
      return;
    }

    if (bytes.length < 6) return;
    final idLen = bytes[0] & 0xff;
    if (bytes.length <= 1 + idLen + 4) return;
    final idBytes = bytes.sublist(1, 1 + idLen);
    final fileId = String.fromCharCodes(idBytes);
    final seqBytes = bytes.sublist(1 + idLen, 1 + idLen + 4);
    final seq = ((seqBytes[0] & 0xff) << 24) |
        ((seqBytes[1] & 0xff) << 16) |
        ((seqBytes[2] & 0xff) << 8) |
        (seqBytes[3] & 0xff);
    final payload = bytes.sublist(1 + idLen + 4);

    const chunkSize = 64 * 1024;
    downloadBuffers.putIfAbsent(fileId, () => <int>[]).addAll(payload);

    if (endpointId != null) {
      if (payload.length == chunkSize) {
        final nextSeq = seq + 1;
        await nearbyService.requestFileChunk(endpointId, fileId, nextSeq);
      } else {
        try {
          final dir = await getApplicationDocumentsDirectory();
          final outFile = File('${dir.path}/$fileId');
          await outFile.writeAsBytes(downloadBuffers[fileId] ?? []);
          downloadBuffers.remove(fileId);

          final workspace =
              currentWorkspace ?? workspaceService.activeWorkspace;
          if (workspace != null) {
            final transfer = await workspaceService.enqueueTransfer(
              workspaceId: workspace.id,
              fileName: fileId,
              direction: 'download',
              totalBytes: outFile.lengthSync(),
            );
            await workspaceService.completeTransfer(workspace.id, transfer.id);

            await workspaceService.addResource(
              workspaceId: workspace.id,
              name: fileId,
              kind: 'Document',
              sizeBytes: outFile.lengthSync(),
              path: outFile.path,
            );
          }

          _uiEventController.add('DOWNLOAD_COMPLETE:$fileId');
          notifyListeners();
        } catch (e) {
          debugPrint('Failed to save downloaded file: $e');
        }
      }
    }
  }

  void _handleUploadProgress(Map<String, dynamic> evt) {
    try {
      final fid = evt['file_id'] as String?;
      final sent = evt['sent_bytes'] as int?;
      if (fid != null && sent != null) {
        final tot = uploadTotals[fid] ?? 0;
        uploadAcked[fid] = math.min(tot, sent);
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _handleControl(Map<String, dynamic> evt) async {
    try {
      final controlStr = evt['control'] as String?;
      if (controlStr == null) return;
      final jo = jsonDecode(controlStr) as Map<String, dynamic>;
      final type = jo['type'] as String?;
      final endpointId = evt['endpointId']?.toString() ?? '';

      debugPrint(
          '[Nearby] Persistent control received: $type from $endpointId');

      if (type == 'WORKSPACE_APPROVED' || type == 'JOIN_APPROVED') {
        final data = Map<String, dynamic>.from(jo as Map? ?? const {});
        final workspaceId = data['workspaceId']?.toString();
        if (workspaceId != null &&
            !_shouldSkipApprovalProcessing(endpointId, workspaceId)) {
          debugPrint('[STATE] JOIN_APPROVED');
          debugPrint('[Nearby] JOIN_APPROVED_BY_HOST');
          await _activateApprovedJoin(
            endpointId: endpointId,
            workspaceId: workspaceId,
          );
        }
        return;
      }

      if (type == 'WORKSPACE_SNAPSHOT' || type == 'WORKSPACE_SYNC') {
        final data = Map<String, dynamic>.from(jo as Map? ?? const {});
        debugPrint('[STATE] WORKSPACE_SYNC_RECEIVED');
        debugPrint('[Nearby] WORKSPACE_SNAPSHOT_RECEIVED');
        try {
          final incomingFolders = (data['folders'] as List<dynamic>?) ??
              (data['sharedFolders'] as List<dynamic>?) ??
              const [];
          final incomingResources = (data['resources'] as List<dynamic>?) ??
              (data['sharedResources'] as List<dynamic>?) ??
              const [];
          debugPrint(
              '[DEBUG_LOG] Incoming WORKSPACE_SYNC: folders=${incomingFolders.length} resources=${incomingResources.length} keys=${data.keys.toList()}');
        } catch (_) {}

        if (snapshotCompleter != null && !snapshotCompleter!.isCompleted) {
          snapshotCompleter!.complete(data);
          return;
        }

        final workspaceId = data['workspaceId']?.toString();
        if (workspaceId != null) {
          final localDeviceId = offlineSessionService.localDeviceId.isEmpty
              ? 'local-device'
              : offlineSessionService.localDeviceId;

          _isApplyingNetworkSync = true;
          try {
            await workspaceService.applyWorkspaceSnapshot(
              data,
              localDeviceId: localDeviceId,
              localMemberName: 'My Device',
              localRole: WorkspaceRole.contributor,
              overrideWorkspaceId: workspaceId,
              setActive: true,
            );
            _syncFromWorkspaceService();
          } finally {
            _isApplyingNetworkSync = false;
          }
          // Refresh session-manager fields now that isApplyingNetworkSync is clear.
          _syncFromWorkspaceService();

          final isLocalHost = isHostMode ||
              workspaceService.activeWorkspace?.ownerDeviceId == localDeviceId;
          if (isLocalHost) {
            final active = workspaceService.activeWorkspace;
            if (active != null) {
              await broadcastWorkspaceSync(
                workspace: active,
                role: 'owner',
                hostEndpointId: localDeviceId,
                members: active.members,
                permissions: permissions,
                folders: active.folders,
                resources: active.resources,
              );
            }
          }
        }
        return;
      }

      if (type == 'WORKSPACE_SNAPSHOT_REQUEST') {
        debugPrint('[Nearby] WORKSPACE_SNAPSHOT_REQUEST_RECEIVED');
        final active = workspaceService.activeWorkspace;
        if (active != null) {
          final membersPayload = active.members.map((m) => m.toJson()).toList();
          final resourcesPayload =
              active.resources.map((r) => r.toJson()).toList();
          final foldersPayload = active.folders.map((f) => f.toJson()).toList();
          final announcementsPayload =
              active.announcements.map((a) => a.toJson()).toList();
          final activityPayload =
              active.activityLogs.map((a) => a.toJson()).toList();
          final inboxPayload =
              active.inboxMessages.map((m) => m.toJson()).toList();
          final notificationsPayload =
              active.notifications.map((n) => n.toJson()).toList();
          final transferPayload =
              active.transferHistory.map((t) => t.toJson()).toList();

          final snapshotPayload = {
            'type': 'WORKSPACE_SNAPSHOT',
            'workspaceId': active.id,
            'workspaceName': active.name,
            'description': active.description,
            'ownerName': active.ownerName,
            'ownerDeviceId': active.ownerDeviceId,
            'createdAt': active.createdAt,
            // Include workspaceSettings so the client resolves workspace.type correctly.
            'workspaceSettings': {
              'type': active.type,
              'visibility': active.visibility,
              'icon': active.icon,
            },
            'workspaceMembers': membersPayload,
            'sharedResources': resourcesPayload,
            'sharedFolders': foldersPayload,
            // Backwards-compatible aliases
            'resources': resourcesPayload,
            'folders': foldersPayload,
            'announcements': announcementsPayload,
            'activityLogs': activityPayload,
            'inboxMessages': inboxPayload,
            'notifications': notificationsPayload,
            'transferHistory': transferPayload,
          };
          await nearbyService.sendControl(endpointId, snapshotPayload);
          debugPrint('[Nearby] Sent WORKSPACE_SNAPSHOT to $endpointId');
        }
        return;
      }

      if (type == 'PING') {
        debugPrint('Heartbeat PING received from $endpointId');
        await nearbyService.sendControl(endpointId, {'type': 'PONG'});
        handleHeartbeatReceived(endpointId);
        return;
      }

      if (type == 'PONG') {
        debugPrint('Heartbeat PONG received from $endpointId');
        handleHeartbeatReceived(endpointId);
        return;
      }
      if (type == 'CHUNK_ACK') {
        final tid = jo['transfer_id'];
        final seq = jo['seq'];
        if (tid != null && seq != null) {
          final int s = (seq is int) ? seq : int.tryParse(seq.toString()) ?? 0;
          final total = uploadTotals[tid];
          if (total != null) {
            uploadAcked[tid] =
                math.min(total, (s + 1) * NearbyService.chunkSize);
            notifyListeners();
          }
        }
        return;
      }

      if (type == 'FILE_UPLOAD_RESULT') {
        final tid = jo['transfer_id'];
        if (tid != null) {
          final tot = uploadTotals[tid];
          if (tot != null) {
            uploadAcked[tid] = tot;
            notifyListeners();
            Future.delayed(const Duration(seconds: 2)).then((_) {
              uploadTotals.remove(tid);
              uploadAcked.remove(tid);
              notifyListeners();
            });
          }
        }
        _uiEventController.add('UPLOAD_COMPLETE:$tid');
        return;
      }

      if (type == 'FILE_UPLOAD_RESPONSE') {
        return;
      }

      if (type == 'FILE_DELETE') {
        final fileId = jo['file_id'] as String?;
        if (fileId != null && workspaceService.activeWorkspace != null) {
          await workspaceService.deleteResource(
              workspaceService.activeWorkspace!.id, fileId);
          try {
            final dir = await getApplicationDocumentsDirectory();
            final f = File('${dir.path}/$fileId');
            if (await f.exists()) await f.delete();
          } catch (_) {}
          _syncFromWorkspaceService();
        }
        return;
      }

      if (type == 'FILE_DELETE_RESULT' || type == 'FILE_DELETED') {
        final fid = jo['file_id'] as String?;
        if (fid != null && workspaceService.activeWorkspace != null) {
          await workspaceService.deleteResource(
              workspaceService.activeWorkspace!.id, fid);
          _syncFromWorkspaceService();
        }
        return;
      }
    } catch (e) {
      debugPrint('Failed to parse control message: $e');
    }
  }

  Future<void> requestJoinWorkspace({
    required String endpointId,
    required String endpointName,
    required String requesterName,
    required String localDeviceId,
  }) async {
    if (joinRequestPending ||
        workspaceSessionActive ||
        approvalPendingWorkspaceId != null) {
      debugPrint(
          '[Nearby] JOIN_REQUEST_SKIPPED: session already pending or active');
      return;
    }
    final requestPayload = {
      'workspaceId': joinedWorkspaceName == null
          ? 'workspace_unknown'
          : joinedWorkspaceName!.replaceAll(' ', '_').toLowerCase(),
      'workspaceName': joinedWorkspaceName ?? endpointName,
      'requesterName': requesterName,
      'requesterDeviceId': localDeviceId,
      'requestedRights': ['read', 'write', 'list'],
      'timestamp': DateTime.now().toIso8601String(),
    };
    debugPrint('[Nearby] JOIN_REQUEST_SENT');
    _setJoinRequestState(pending: true, status: 'pending');
    notifyListeners();

    await nearbyService.requestJoin(endpointId, requestPayload);
  }

  Future<void> startNearbyDiscovery() async {
    debugPrint(
        '[DISCOVERY_DEBUG] startNearbyDiscovery: nearbyDiscovering=$nearbyDiscovering');
    if (nearbyDiscovering) {
      debugPrint('[DISCOVERY_DEBUG] already active – skipping duplicate start');
      return;
    }
    offlineSessionService.setDiscoveryActive(true);
    nearbyDiscovering = true;
    notifyListeners();
    try {
      await nearbyService.startDiscovery();
      debugPrint('[DISCOVERY_DEBUG] startDiscovery native call returned');
    } catch (e) {
      debugPrint('[DISCOVERY_DEBUG] startDiscovery THREW: $e');
      offlineSessionService.setDiscoveryActive(false);
      nearbyDiscovering = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stopNearbyDiscovery() async {
    debugPrint('[DISCOVERY_DEBUG] stopNearbyDiscovery called');
    try {
      await nearbyService.stopDiscovery();
    } catch (_) {}
    nearbyDiscovering = false;
    notifyListeners();
  }

  Future<void> startNearbyAdvertising(String name, String type) async {
    debugPrint(
        '[ADVERTISING_DEBUG] startNearbyAdvertising: name=$name type=$type advertisingNearby=$advertisingNearby');
    if (advertisingNearby) return;
    offlineSessionService.setAdvertisingActive(true);
    advertisingNearby = true;
    isHostMode = true;
    joinedWorkspaceName = name;
    joinedWorkspaceType = type;
    notifyListeners();
    try {
      await nearbyService.stopAdvertising();
    } catch (_) {}
    try {
      await nearbyService.startAdvertising('NEXUS', name);
      debugPrint(
          '[ADVERTISING_DEBUG] startAdvertising returned for name=$name');
    } catch (e) {
      debugPrint('[ADVERTISING_DEBUG] startAdvertising THREW: $e');
      advertisingNearby = false;
      isHostMode = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stopNearbyAdvertising() async {
    try {
      await nearbyService.stopAdvertising();
    } catch (_) {}
    advertisingNearby = false;
    notifyListeners();
  }

  Future<void> tryAutoReconnect() async {
    if (connectionState != 'connected' || connectedHost.isEmpty) return;
    debugPrint('[Nearby] Initiating Auto Reconnect to host: $connectedHost');

    try {
      await nearbyService.requestJoin(connectedHost, {
        'workspaceId': currentWorkspace?.id ?? 'workspace_unknown',
        'workspaceName': currentWorkspace?.name ?? 'Nearby Workspace',
        'requesterDeviceId': offlineSessionService.localDeviceId,
        'timestamp': DateTime.now().toIso8601String(),
        'auto_reconnect': true,
      });
    } catch (e) {
      debugPrint('[Nearby] Auto reconnect request failed: $e');
    }
  }
}
