import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexus_bridge/services/nearby_service.dart';
import 'package:nexus_bridge/services/offline_session_service.dart';
import 'package:nexus_bridge/services/workspace_service.dart';
import 'package:nexus_bridge/services/workspace_session_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('activates a workspace from approval payload and persists the session',
      () async {
    SharedPreferences.setMockInitialValues({});

    final workspaceService = WorkspaceService();
    final sessionService = OfflineSessionService();
    final manager = WorkspaceSessionManager(
      nearbyService: NearbyService(),
      workspaceService: workspaceService,
      offlineSessionService: sessionService,
    );

    await workspaceService.load();
    await sessionService.load();
    await manager.load();

    final payload = {
      'workspaceId': 'ws-approval-1',
      'workspaceName': 'Approval Studio',
      'workspaceDescription': 'Joined after approval',
      'ownerName': 'Host',
      'ownerDeviceId': 'host-1',
      'workspaceMembers': [
        {
          'id': 'host-1',
          'name': 'Host',
          'deviceId': 'host-1',
          'role': 'owner',
        },
        {
          'id': 'device-2',
          'name': 'Client',
          'deviceId': 'device-2',
          'role': 'contributor',
        },
      ],
      'members': [
        {
          'id': 'host-1',
          'name': 'Host',
          'deviceId': 'host-1',
          'role': 'owner',
        },
        {
          'id': 'device-2',
          'name': 'Client',
          'deviceId': 'device-2',
          'role': 'contributor',
        },
      ],
      'resources': const [],
      'folders': const [],
      'announcements': const [],
      'inboxMessages': const [],
      'activityLogs': const [],
      'notifications': const [],
      'transferHistory': const [],
      'joinRequests': const [],
      'workspaceSettings': {
        'visibility': 'Local',
        'type': 'Connected',
        'icon': 'workspaces',
      },
      'grantedRights': ['read', 'write'],
      'workspaceRole': 'contributor',
    };

    final activated = await manager.activateWorkspaceFromPayload(
      payload,
      endpointId: 'host-1',
      localDeviceId: 'device-2',
      localMemberName: 'Client',
      localRole: WorkspaceRole.contributor,
    );

    expect(activated.name, 'Approval Studio');
    expect(manager.currentWorkspace?.id, 'ws-approval-1');
    expect(workspaceService.activeWorkspace?.id, 'ws-approval-1');
    expect(sessionService.sessionActive, isTrue);
    expect(sessionService.workspaceId, 'ws-approval-1');
    expect(manager.connectionState, 'connected');
  });

  test('activates a workspace from sync payload and persists the session',
      () async {
    SharedPreferences.setMockInitialValues({});

    final workspaceService = WorkspaceService();
    final sessionService = OfflineSessionService();
    final manager = WorkspaceSessionManager(
      nearbyService: NearbyService(),
      workspaceService: workspaceService,
      offlineSessionService: sessionService,
    );

    await workspaceService.load();
    await sessionService.load();
    await manager.load();

    final payload = {
      'workspaceId': 'ws-sync-1',
      'workspaceName': 'Shared Studio',
      'hostEndpointId': 'host-1',
      'workspaceMembers': [
        {
          'id': 'host-1',
          'name': 'Host',
          'deviceId': 'host-1',
          'role': 'owner',
        },
        {
          'id': 'device-2',
          'name': 'Client',
          'deviceId': 'device-2',
          'role': 'contributor',
        },
      ],
      'roles': {
        'host-1': 'owner',
        'device-2': 'contributor',
      },
      'permissions': {
        'host-1': 'manageMembers,resources,announcements,upload,download',
        'device-2': 'resources,announcements,upload,download',
      },
      'sharedFolders': [
        {
          'id': 'folder-1',
          'name': 'Design',
          'parentId': '',
          'createdAt': DateTime.now().toIso8601String(),
        },
      ],
      'sharedResources': [
        {
          'id': 'res-1',
          'name': 'Mock File',
          'kind': 'Documents',
          'sizeBytes': 1024,
          'path': '/tmp/mock',
          'createdAt': DateTime.now().toIso8601String(),
        },
      ],
      'workspaceSettings': {
        'visibility': 'Local',
        'type': 'Connected',
        'icon': 'workspaces',
      },
      'workspaceRole': 'contributor',
    };

    await manager.applyWorkspaceSync(payload, endpointId: 'host-1');

    expect(manager.currentWorkspace?.name, 'Shared Studio');
    expect(manager.connectedHost, 'host-1');
    expect(manager.currentRole, 'contributor');
    expect(manager.workspaceMembers.length, 2);
    expect(manager.connectionState, 'connected');
    expect(workspaceService.activeWorkspace?.id, 'ws-sync-1');
  });

  test(
      'keeps the session manager aligned with workspace service member changes',
      () async {
    SharedPreferences.setMockInitialValues({});

    final workspaceService = WorkspaceService();
    final sessionService = OfflineSessionService();
    final manager = WorkspaceSessionManager(
      nearbyService: NearbyService(),
      workspaceService: workspaceService,
      offlineSessionService: sessionService,
    );

    await workspaceService.load();
    await sessionService.load();
    await manager.load();

    final workspace = await workspaceService.createWorkspace(
      name: 'Aligned Workspace',
      description: 'test',
      visibility: 'Local',
      password: '',
      type: 'Connected',
      icon: 'workspaces',
      ownerName: 'Host',
      ownerDeviceId: 'host-1',
    );

    await workspaceService.updateWorkspaceMembers(
      workspace.id,
      [
        WorkspaceMember(
          id: 'host-1',
          name: 'Host',
          deviceId: 'host-1',
          role: WorkspaceRole.owner,
        ),
        WorkspaceMember(
          id: 'device-2',
          name: 'Client',
          deviceId: 'device-2',
          role: WorkspaceRole.contributor,
        ),
      ],
    );

    expect(workspaceService.activeWorkspace?.members.length, 2);
    expect(manager.currentWorkspace?.members.length, 2);
    expect(manager.currentWorkspace, same(workspaceService.activeWorkspace));
  });
}
