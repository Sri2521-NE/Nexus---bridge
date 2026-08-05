import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexus_bridge/services/workspace_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('creates and persists a workspace with pending join requests', () async {
    SharedPreferences.setMockInitialValues({});
    final service = WorkspaceService();

    await service.load();
    final workspace = await service.createWorkspace(
      name: 'Test Workspace',
      description: 'Offline test workspace',
      visibility: 'Local',
      password: 'secret',
      type: 'Project',
      icon: 'workspaces',
      ownerName: 'Me',
      ownerDeviceId: 'device-1',
    );

    expect(workspace.name, 'Test Workspace');
    expect(service.workspaces.length, 1);

    await service.addJoinRequest(
      workspaceId: workspace.id,
      requesterName: 'Ava',
      requesterDeviceId: 'device-2',
      requestedRights: ['read', 'write'],
    );

    expect(service.pendingJoinRequests.length, 1);
    expect(service.pendingJoinRequests.first.requesterName, 'Ava');

    await service.save();
    final reloaded = WorkspaceService();
    await reloaded.load();
    expect(reloaded.workspaces.first.name, 'Test Workspace');
    expect(reloaded.pendingJoinRequests.length, 1);
  });

  test('activates a workspace by name and keeps the dashboard in sync',
      () async {
    SharedPreferences.setMockInitialValues({});
    final service = WorkspaceService();

    await service.load();
    await service.createWorkspace(
      name: 'Studio Hub',
      description: 'Offline design workspace',
      visibility: 'Local',
      password: '',
      type: 'Creative',
      icon: 'workspaces',
      ownerName: 'Me',
      ownerDeviceId: 'device-1',
    );

    await service.setActiveWorkspace('Studio Hub');

    expect(service.activeWorkspace?.name, 'Studio Hub');
  });

  test('tracks join approvals and transfer history for the active workspace',
      () async {
    SharedPreferences.setMockInitialValues({});
    final service = WorkspaceService();

    await service.load();
    final workspace = await service.createWorkspace(
      name: 'Studio Hub',
      description: 'Offline design workspace',
      visibility: 'Local',
      password: '',
      type: 'Creative',
      icon: 'workspaces',
      ownerName: 'Me',
      ownerDeviceId: 'device-1',
    );

    await service.addJoinRequest(
      workspaceId: workspace.id,
      requesterName: 'Ava',
      requesterDeviceId: 'device-2',
      requestedRights: ['read', 'write'],
    );

    final request = service.pendingJoinRequests.first;
    await service.acceptJoinRequest(workspace.id, request.id);

    final updatedWorkspace = service.workspaces.firstWhere(
      (entry) => entry.id == workspace.id,
    );
    expect(updatedWorkspace.joinRequests.first.status, 'accepted');
    expect(
        updatedWorkspace.members.any((member) => member.deviceId == 'device-2'),
        isTrue);
  });

  test('activates a joined workspace and syncs member metadata', () async {
    SharedPreferences.setMockInitialValues({});
    final service = WorkspaceService();

    await service.load();
    final workspace = await service.activateWorkspaceSession(
      workspaceId: 'workspace_sync_test',
      name: 'Sync Workspace',
      description: 'Synchronized after approval',
      visibility: 'Local',
      password: '',
      type: 'Connected',
      icon: 'workspaces',
      ownerName: 'Host',
      ownerDeviceId: 'device-1',
      localDeviceId: 'device-2',
      localMemberName: 'Client',
      localRole: WorkspaceRole.contributor,
      members: [
        WorkspaceMember(
          id: 'device-1',
          name: 'Host',
          deviceId: 'device-1',
          role: WorkspaceRole.owner,
        ),
        WorkspaceMember(
          id: 'device-2',
          name: 'Client',
          deviceId: 'device-2',
          role: WorkspaceRole.contributor,
        ),
      ],
      folders: [
        WorkspaceFolder(
          id: 'folder_1',
          name: 'Shared',
          parentId: '',
          createdAt: DateTime.now().toIso8601String(),
        ),
      ],
      resources: const [],
      announcements: const [],
      inboxMessages: const [],
      activityLogs: const [],
      notifications: const [],
      transferHistory: const [],
      joinRequests: const [],
    );

    expect(workspace.name, 'Sync Workspace');
    expect(service.activeWorkspace?.id, workspace.id);
    expect(service.activeWorkspace?.members.length, 2);
    expect(service.activeWorkspace?.folders.length, 1);
  });

  test('applies an approval snapshot as the active workspace', () async {
    SharedPreferences.setMockInitialValues({});
    final service = WorkspaceService();

    await service.load();

    final applied = await service.applyWorkspaceSnapshot(
      {
        'workspaceId': 'approved-workspace',
        'workspaceName': 'Approved Workspace',
        'workspaceDescription': 'Joined after approval',
        'ownerName': 'Host',
        'ownerDeviceId': 'device-1',
        'workspaceMembers': [
          {
            'id': 'device-1',
            'name': 'Host',
            'deviceId': 'device-1',
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
            'id': 'device-1',
            'name': 'Host',
            'deviceId': 'device-1',
            'role': 'owner',
          },
          {
            'id': 'device-2',
            'name': 'Client',
            'deviceId': 'device-2',
            'role': 'contributor',
          },
        ],
      },
      localDeviceId: 'device-2',
      localMemberName: 'Client',
      localRole: WorkspaceRole.contributor,
      overrideWorkspaceId: 'approved-workspace',
    );

    expect(applied.name, 'Approved Workspace');
    expect(service.activeWorkspace?.id, 'approved-workspace');
    expect(service.activeWorkspace?.members.length, 2);
  });
}
