import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum WorkspaceRole { owner, admin, contributor, viewer }

enum WorkspacePermission {
  manageMembers,
  resources,
  announcements,
  upload,
  download
}

class WorkspaceModel {
  WorkspaceModel({
    required this.id,
    required this.name,
    required this.description,
    required this.visibility,
    required this.password,
    required this.type,
    required this.icon,
    required this.ownerName,
    required this.ownerDeviceId,
    required this.createdAt,
    this.members = const [],
    this.resources = const [],
    this.folders = const [],
    this.announcements = const [],
    this.inboxMessages = const [],
    this.activityLogs = const [],
    this.transferHistory = const [],
    this.joinRequests = const [],
    this.notifications = const [],
  });

  final String id;
  final String name;
  final String description;
  final String visibility;
  final String password;
  final String type;
  final String icon;
  final String ownerName;
  final String ownerDeviceId;
  final String createdAt;
  final List<WorkspaceMember> members;
  final List<ResourceItem> resources;
  final List<WorkspaceFolder> folders;
  final List<AnnouncementItem> announcements;
  final List<InboxMessage> inboxMessages;
  final List<ActivityLogEntry> activityLogs;
  final List<TransferRecord> transferHistory;
  final List<JoinRequest> joinRequests;
  final List<LocalNotificationItem> notifications;

  WorkspaceModel copyWith({
    String? id,
    String? name,
    String? description,
    String? visibility,
    String? password,
    String? type,
    String? icon,
    String? ownerName,
    String? ownerDeviceId,
    String? createdAt,
    List<WorkspaceMember>? members,
    List<ResourceItem>? resources,
    List<WorkspaceFolder>? folders,
    List<AnnouncementItem>? announcements,
    List<InboxMessage>? inboxMessages,
    List<ActivityLogEntry>? activityLogs,
    List<TransferRecord>? transferHistory,
    List<JoinRequest>? joinRequests,
    List<LocalNotificationItem>? notifications,
  }) {
    return WorkspaceModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      visibility: visibility ?? this.visibility,
      password: password ?? this.password,
      type: type ?? this.type,
      icon: icon ?? this.icon,
      ownerName: ownerName ?? this.ownerName,
      ownerDeviceId: ownerDeviceId ?? this.ownerDeviceId,
      createdAt: createdAt ?? this.createdAt,
      members: members ?? this.members,
      resources: resources ?? this.resources,
      folders: folders ?? this.folders,
      announcements: announcements ?? this.announcements,
      inboxMessages: inboxMessages ?? this.inboxMessages,
      activityLogs: activityLogs ?? this.activityLogs,
      transferHistory: transferHistory ?? this.transferHistory,
      joinRequests: joinRequests ?? this.joinRequests,
      notifications: notifications ?? this.notifications,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'visibility': visibility,
        'password': password,
        'type': type,
        'icon': icon,
        'ownerName': ownerName,
        'ownerDeviceId': ownerDeviceId,
        'createdAt': createdAt,
        'members': members.map((m) => m.toJson()).toList(),
        'resources': resources.map((r) => r.toJson()).toList(),
        'folders': folders.map((f) => f.toJson()).toList(),
        'announcements': announcements.map((a) => a.toJson()).toList(),
        'inboxMessages': inboxMessages.map((m) => m.toJson()).toList(),
        'activityLogs': activityLogs.map((a) => a.toJson()).toList(),
        'transferHistory': transferHistory.map((t) => t.toJson()).toList(),
        'joinRequests': joinRequests.map((j) => j.toJson()).toList(),
        'notifications': notifications.map((n) => n.toJson()).toList(),
      };

  factory WorkspaceModel.empty() => WorkspaceModel(
        id: '',
        name: '',
        description: '',
        visibility: 'Local',
        password: '',
        type: 'Personal',
        icon: 'workspaces',
        ownerName: 'Owner',
        ownerDeviceId: '',
        createdAt: DateTime.now().toIso8601String(),
      );

  factory WorkspaceModel.fromJson(Map<String, dynamic> map) => WorkspaceModel(
        id: map['id']?.toString() ?? '',
        name: map['name']?.toString() ?? 'Workspace',
        description: map['description']?.toString() ?? '',
        visibility: map['visibility']?.toString() ?? 'Local',
        password: map['password']?.toString() ?? '',
        type: map['type']?.toString() ?? 'Personal',
        icon: map['icon']?.toString() ?? 'workspaces',
        ownerName: map['ownerName']?.toString() ?? 'Owner',
        ownerDeviceId: map['ownerDeviceId']?.toString() ?? '',
        createdAt:
            map['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
        members: List<Map<String, dynamic>>.from(map['members'] ?? [])
            .map(WorkspaceMember.fromJson)
            .toList(),
        resources: List<Map<String, dynamic>>.from(map['resources'] ?? [])
            .map(ResourceItem.fromJson)
            .toList(),
        folders: List<Map<String, dynamic>>.from(map['folders'] ?? [])
            .map(WorkspaceFolder.fromJson)
            .toList(),
        announcements:
            List<Map<String, dynamic>>.from(map['announcements'] ?? [])
                .map(AnnouncementItem.fromJson)
                .toList(),
        inboxMessages:
            List<Map<String, dynamic>>.from(map['inboxMessages'] ?? [])
                .map(InboxMessage.fromJson)
                .toList(),
        activityLogs: List<Map<String, dynamic>>.from(map['activityLogs'] ?? [])
            .map(ActivityLogEntry.fromJson)
            .toList(),
        transferHistory:
            List<Map<String, dynamic>>.from(map['transferHistory'] ?? [])
                .map(TransferRecord.fromJson)
                .toList(),
        joinRequests: List<Map<String, dynamic>>.from(map['joinRequests'] ?? [])
            .map(JoinRequest.fromJson)
            .toList(),
        notifications:
            List<Map<String, dynamic>>.from(map['notifications'] ?? [])
                .map(LocalNotificationItem.fromJson)
                .toList(),
      );
}

class WorkspaceMember {
  WorkspaceMember({
    required this.id,
    required this.name,
    required this.deviceId,
    required this.role,
    this.permissions = const [],
  });

  final String id;
  final String name;
  final String deviceId;
  final WorkspaceRole role;
  final List<String> permissions;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'deviceId': deviceId,
        'role': role.name,
        'permissions': permissions,
      };

  factory WorkspaceMember.fromJson(Map<String, dynamic> map) => WorkspaceMember(
        id: map['id']?.toString() ?? '',
        name: map['name']?.toString() ?? 'Member',
        deviceId: map['deviceId']?.toString() ?? '',
        role: WorkspaceRole.values.firstWhere(
          (role) => role.name == map['role'],
          orElse: () => WorkspaceRole.contributor,
        ),
        permissions: (map['permissions'] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .toList(),
      );
}

class ResourceItem {
  ResourceItem({
    required this.id,
    required this.name,
    required this.kind,
    required this.sizeBytes,
    required this.path,
    this.folderId,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String kind;
  final int sizeBytes;
  final String path;
  final String? folderId;
  final String createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'sizeBytes': sizeBytes,
        'path': path,
        'folderId': folderId,
        'createdAt': createdAt,
      };

  factory ResourceItem.fromJson(Map<String, dynamic> map) => ResourceItem(
        id: map['id']?.toString() ?? '',
        name: map['name']?.toString() ?? 'resource',
        kind: map['kind']?.toString() ?? 'Documents',
        sizeBytes: int.tryParse(map['sizeBytes']?.toString() ?? '0') ?? 0,
        path: map['path']?.toString() ?? '',
        folderId: map['folderId']?.toString(),
        createdAt:
            map['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
      );
}

class AnnouncementItem {
  AnnouncementItem({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final String createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'createdAt': createdAt,
      };

  factory AnnouncementItem.fromJson(Map<String, dynamic> map) =>
      AnnouncementItem(
        id: map['id']?.toString() ?? '',
        title: map['title']?.toString() ?? 'Announcement',
        body: map['body']?.toString() ?? '',
        createdAt:
            map['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
      );
}

class InboxMessage {
  InboxMessage({
    required this.id,
    required this.senderName,
    required this.subject,
    required this.body,
    required this.createdAt,
    this.read = false,
  });

  final String id;
  final String senderName;
  final String subject;
  final String body;
  final String createdAt;
  final bool read;

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderName': senderName,
        'subject': subject,
        'body': body,
        'createdAt': createdAt,
        'read': read,
      };

  factory InboxMessage.fromJson(Map<String, dynamic> map) => InboxMessage(
        id: map['id']?.toString() ?? '',
        senderName: map['senderName']?.toString() ?? 'Unknown',
        subject: map['subject']?.toString() ?? 'Message',
        body: map['body']?.toString() ?? '',
        createdAt:
            map['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
        read: map['read'] == true || map['read']?.toString() == 'true',
      );
}

class ActivityLogEntry {
  ActivityLogEntry({
    required this.id,
    required this.title,
    required this.detail,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String detail;
  final String createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'detail': detail,
        'createdAt': createdAt,
      };

  factory ActivityLogEntry.fromJson(Map<String, dynamic> map) =>
      ActivityLogEntry(
        id: map['id']?.toString() ?? '',
        title: map['title']?.toString() ?? 'Activity',
        detail: map['detail']?.toString() ?? '',
        createdAt:
            map['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
      );
}

class WorkspaceFolder {
  WorkspaceFolder({
    required this.id,
    required this.name,
    required this.parentId,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String parentId;
  final String createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'parentId': parentId,
        'createdAt': createdAt,
      };

  factory WorkspaceFolder.fromJson(Map<String, dynamic> map) => WorkspaceFolder(
        id: map['id']?.toString() ?? '',
        name: map['name']?.toString() ?? 'Folder',
        parentId: map['parentId']?.toString() ?? '',
        createdAt:
            map['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
      );
}

class TransferRecord {
  TransferRecord({
    required this.id,
    required this.fileName,
    required this.direction,
    required this.status,
    required this.totalBytes,
    required this.transferredBytes,
    required this.startedAt,
    this.attempts = 0,
    this.errorMessage = '',
  });

  final String id;
  final String fileName;
  final String direction;
  final String status;
  final int totalBytes;
  final int transferredBytes;
  final String startedAt;
  final int attempts;
  final String errorMessage;

  double get progress => totalBytes == 0 ? 0 : transferredBytes / totalBytes;

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'direction': direction,
        'status': status,
        'totalBytes': totalBytes,
        'transferredBytes': transferredBytes,
        'startedAt': startedAt,
        'attempts': attempts,
        'errorMessage': errorMessage,
      };

  factory TransferRecord.fromJson(Map<String, dynamic> map) => TransferRecord(
        id: map['id']?.toString() ?? '',
        fileName: map['fileName']?.toString() ?? 'transfer',
        direction: map['direction']?.toString() ?? 'upload',
        status: map['status']?.toString() ?? 'queued',
        totalBytes: int.tryParse(map['totalBytes']?.toString() ?? '0') ?? 0,
        transferredBytes:
            int.tryParse(map['transferredBytes']?.toString() ?? '0') ?? 0,
        startedAt:
            map['startedAt']?.toString() ?? DateTime.now().toIso8601String(),
        attempts: int.tryParse(map['attempts']?.toString() ?? '0') ?? 0,
        errorMessage: map['errorMessage']?.toString() ?? '',
      );
}

class JoinRequest {
  JoinRequest({
    required this.id,
    required this.workspaceId,
    required this.requesterName,
    required this.requesterDeviceId,
    required this.requestedRights,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String workspaceId;
  final String requesterName;
  final String requesterDeviceId;
  final List<String> requestedRights;
  final String status;
  final String createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'workspaceId': workspaceId,
        'requesterName': requesterName,
        'requesterDeviceId': requesterDeviceId,
        'requestedRights': requestedRights,
        'status': status,
        'createdAt': createdAt,
      };

  factory JoinRequest.fromJson(Map<String, dynamic> map) => JoinRequest(
        id: map['id']?.toString() ?? '',
        workspaceId: map['workspaceId']?.toString() ?? '',
        requesterName: map['requesterName']?.toString() ?? 'Requester',
        requesterDeviceId: map['requesterDeviceId']?.toString() ?? '',
        requestedRights: List<String>.from(map['requestedRights'] ?? []),
        status: map['status']?.toString() ?? 'pending',
        createdAt:
            map['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
      );
}

class LocalNotificationItem {
  LocalNotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String message;
  final String createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'message': message,
        'createdAt': createdAt,
      };

  factory LocalNotificationItem.fromJson(Map<String, dynamic> map) =>
      LocalNotificationItem(
        id: map['id']?.toString() ?? '',
        title: map['title']?.toString() ?? 'Notification',
        message: map['message']?.toString() ?? '',
        createdAt:
            map['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
      );
}

class WorkspaceService extends ChangeNotifier {
  static const String _prefKey = 'workspace_service_state';

  final List<WorkspaceModel> _workspaces = [];
  final List<JoinRequest> _pendingJoinRequests = [];
  String? _activeWorkspaceId;
  bool _loaded = false;

  String _timestamp() => DateTime.now().toIso8601String();

  void _traceState(
      String method, String field, Object? previousValue, Object? newValue) {
    debugPrint(
      '[TRACE][WorkspaceService] ${_timestamp()} method=$method field=$field previous=$previousValue new=$newValue stack=${StackTrace.current}',
    );
  }

  void _setActiveWorkspaceId(String? newValue, {required String method}) {
    final previousValue = _activeWorkspaceId;
    if (previousValue != newValue) {
      _traceState(method, '_activeWorkspaceId', previousValue, newValue);
    }
    _activeWorkspaceId = newValue;
  }

  void _traceWorkspaceMutation(String method, String action) {
    final previousValue = _workspaces.map((workspace) => workspace.id).toList();
    debugPrint(
      '[TRACE][WorkspaceService] ${_timestamp()} method=$method action=$action field=_workspaces previous=$previousValue new=${_workspaces.map((workspace) => workspace.id).toList()} stack=${StackTrace.current}',
    );
  }

  List<WorkspaceModel> get workspaces => List.unmodifiable(_workspaces);
  List<JoinRequest> get pendingJoinRequests =>
      List.unmodifiable(_pendingJoinRequests);
  WorkspaceModel? get activeWorkspace => _activeWorkspaceId == null
      ? (_workspaces.isNotEmpty ? _workspaces.first : null)
      : _workspaces.cast<WorkspaceModel?>().firstWhere(
            (workspace) => workspace?.id == _activeWorkspaceId,
            orElse: () => null,
          );
  bool get loaded => _loaded;

  Future<void> load() async {
    final previousActiveWorkspaceId = _activeWorkspaceId;
    debugPrint(
      '[TRACE][WorkspaceService] ${_timestamp()} method=load field=_activeWorkspaceId previous=$previousActiveWorkspaceId new=$previousActiveWorkspaceId stack=${StackTrace.current}',
    );
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null || raw.isEmpty) {
      _loaded = true;
      notifyListeners();
      return;
    }

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _traceWorkspaceMutation('load', 'clear');
      _workspaces.clear();
      _pendingJoinRequests.clear();
      _setActiveWorkspaceId(decoded['activeWorkspaceId']?.toString(),
          method: 'load');
      final workspaceMaps =
          List<Map<String, dynamic>>.from(decoded['workspaces'] ?? []);
      for (final workspaceMap in workspaceMaps) {
        final workspace = WorkspaceModel.fromJson(workspaceMap);
        _workspaces.add(workspace);
        for (final request in workspace.joinRequests
            .where((entry) => entry.status == 'pending')) {
          _pendingJoinRequests.add(request);
        }
      }
      _loaded = true;
      notifyListeners();
    } catch (_) {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> save() async {
    debugPrint(
      '[TRACE][WorkspaceService] ${_timestamp()} method=save field=_activeWorkspaceId previous=$_activeWorkspaceId new=$_activeWorkspaceId stack=${StackTrace.current}',
    );
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'activeWorkspaceId': _activeWorkspaceId,
      'workspaces': _workspaces.map((workspace) => workspace.toJson()).toList(),
    };
    await prefs.setString(_prefKey, jsonEncode(payload));
    notifyListeners();
  }

  void updateWorkspaceInPlace(WorkspaceModel workspace) {
    final index = _workspaces.indexWhere((entry) => entry.id == workspace.id);
    if (index >= 0) {
      _workspaces[index] = workspace;
      if (_activeWorkspaceId == null || _activeWorkspaceId == workspace.id) {
        _setActiveWorkspaceId(workspace.id, method: 'updateWorkspaceInPlace');
      }
      notifyListeners();
    }
  }

  void refreshActiveWorkspace(WorkspaceModel workspace) {
    final index = _workspaces.indexWhere((entry) => entry.id == workspace.id);
    if (index >= 0) {
      _workspaces[index] = workspace;
    } else {
      _workspaces.add(workspace);
    }
    _setActiveWorkspaceId(workspace.id, method: 'refreshActiveWorkspace');
    notifyListeners();
  }

  Future<WorkspaceModel> ensureWorkspace({
    required String name,
    required String description,
    required String visibility,
    required String password,
    required String type,
    required String icon,
    required String ownerName,
    required String ownerDeviceId,
  }) async {
    final existing = _workspaces.where((workspace) {
      final normalizedName = workspace.name.trim().toLowerCase();
      return normalizedName == name.trim().toLowerCase();
    }).toList();
    if (existing.isNotEmpty) {
      return existing.first;
    }
    return createWorkspace(
      name: name,
      description: description,
      visibility: visibility,
      password: password,
      type: type,
      icon: icon,
      ownerName: ownerName,
      ownerDeviceId: ownerDeviceId,
    );
  }

  Future<WorkspaceModel> createWorkspace({
    required String name,
    required String description,
    required String visibility,
    required String password,
    required String type,
    required String icon,
    required String ownerName,
    required String ownerDeviceId,
  }) async {
    // ROOT CAUSE #2 FIX: Include ownerDeviceId in workspace ID to ensure uniqueness per host session
    final workspace = WorkspaceModel(
      id: 'workspace_${ownerDeviceId}_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      description: description,
      visibility: visibility,
      password: password,
      type: type,
      icon: icon,
      ownerName: ownerName,
      ownerDeviceId: ownerDeviceId,
      createdAt: DateTime.now().toIso8601String(),
      members: [
        WorkspaceMember(
          id: ownerDeviceId,
          name: ownerName,
          deviceId: ownerDeviceId,
          role: WorkspaceRole.owner,
        )
      ],
    );
    _traceWorkspaceMutation('createWorkspace', 'add');
    _workspaces.add(workspace);
    debugPrint(
        '[DEBUG_LOG] ACTIVE_WORKSPACE_CREATED: ${workspace.id} name=${workspace.name}');
    _setActiveWorkspaceId(workspace.id, method: 'createWorkspace');
    await _appendActivity(workspace.id, 'Workspace created',
        'The workspace is now available offline');
    await _appendNotification(workspace.id, 'Workspace created',
        'The workspace is ready for nearby members');
    await save();
    return workspace;
  }

  Future<WorkspaceModel> applyWorkspaceSnapshot(
    Map<String, dynamic> payload, {
    required String localDeviceId,
    required String localMemberName,
    required WorkspaceRole localRole,
    String? overrideWorkspaceId,
    bool setActive = true,
  }) async {
    final workspaceId =
        (overrideWorkspaceId ?? payload['workspaceId'])?.toString() ?? '';
    final normalizedWorkspaceId = workspaceId.trim();
    final workspaceName = payload['workspaceName']?.toString() ??
        payload['name']?.toString() ??
        'Workspace';
    final workspaceDescription = payload['workspaceDescription']?.toString() ??
        payload['description']?.toString() ??
        '';
    final workspaceSettings = Map<String, dynamic>.from(
      payload['workspaceSettings'] as Map? ?? const {},
    );
    final visibility = payload['visibility']?.toString() ??
        workspaceSettings['visibility']?.toString() ??
        'Local';
    final password = payload['password']?.toString() ?? '';
    // Ignore payload['type']: it carries the Nearby message type string
    // ('WORKSPACE_SNAPSHOT', 'WORKSPACE_SYNC'), not the workspace category.
    final type = workspaceSettings['type']?.toString() ?? 'Connected';
    final icon = payload['icon']?.toString() ??
        workspaceSettings['icon']?.toString() ??
        'workspaces';
    final ownerName = payload['ownerName']?.toString() ??
        workspaceSettings['ownerName']?.toString() ??
        'Host';
    final ownerDeviceId = payload['ownerDeviceId']?.toString() ??
        payload['hostEndpointId']?.toString() ??
        '';
    final membersPayload = (payload['workspaceMembers'] as List<dynamic>?) ??
        (payload['members'] as List<dynamic>?) ??
        const [];
    final resourcesPayload = (payload['resources'] as List<dynamic>?) ??
        (payload['sharedResources'] as List<dynamic>?) ??
        const [];
    final foldersPayload = (payload['folders'] as List<dynamic>?) ??
        (payload['sharedFolders'] as List<dynamic>?) ??
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
    final joinRequestsPayload =
        payload['joinRequests'] as List<dynamic>? ?? const [];

    final resolvedMembers = membersPayload.map<WorkspaceMember>((entry) {
      final map = Map<String, dynamic>.from(entry as Map);
      final deviceId =
          map['deviceId']?.toString() ?? map['id']?.toString() ?? '';
      return WorkspaceMember(
        id: map['id']?.toString() ?? deviceId,
        name: map['name']?.toString() ?? 'Member',
        deviceId: deviceId,
        role: WorkspaceRole.values.firstWhere(
          (role) => role.name == map['role'],
          orElse: () => WorkspaceRole.contributor,
        ),
        permissions: (map['permissions'] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .toList(),
      );
    }).toList();

    if (localDeviceId.isNotEmpty &&
        !resolvedMembers.any((member) => member.deviceId == localDeviceId)) {
      resolvedMembers.add(
        WorkspaceMember(
          id: localDeviceId,
          name: localMemberName.isEmpty ? 'You' : localMemberName,
          deviceId: localDeviceId,
          role: localRole,
          permissions: const [
            'manageMembers',
            'resources',
            'announcements',
            'upload',
            'download'
          ],
        ),
      );
    }

    final resolvedResources = resourcesPayload
        .map((entry) =>
            ResourceItem.fromJson(Map<String, dynamic>.from(entry as Map)))
        .toList();
    final resolvedFolders = foldersPayload
        .map((entry) =>
            WorkspaceFolder.fromJson(Map<String, dynamic>.from(entry as Map)))
        .toList();
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
    final resolvedTransfers = transferPayload
        .map((entry) =>
            TransferRecord.fromJson(Map<String, dynamic>.from(entry as Map)))
        .toList();
    final resolvedJoinRequests = joinRequestsPayload
        .map((entry) =>
            JoinRequest.fromJson(Map<String, dynamic>.from(entry as Map)))
        .toList();

    final workspace = WorkspaceModel(
      id: normalizedWorkspaceId.isEmpty
          ? 'workspace_${DateTime.now().millisecondsSinceEpoch}'
          : normalizedWorkspaceId,
      name: workspaceName,
      description: workspaceDescription,
      visibility: visibility,
      password: password,
      type: type,
      icon: icon,
      ownerName: ownerName,
      ownerDeviceId: ownerDeviceId,
      createdAt: DateTime.now().toIso8601String(),
      members: resolvedMembers,
      resources: resolvedResources,
      folders: resolvedFolders,
      announcements: resolvedAnnouncements,
      inboxMessages: resolvedInbox,
      activityLogs: resolvedActivity,
      notifications: resolvedNotifications,
      transferHistory: resolvedTransfers,
      joinRequests: resolvedJoinRequests,
    );

    debugPrint(
      '[TRACE][WorkspaceService] ${_timestamp()} method=applyWorkspaceSnapshot field=_activeWorkspaceId previous=$_activeWorkspaceId new=${setActive ? workspace.id : _activeWorkspaceId} stack=${StackTrace.current}',
    );
    final existingIndex = _workspaces.indexWhere(
      (entry) =>
          entry.id == workspace.id ||
          entry.name.trim().toLowerCase() ==
              workspace.name.trim().toLowerCase(),
    );
    if (existingIndex >= 0) {
      final existing = _workspaces[existingIndex];
      // Merge lists: only replace if incoming payload provided non-empty lists.
      try {
        debugPrint(
            '[DEBUG_LOG] applyWorkspaceSnapshot incoming sizes: members=${workspace.members.length} resources=${workspace.resources.length} folders=${workspace.folders.length}');
        debugPrint(
            '[DEBUG_LOG] applyWorkspaceSnapshot existing sizes: members=${existing.members.length} resources=${existing.resources.length} folders=${existing.folders.length}');
      } catch (_) {}
      final mergedMembers =
          workspace.members.isNotEmpty ? workspace.members : existing.members;
      final mergedResources = workspace.resources.isNotEmpty
          ? workspace.resources
          : existing.resources;
      final mergedFolders =
          workspace.folders.isNotEmpty ? workspace.folders : existing.folders;
      try {
        debugPrint(
            '[DEBUG_LOG] applyWorkspaceSnapshot merged sizes: members=${mergedMembers.length} resources=${mergedResources.length} folders=${mergedFolders.length}');
      } catch (_) {}
      final mergedAnnouncements = workspace.announcements.isNotEmpty
          ? workspace.announcements
          : existing.announcements;
      final mergedInbox = workspace.inboxMessages.isNotEmpty
          ? workspace.inboxMessages
          : existing.inboxMessages;
      final mergedActivity = workspace.activityLogs.isNotEmpty
          ? workspace.activityLogs
          : existing.activityLogs;
      final mergedNotifications = workspace.notifications.isNotEmpty
          ? workspace.notifications
          : existing.notifications;
      final mergedTransfers = workspace.transferHistory.isNotEmpty
          ? workspace.transferHistory
          : existing.transferHistory;
      final mergedJoinRequests = workspace.joinRequests.isNotEmpty
          ? workspace.joinRequests
          : existing.joinRequests;

      _workspaces[existingIndex] = existing.copyWith(
        id: workspace.id,
        name: workspace.name,
        description: workspace.description,
        visibility: workspace.visibility,
        password: workspace.password,
        type: workspace.type,
        icon: workspace.icon,
        ownerName: workspace.ownerName,
        ownerDeviceId: workspace.ownerDeviceId,
        members: mergedMembers,
        resources: mergedResources,
        folders: mergedFolders,
        announcements: mergedAnnouncements,
        inboxMessages: mergedInbox,
        activityLogs: mergedActivity,
        notifications: mergedNotifications,
        transferHistory: mergedTransfers,
        joinRequests: mergedJoinRequests,
      );
    } else {
      _workspaces.add(workspace);
      debugPrint('[DEBUG_LOG] WORKSPACE_SNAPSHOT_ADDED: ${workspace.id}');
    }

    _pendingJoinRequests.removeWhere((entry) =>
        entry.workspaceId == workspace.id ||
        entry.requesterDeviceId == localDeviceId ||
        entry.requesterDeviceId == ownerDeviceId);

    if (setActive) {
      _setActiveWorkspaceId(workspace.id, method: 'applyWorkspaceSnapshot');
      debugPrint(
          '[DEBUG_LOG] ACTIVE_WORKSPACE_SET: ${workspace.id} via applyWorkspaceSnapshot');
    }

    await _appendActivity(
        workspace.id, 'Workspace synced', 'Nearby workspace state was applied');
    await _appendNotification(workspace.id, 'Workspace updated',
        'Workspace state is now synchronized');
    await save();
    notifyListeners();
    return _findWorkspace(workspace.id);
  }

  Future<WorkspaceModel> activateWorkspaceSession({
    required String workspaceId,
    required String name,
    required String description,
    required String visibility,
    required String password,
    required String type,
    required String icon,
    required String ownerName,
    required String ownerDeviceId,
    required String localDeviceId,
    required String localMemberName,
    required WorkspaceRole localRole,
    List<WorkspaceMember>? members,
    List<ResourceItem>? resources,
    List<WorkspaceFolder>? folders,
    List<AnnouncementItem>? announcements,
    List<InboxMessage>? inboxMessages,
    List<ActivityLogEntry>? activityLogs,
    List<LocalNotificationItem>? notifications,
    List<TransferRecord>? transferHistory,
    List<JoinRequest>? joinRequests,
  }) async {
    debugPrint(
      '[TRACE][WorkspaceService] ${_timestamp()} method=activateWorkspaceSession field=_activeWorkspaceId previous=$_activeWorkspaceId new=${workspaceId.trim().isNotEmpty ? workspaceId.trim() : _activeWorkspaceId} stack=${StackTrace.current}',
    );
    final normalizedWorkspaceId = workspaceId.trim();
    final existingIndex = _workspaces.indexWhere(
      (workspace) =>
          workspace.id == normalizedWorkspaceId ||
          workspace.name.trim().toLowerCase() == name.trim().toLowerCase(),
    );

    final ownerMember = WorkspaceMember(
      id: ownerDeviceId,
      name: ownerName,
      deviceId: ownerDeviceId,
      role: WorkspaceRole.owner,
      permissions: const [
        'manageMembers',
        'resources',
        'announcements',
        'upload',
        'download'
      ],
    );
    final resolvedMembers = <WorkspaceMember>[];
    if (members != null && members.isNotEmpty) {
      resolvedMembers.addAll(members);
    } else {
      resolvedMembers.add(ownerMember);
    }

    if (localDeviceId.isNotEmpty) {
      final hasLocalMember = resolvedMembers.any(
        (member) => member.deviceId == localDeviceId,
      );
      if (!hasLocalMember) {
        resolvedMembers.add(
          WorkspaceMember(
            id: localDeviceId,
            name: localMemberName.isEmpty ? 'You' : localMemberName,
            deviceId: localDeviceId,
            role: localRole,
            permissions: const [
              'manageMembers',
              'resources',
              'announcements',
              'upload',
              'download'
            ],
          ),
        );
      }
    }

    final workspace = WorkspaceModel(
      id: normalizedWorkspaceId.isEmpty
          ? 'workspace_${DateTime.now().millisecondsSinceEpoch}'
          : normalizedWorkspaceId,
      name: name,
      description: description,
      visibility: visibility,
      password: password,
      type: type,
      icon: icon,
      ownerName: ownerName,
      ownerDeviceId: ownerDeviceId,
      createdAt: DateTime.now().toIso8601String(),
      members: resolvedMembers,
      resources: resources ?? const [],
      folders: folders ?? const [],
      announcements: announcements ?? const [],
      inboxMessages: inboxMessages ?? const [],
      activityLogs: activityLogs ?? const [],
      notifications: notifications ?? const [],
      transferHistory: transferHistory ?? const [],
      joinRequests: joinRequests ?? const [],
    );

    if (existingIndex >= 0) {
      _workspaces[existingIndex] = _workspaces[existingIndex].copyWith(
        id: workspace.id,
        name: workspace.name,
        description: workspace.description,
        visibility: workspace.visibility,
        password: workspace.password,
        type: workspace.type,
        icon: workspace.icon,
        ownerName: workspace.ownerName,
        ownerDeviceId: workspace.ownerDeviceId,
        members: workspace.members,
        resources: workspace.resources,
        folders: workspace.folders,
        announcements: workspace.announcements,
        inboxMessages: workspace.inboxMessages,
        activityLogs: workspace.activityLogs,
        notifications: workspace.notifications,
        transferHistory: workspace.transferHistory,
        joinRequests: workspace.joinRequests,
      );
    } else {
      _traceWorkspaceMutation('activateWorkspaceSession', 'add');
      _workspaces.add(workspace);
    }

    _setActiveWorkspaceId(workspace.id, method: 'activateWorkspaceSession');
    await _appendActivity(workspace.id, 'Workspace ready',
        'The workspace is ready for nearby collaboration');
    await _appendNotification(workspace.id, 'Workspace ready',
        'Members can now enter the shared workspace');
    await save();
    notifyListeners();
    return _findWorkspace(workspace.id);
  }

  Future<void> updateWorkspace({
    required String workspaceId,
    String? name,
    String? description,
    String? visibility,
    String? password,
    String? type,
    String? icon,
  }) async {
    final index =
        _workspaces.indexWhere((workspace) => workspace.id == workspaceId);
    if (index < 0) return;
    final workspace = _workspaces[index];
    _workspaces[index] = workspace.copyWith(
      name: name ?? workspace.name,
      description: description ?? workspace.description,
      visibility: visibility ?? workspace.visibility,
      password: password ?? workspace.password,
      type: type ?? workspace.type,
      icon: icon ?? workspace.icon,
    );
    await _appendActivity(
        workspaceId, 'Workspace updated', 'Workspace details were updated');
    await save();
  }

  Future<void> updateWorkspaceMembers(
    String workspaceId,
    List<WorkspaceMember> members,
  ) async {
    final index =
        _workspaces.indexWhere((workspace) => workspace.id == workspaceId);
    if (index < 0) return;
    final workspace = _workspaces[index];
    _workspaces[index] = workspace.copyWith(members: members);
    await _appendActivity(
        workspaceId, 'Members updated', 'Workspace members were updated');
    await save();
    notifyListeners();
  }

  Future<void> deleteWorkspace(String workspaceId) async {
    debugPrint(
      '[TRACE][WorkspaceService] ${_timestamp()} method=removeWorkspace field=_activeWorkspaceId previous=$_activeWorkspaceId new=$_activeWorkspaceId stack=${StackTrace.current}',
    );
    _traceWorkspaceMutation('removeWorkspace', 'removeWhere');
    _workspaces.removeWhere((workspace) => workspace.id == workspaceId);
    debugPrint('[DEBUG_LOG] WORKSPACE_DELETED: $workspaceId');
    if (_activeWorkspaceId == workspaceId) {
      _setActiveWorkspaceId(
        _workspaces.isNotEmpty ? _workspaces.first.id : null,
        method: 'removeWorkspace',
      );
    }
    _pendingJoinRequests
        .removeWhere((request) => request.workspaceId == workspaceId);
    await save();
  }

  Future<void> setActiveWorkspace(String workspaceId) async {
    debugPrint(
      '[TRACE][WorkspaceService] ${_timestamp()} method=setActiveWorkspace field=_activeWorkspaceId previous=$_activeWorkspaceId new=$workspaceId stack=${StackTrace.current}',
    );
    final normalized = workspaceId.trim();
    if (normalized.isEmpty) return;
    final match = _workspaces.firstWhere(
      (workspace) =>
          workspace.id == normalized ||
          workspace.name.trim().toLowerCase() == normalized.toLowerCase(),
      orElse: () => WorkspaceModel(
        id: '',
        name: '',
        description: '',
        visibility: 'Local',
        password: '',
        type: 'Personal',
        icon: 'workspaces',
        ownerName: '',
        ownerDeviceId: '',
        createdAt: DateTime.now().toIso8601String(),
      ),
    );
    if (match.id.isNotEmpty) {
      _setActiveWorkspaceId(match.id, method: 'setActiveWorkspace');
      await save();
      notifyListeners();
    }
  }

  Future<WorkspaceModel> addResource({
    required String workspaceId,
    required String name,
    required String kind,
    required int sizeBytes,
    required String path,
    String? folderId,
  }) async {
    final workspace = _findWorkspace(workspaceId);
    final resource = ResourceItem(
      id: 'resource_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      kind: kind,
      sizeBytes: sizeBytes,
      path: path,
      folderId: folderId,
      createdAt: DateTime.now().toIso8601String(),
    );
    final updatedResources = [...workspace.resources, resource];
    _workspaces[_workspaces.indexWhere((entry) => entry.id == workspaceId)] =
        workspace.copyWith(resources: updatedResources);
    await _appendActivity(workspaceId, 'Resource uploaded', name);
    await _appendNotification(workspaceId, 'Resource uploaded', name);
    await save();
    return _findWorkspace(workspaceId);
  }

  Future<void> renameResource(
      String workspaceId, String resourceId, String newName) async {
    final workspace = _findWorkspace(workspaceId);
    final resources = workspace.resources.map((resource) {
      if (resource.id == resourceId) {
        return ResourceItem(
          id: resource.id,
          name: newName,
          kind: resource.kind,
          sizeBytes: resource.sizeBytes,
          path: resource.path,
          folderId: resource.folderId,
          createdAt: resource.createdAt,
        );
      }
      return resource;
    }).toList();
    _workspaces[_workspaces.indexWhere((entry) => entry.id == workspaceId)] =
        workspace.copyWith(resources: resources);
    await _appendActivity(workspaceId, 'Resource renamed', newName);
    await save();
  }

  Future<void> deleteResource(String workspaceId, String resourceId) async {
    final workspace = _findWorkspace(workspaceId);
    final resources = workspace.resources
        .where((resource) => resource.id != resourceId)
        .toList();
    _workspaces[_workspaces.indexWhere((entry) => entry.id == workspaceId)] =
        workspace.copyWith(resources: resources);
    await _appendActivity(workspaceId, 'Resource deleted', resourceId);
    await save();
  }

  Future<void> addAnnouncement(
      String workspaceId, String title, String body) async {
    final workspace = _findWorkspace(workspaceId);
    final announcement = AnnouncementItem(
      id: 'announcement_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      body: body,
      createdAt: DateTime.now().toIso8601String(),
    );
    final announcements = [...workspace.announcements, announcement];
    _workspaces[_workspaces.indexWhere((entry) => entry.id == workspaceId)] =
        workspace.copyWith(announcements: announcements);
    await _appendActivity(workspaceId, 'Announcement added', title);
    await _appendNotification(workspaceId, 'Announcement added', title);
    await save();
  }

  Future<JoinRequest> addJoinRequest({
    required String workspaceId,
    required String requesterName,
    required String requesterDeviceId,
    required List<String> requestedRights,
  }) async {
    final workspace = _findWorkspace(workspaceId);
    final existingPending = workspace.joinRequests
        .where((entry) =>
            entry.requesterDeviceId == requesterDeviceId &&
            entry.status == 'pending')
        .toList();
    if (existingPending.isNotEmpty) {
      return existingPending.first;
    }

    final request = JoinRequest(
      id: 'join_${DateTime.now().millisecondsSinceEpoch}',
      workspaceId: workspaceId,
      requesterName: requesterName,
      requesterDeviceId: requesterDeviceId,
      requestedRights: requestedRights,
      status: 'pending',
      createdAt: DateTime.now().toIso8601String(),
    );
    _pendingJoinRequests.add(request);
    final joinRequests = [...workspace.joinRequests, request];
    _workspaces[_workspaces.indexWhere((entry) => entry.id == workspaceId)] =
        workspace.copyWith(joinRequests: joinRequests);
    await _appendActivity(
        workspaceId, 'Join request', '$requesterName requested access');
    await _appendNotification(
        workspaceId, 'Join requested', '$requesterName wants to join');
    await save();
    return request;
  }

  Future<void> acceptJoinRequest(String workspaceId, String requestId) async {
    final workspace = _findWorkspace(workspaceId);
    final request = workspace.joinRequests.firstWhere(
        (entry) => entry.id == requestId,
        orElse: () => JoinRequest(
            id: '',
            workspaceId: workspaceId,
            requesterName: '',
            requesterDeviceId: '',
            requestedRights: const [],
            status: 'rejected',
            createdAt: ''));
    if (request.id.isEmpty) return;
    final joinRequests = workspace.joinRequests.map((entry) {
      if (entry.id == requestId) {
        return JoinRequest(
          id: entry.id,
          workspaceId: entry.workspaceId,
          requesterName: entry.requesterName,
          requesterDeviceId: entry.requesterDeviceId,
          requestedRights: entry.requestedRights,
          status: 'accepted',
          createdAt: entry.createdAt,
        );
      }
      return entry;
    }).toList();
    final existingMember = workspace.members.any(
      (member) => member.deviceId == request.requesterDeviceId,
    );
    final members = existingMember
        ? workspace.members
        : [
            ...workspace.members,
            WorkspaceMember(
              id: request.requesterDeviceId,
              name: request.requesterName,
              deviceId: request.requesterDeviceId,
              role: WorkspaceRole.contributor,
            )
          ];
    _workspaces[_workspaces.indexWhere((entry) => entry.id == workspaceId)] =
        workspace.copyWith(joinRequests: joinRequests, members: members);
    _pendingJoinRequests.removeWhere((entry) => entry.id == requestId);
    await _appendActivity(workspaceId, 'Join accepted', request.requesterName);
    await _appendNotification(workspaceId, 'Join approved',
        '${request.requesterName} is now a member');
    await save();
    notifyListeners();
  }

  Future<void> rejectJoinRequest(String workspaceId, String requestId) async {
    final workspace = _findWorkspace(workspaceId);
    final joinRequests = workspace.joinRequests.map((entry) {
      if (entry.id == requestId) {
        return JoinRequest(
          id: entry.id,
          workspaceId: entry.workspaceId,
          requesterName: entry.requesterName,
          requesterDeviceId: entry.requesterDeviceId,
          requestedRights: entry.requestedRights,
          status: 'rejected',
          createdAt: entry.createdAt,
        );
      }
      return entry;
    }).toList();
    _workspaces[_workspaces.indexWhere((entry) => entry.id == workspaceId)] =
        workspace.copyWith(joinRequests: joinRequests);
    _pendingJoinRequests.removeWhere((entry) => entry.id == requestId);
    await _appendActivity(workspaceId, 'Join rejected', requestId);
    await save();
  }

  Future<void> blockUser(String workspaceId, String deviceId) async {
    final workspace = _findWorkspace(workspaceId);
    final members = workspace.members
        .where((member) => member.deviceId != deviceId)
        .toList();
    _workspaces[_workspaces.indexWhere((entry) => entry.id == workspaceId)] =
        workspace.copyWith(members: members);
    await _appendActivity(workspaceId, 'User blocked', deviceId);
    await save();
  }

  Future<void> updateMemberRole(
      String workspaceId, String memberId, WorkspaceRole role) async {
    final workspace = _findWorkspace(workspaceId);
    final members = workspace.members.map((member) {
      if (member.id == memberId) {
        return WorkspaceMember(
            id: member.id,
            name: member.name,
            deviceId: member.deviceId,
            role: role);
      }
      return member;
    }).toList();
    _workspaces[_workspaces.indexWhere((entry) => entry.id == workspaceId)] =
        workspace.copyWith(members: members);
    await _appendActivity(workspaceId, 'Role updated', role.name);
    await save();
    notifyListeners();
  }

  Future<WorkspaceFolder> createFolder({
    required String workspaceId,
    required String name,
    String parentId = '',
  }) async {
    final workspace = _findWorkspace(workspaceId);
    final folder = WorkspaceFolder(
      id: 'folder_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      parentId: parentId,
      createdAt: DateTime.now().toIso8601String(),
    );
    final folders = [...workspace.folders, folder];
    _workspaces[_workspaces.indexWhere((entry) => entry.id == workspaceId)] =
        workspace.copyWith(folders: folders);
    await _appendActivity(workspaceId, 'Folder created', name);
    await save();
    return folder;
  }

  Future<void> addInboxMessage({
    required String workspaceId,
    required String senderName,
    required String subject,
    required String body,
  }) async {
    final workspace = _findWorkspace(workspaceId);
    final message = InboxMessage(
      id: 'message_${DateTime.now().millisecondsSinceEpoch}',
      senderName: senderName,
      subject: subject,
      body: body,
      createdAt: DateTime.now().toIso8601String(),
    );
    final inboxMessages = [...workspace.inboxMessages, message];
    _workspaces[_workspaces.indexWhere((entry) => entry.id == workspaceId)] =
        workspace.copyWith(inboxMessages: inboxMessages);
    await _appendActivity(workspaceId, 'New message', subject);
    await _appendNotification(workspaceId, 'New inbox message', subject);
    await save();
  }

  Future<void> markInboxMessageRead(
      String workspaceId, String messageId) async {
    final workspace = _findWorkspace(workspaceId);
    final inboxMessages = workspace.inboxMessages.map((message) {
      if (message.id == messageId) {
        return InboxMessage(
          id: message.id,
          senderName: message.senderName,
          subject: message.subject,
          body: message.body,
          createdAt: message.createdAt,
          read: true,
        );
      }
      return message;
    }).toList();
    _workspaces[_workspaces.indexWhere((entry) => entry.id == workspaceId)] =
        workspace.copyWith(inboxMessages: inboxMessages);
    await save();
  }

  Future<TransferRecord> enqueueTransfer({
    required String workspaceId,
    required String fileName,
    required String direction,
    required int totalBytes,
  }) async {
    final transfer = TransferRecord(
      id: 'transfer_${DateTime.now().millisecondsSinceEpoch}',
      fileName: fileName,
      direction: direction,
      status: 'queued',
      totalBytes: totalBytes,
      transferredBytes: 0,
      startedAt: DateTime.now().toIso8601String(),
    );
    final workspace = _findWorkspace(workspaceId);
    final transferHistory = [...workspace.transferHistory, transfer];
    _workspaces[_workspaces.indexWhere((entry) => entry.id == workspaceId)] =
        workspace.copyWith(transferHistory: transferHistory);
    await save();
    return transfer;
  }

  Future<void> updateTransferProgress(
      String workspaceId, String transferId, int transferredBytes,
      {String? status}) async {
    final workspace = _findWorkspace(workspaceId);
    final transferHistory = workspace.transferHistory.map((entry) {
      if (entry.id == transferId) {
        return TransferRecord(
          id: entry.id,
          fileName: entry.fileName,
          direction: entry.direction,
          status: status ?? entry.status,
          totalBytes: entry.totalBytes,
          transferredBytes: transferredBytes,
          startedAt: entry.startedAt,
          attempts: entry.attempts,
          errorMessage: entry.errorMessage,
        );
      }
      return entry;
    }).toList();
    _workspaces[_workspaces.indexWhere((entry) => entry.id == workspaceId)] =
        workspace.copyWith(transferHistory: transferHistory);
    await save();
  }

  Future<void> completeTransfer(String workspaceId, String transferId) async {
    final workspace = _findWorkspace(workspaceId);
    final transferHistory = workspace.transferHistory.map((entry) {
      if (entry.id == transferId) {
        return TransferRecord(
          id: entry.id,
          fileName: entry.fileName,
          direction: entry.direction,
          status: 'completed',
          totalBytes: entry.totalBytes,
          transferredBytes: entry.totalBytes,
          startedAt: entry.startedAt,
          attempts: entry.attempts + 1,
          errorMessage: entry.errorMessage,
        );
      }
      return entry;
    }).toList();
    _workspaces[_workspaces.indexWhere((entry) => entry.id == workspaceId)] =
        workspace.copyWith(transferHistory: transferHistory);
    await _appendActivity(workspaceId, 'Transfer completed', transferId);
    await save();
  }

  Future<void> failTransfer(
      String workspaceId, String transferId, String error) async {
    final workspace = _findWorkspace(workspaceId);
    final transferHistory = workspace.transferHistory.map((entry) {
      if (entry.id == transferId) {
        return TransferRecord(
          id: entry.id,
          fileName: entry.fileName,
          direction: entry.direction,
          status: 'failed',
          totalBytes: entry.totalBytes,
          transferredBytes: entry.transferredBytes,
          startedAt: entry.startedAt,
          attempts: entry.attempts + 1,
          errorMessage: error,
        );
      }
      return entry;
    }).toList();
    _workspaces[_workspaces.indexWhere((entry) => entry.id == workspaceId)] =
        workspace.copyWith(transferHistory: transferHistory);
    await _appendActivity(workspaceId, 'Transfer failed', error);
    await save();
  }

  Future<void> _appendActivity(
      String workspaceId, String title, String detail) async {
    final workspace = _findWorkspace(workspaceId);
    final activityLogs = [
      ActivityLogEntry(
        id: 'activity_${DateTime.now().millisecondsSinceEpoch}',
        title: title,
        detail: detail,
        createdAt: DateTime.now().toIso8601String(),
      ),
      ...workspace.activityLogs,
    ];
    _workspaces[_workspaces.indexWhere((entry) => entry.id == workspaceId)] =
        workspace.copyWith(activityLogs: activityLogs.take(20).toList());
  }

  Future<void> _appendNotification(
      String workspaceId, String title, String message) async {
    final workspace = _findWorkspace(workspaceId);
    final notifications = [
      LocalNotificationItem(
        id: 'notification_${DateTime.now().millisecondsSinceEpoch}',
        title: title,
        message: message,
        createdAt: DateTime.now().toIso8601String(),
      ),
      ...workspace.notifications,
    ];
    _workspaces[_workspaces.indexWhere((entry) => entry.id == workspaceId)] =
        workspace.copyWith(notifications: notifications.take(20).toList());
  }

  List<ResourceItem> searchResources(String workspaceId, String query) {
    final workspace = _findWorkspace(workspaceId);
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return workspace.resources;
    return workspace.resources.where((resource) {
      return resource.name.toLowerCase().contains(normalized) ||
          resource.kind.toLowerCase().contains(normalized);
    }).toList();
  }

  List<ActivityLogEntry> searchActivity(String workspaceId, String query) {
    final workspace = _findWorkspace(workspaceId);
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return workspace.activityLogs;
    return workspace.activityLogs.where((entry) {
      return entry.title.toLowerCase().contains(normalized) ||
          entry.detail.toLowerCase().contains(normalized);
    }).toList();
  }

  List<WorkspaceModel> searchWorkspaces(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return _workspaces;
    return _workspaces.where((workspace) {
      return workspace.name.toLowerCase().contains(normalized) ||
          workspace.description.toLowerCase().contains(normalized) ||
          workspace.type.toLowerCase().contains(normalized);
    }).toList();
  }

  bool canPerform(
      String workspaceId, String deviceId, WorkspacePermission permission) {
    final workspace = _findWorkspace(workspaceId);
    final member =
        workspace.members.where((entry) => entry.deviceId == deviceId).toList();
    if (member.isEmpty) return false;
    final role = member.first.role;
    switch (permission) {
      case WorkspacePermission.manageMembers:
        return role == WorkspaceRole.owner || role == WorkspaceRole.admin;
      case WorkspacePermission.resources:
        return role != WorkspaceRole.viewer;
      case WorkspacePermission.announcements:
        return role == WorkspaceRole.owner ||
            role == WorkspaceRole.admin ||
            role == WorkspaceRole.contributor;
      case WorkspacePermission.upload:
        return role == WorkspaceRole.owner ||
            role == WorkspaceRole.admin ||
            role == WorkspaceRole.contributor;
      case WorkspacePermission.download:
        return role != WorkspaceRole.viewer;
    }
  }

  WorkspaceModel _findWorkspace(String workspaceId) {
    final normalized = workspaceId.trim();
    var index =
        _workspaces.indexWhere((workspace) => workspace.id == normalized);
    if (index >= 0) return _workspaces[index];

    // Fallback: try matching by workspace name (case-insensitive)
    index = _workspaces.indexWhere((workspace) =>
        workspace.name.trim().toLowerCase() == normalized.toLowerCase());
    if (index >= 0) return _workspaces[index];

    throw StateError('Workspace not found');
  }
}
