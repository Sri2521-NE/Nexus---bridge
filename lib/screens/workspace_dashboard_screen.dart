import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/nearby_service.dart';
import '../services/workspace_session_manager.dart';
import '../services/workspace_service.dart';
import '../services/connection_service.dart';

class WorkspaceDashboardScreen extends StatefulWidget {
  final String workspaceName;
  final String workspaceType;
  final String ownerName;
  final int members;
  final int resources;
  final bool isProtected;

  const WorkspaceDashboardScreen({
    super.key,
    required this.workspaceName,
    required this.workspaceType,
    required this.ownerName,
    required this.members,
    required this.resources,
    required this.isProtected,
  });

  @override
  State<WorkspaceDashboardScreen> createState() =>
      _WorkspaceDashboardScreenState();
}

class _WorkspaceDashboardScreenState extends State<WorkspaceDashboardScreen> {
  int _selectedIndex = 0;
  String _searchQuery = '';
  String? _selectedFolderId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WorkspaceService>().setActiveWorkspace(widget.workspaceName);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <String>[
      'Requests',
      'Resources',
      'Members',
      'Announcements',
      'Activity',
      'Settings'
    ];
    final workspaceService = context.watch<WorkspaceService>();
    final workspace = workspaceService.activeWorkspace ??
        workspaceService.workspaces.firstWhere(
          (entry) => entry.name == widget.workspaceName,
          orElse: () => WorkspaceModel(
            id: widget.workspaceName,
            name: widget.workspaceName,
            description: 'Offline workspace',
            visibility: 'Local',
            password: '',
            type: widget.workspaceType,
            icon: 'workspaces',
            ownerName: widget.ownerName,
            ownerDeviceId: '',
            createdAt: DateTime.now().toIso8601String(),
          ),
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(workspace.name),
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF121B2D),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF22304A)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                            colors: [Color(0xFF00D9FF), Color(0xFF7C4DFF)]),
                      ),
                      child: const Icon(Icons.workspaces_rounded,
                          color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(workspace.name,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                          const SizedBox(height: 2),
                          Text(
                              '${workspace.type} • ${workspace.members.length} members • ${workspace.resources.length} resources',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: tabs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final selected = index == _selectedIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF17304C)
                            : const Color(0xFF121B2D),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: selected
                                ? const Color(0xFF00D9FF)
                                : const Color(0xFF22304A)),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => setState(() => _selectedIndex = index),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Center(
                                child: Text(tabs[index],
                                    style: TextStyle(
                                        color: selected
                                            ? const Color(0xFF00D9FF)
                                            : Colors.white70,
                                        fontWeight: FontWeight.w600))),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildTabContent(tabs[_selectedIndex]),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF07111F),
        indicatorColor: const Color(0xFF17304C),
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.mail_outline_rounded), label: 'Requests'),
          NavigationDestination(
              icon: Icon(Icons.folder_open_rounded), label: 'Resources'),
          NavigationDestination(
              icon: Icon(Icons.people_alt_rounded), label: 'Members'),
          NavigationDestination(
              icon: Icon(Icons.campaign_rounded), label: 'Announcements'),
          NavigationDestination(
              icon: Icon(Icons.insights_rounded), label: 'Activity'),
          NavigationDestination(
              icon: Icon(Icons.settings_rounded), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildTabContent(String label) {
    return Consumer<WorkspaceService>(
      builder: (context, workspaceService, _) {
        final workspace = workspaceService.activeWorkspace ??
            workspaceService.workspaces.firstWhere(
              (entry) => entry.name == widget.workspaceName,
              orElse: () => WorkspaceModel(
                id: widget.workspaceName,
                name: widget.workspaceName,
                description: 'Offline workspace',
                visibility: 'Local',
                password: '',
                type: widget.workspaceType,
                icon: 'workspaces',
                ownerName: widget.ownerName,
                ownerDeviceId: '',
                createdAt: DateTime.now().toIso8601String(),
              ),
            );
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: Container(
            key: ValueKey(label),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF121B2D),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF22304A)),
            ),
            child: _buildTabBody(label, workspace),
          ),
        );
      },
    );
  }

  Widget _buildTabBody(String label, WorkspaceModel workspace) {
    switch (label) {
      case 'Requests':
        final pendingRequests = workspace.joinRequests
            .where((request) => request.status == 'pending')
            .toList();
        if (pendingRequests.isEmpty) {
          return const Center(
            child: Text('No pending join requests.',
                style: TextStyle(color: Colors.white70)),
          );
        }
        return ListView.separated(
          itemCount: pendingRequests.length,
          separatorBuilder: (_, __) => const Divider(color: Color(0xFF22304A)),
          itemBuilder: (context, index) {
            final request = pendingRequests[index];
            return ListTile(
              title: Text(request.requesterName),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Device: ${request.requesterDeviceId}'),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: request.requestedRights
                        .map((right) => Chip(
                              label: Text(right),
                              backgroundColor: const Color(0xFF17304C),
                              labelStyle:
                                  const TextStyle(color: Colors.white70),
                            ))
                        .toList(),
                  ),
                ],
              ),
              trailing: Wrap(
                spacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      final nearby = context.read<NearbyService>();
                      final workspaceService = context.read<WorkspaceService>();
                      final sessionManager =
                          context.read<WorkspaceSessionManager>();
                      final connectionService =
                          context.read<ConnectionService>();
                      final messenger = ScaffoldMessenger.of(context);

                      // ROOT CAUSE #3 FIX: Validate that current device is workspace owner
                      final currentDeviceId =
                          connectionService.deviceId ?? 'local-device';
                      if (workspace.ownerDeviceId != currentDeviceId) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content:
                                Text('Error: You are not the workspace owner'),
                          ),
                        );
                        return;
                      }

                      final availableRights = request.requestedRights.isEmpty
                          ? ['read']
                          : request.requestedRights;
                      final selectedRights = <String>{...availableRights};
                      final shouldApprove = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) {
                          return AlertDialog(
                            title: const Text('Grant workspace permissions'),
                            content: StatefulBuilder(
                              builder: (context, setDialogState) {
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: availableRights
                                      .map(
                                        (right) => CheckboxListTile(
                                          dense: true,
                                          title: Text(right),
                                          value: selectedRights.contains(right),
                                          onChanged: (value) {
                                            setDialogState(() {
                                              if (value == true) {
                                                selectedRights.add(right);
                                              } else {
                                                selectedRights.remove(right);
                                              }
                                            });
                                          },
                                        ),
                                      )
                                      .toList(),
                                );
                              },
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, true),
                                child: const Text('Approve'),
                              ),
                            ],
                          );
                        },
                      );
                      if (shouldApprove != true) return;

                      final grantedRights = selectedRights.toList()..sort();
                      final clientEndpointId =
                          sessionManager.endpointIdForClientDeviceId(
                              request.requesterDeviceId);
                      if (clientEndpointId == null) {
                        messenger.showSnackBar(
                          const SnackBar(
                              content: Text('Client is no longer connected')),
                        );
                        return;
                      }

                      // Accept the request
                      await workspaceService.acceptJoinRequest(
                          workspace.id, request.id);

                      final approvedPayload = {
                        'accepted': true,
                        'granted_rights': grantedRights,
                        'granted_permissions': grantedRights,
                        'workspaceId': workspace.id,
                        'workspaceName': workspace.name,
                      };
                      await nearby.respondJoin(
                          clientEndpointId, approvedPayload);

                      // Register the endpoint so it can receive broadcast messages
                      sessionManager.registerEndpoint(
                        clientEndpointId,
                        request.requesterName,
                      );

                      // Get fresh workspace data
                      final updatedWorkspace = workspaceService.workspaces
                          .firstWhere((w) => w.id == workspace.id);

                      // Add approved client as member (if not already present)
                      // Use the client's persistent app UUID as member identity.
                      // request.requesterDeviceId is the persistent member identity.
                      final clientId =
                          sessionManager.clientDeviceId(clientEndpointId);
                      final newMember = WorkspaceMember(
                        id: clientId,
                        name: request.requesterName,
                        deviceId: clientId,
                        role: WorkspaceRole.contributor,
                        permissions: grantedRights,
                      );
                      final updatedMembers = updatedWorkspace.members
                          .where((m) => m.deviceId != clientId)
                          .toList();
                      updatedMembers.add(newMember);

                      // Update workspace with new member
                      await workspaceService.updateWorkspaceMembers(
                        updatedWorkspace.id,
                        updatedMembers,
                      );

                      // Create complete workspace sync payload
                      final workspaceSyncPayload = {
                        'type': 'WORKSPACE_SYNC',
                        'workspaceId': updatedWorkspace.id,
                        'workspaceName': updatedWorkspace.name,
                        'workspaceDescription': updatedWorkspace.description,
                        'hostEndpointId': workspace.ownerDeviceId,
                        'ownerName': updatedWorkspace.ownerName,
                        'ownerDeviceId': updatedWorkspace.ownerDeviceId,
                        'workspaceMembers': updatedMembers
                            .map((member) => {
                                  'id': member.id,
                                  'name': member.name,
                                  'deviceId': member.deviceId,
                                  'role': member.role.name,
                                  'permissions': member.permissions,
                                })
                            .toList(),
                        'roles': {
                          for (final member in updatedMembers)
                            member.deviceId: member.role.name,
                        },
                        'members': updatedMembers
                            .map((member) => {
                                  'id': member.id,
                                  'name': member.name,
                                  'deviceId': member.deviceId,
                                  'role': member.role.name,
                                  'permissions': member.permissions,
                                })
                            .toList(),
                        'resources': updatedWorkspace.resources
                            .map((resource) => resource.toJson())
                            .toList(),
                        'folders': updatedWorkspace.folders
                            .map((folder) => folder.toJson())
                            .toList(),
                        'announcements': updatedWorkspace.announcements
                            .map((ann) => ann.toJson())
                            .toList(),
                        'activityLogs': updatedWorkspace.activityLogs
                            .map((log) => log.toJson())
                            .toList(),
                        'inboxMessages': updatedWorkspace.inboxMessages
                            .map((msg) => msg.toJson())
                            .toList(),
                        'notifications': updatedWorkspace.notifications
                            .map((notif) => notif.toJson())
                            .toList(),
                        'transferHistory': updatedWorkspace.transferHistory
                            .map((transfer) => transfer.toJson())
                            .toList(),
                        'joinRequests': updatedWorkspace.joinRequests
                            .map((requestItem) => requestItem.toJson())
                            .toList(),
                        'permissions': [
                          for (final right in grantedRights) '$clientId:$right',
                        ],
                        'workspaceSettings': {
                          'visibility': updatedWorkspace.visibility,
                          'type': updatedWorkspace.type,
                          'icon': updatedWorkspace.icon,
                          'ownerName': updatedWorkspace.ownerName,
                        },
                        'workspaceRole': 'contributor',
                        'snapshotTimestamp': DateTime.now().toIso8601String(),
                      };

                      await workspaceService.applyWorkspaceSnapshot(
                        workspaceSyncPayload,
                        localDeviceId:
                            connectionService.deviceId ?? 'local-device',
                        localMemberName: 'You',
                        localRole: WorkspaceRole.contributor,
                        overrideWorkspaceId: updatedWorkspace.id,
                      );

                      await nearby.sendControl(
                        clientEndpointId,
                        {
                          'type': 'WORKSPACE_APPROVED',
                          ...workspaceSyncPayload,
                        },
                      );

                      await nearby.sendControl(
                        clientEndpointId,
                        {
                          'type': 'JOIN_APPROVED',
                          'workspaceId': updatedWorkspace.id,
                          'workspaceName': updatedWorkspace.name,
                          'workspaceDescription': updatedWorkspace.description,
                          'hostEndpointId': workspace.ownerDeviceId,
                          'ownerName': updatedWorkspace.ownerName,
                          'ownerDeviceId': updatedWorkspace.ownerDeviceId,
                          'workspaceMembers': updatedMembers
                              .map((member) => {
                                    'id': member.id,
                                    'name': member.name,
                                    'deviceId': member.deviceId,
                                    'role': member.role.name,
                                    'permissions': member.permissions,
                                  })
                              .toList(),
                          'members': updatedMembers
                              .map((member) => {
                                    'id': member.id,
                                    'name': member.name,
                                    'deviceId': member.deviceId,
                                    'role': member.role.name,
                                    'permissions': member.permissions,
                                  })
                              .toList(),
                          'resources': updatedWorkspace.resources
                              .map((resource) => resource.toJson())
                              .toList(),
                          'folders': updatedWorkspace.folders
                              .map((folder) => folder.toJson())
                              .toList(),
                          'announcements': updatedWorkspace.announcements
                              .map((ann) => ann.toJson())
                              .toList(),
                          'activityLogs': updatedWorkspace.activityLogs
                              .map((log) => log.toJson())
                              .toList(),
                          'inboxMessages': updatedWorkspace.inboxMessages
                              .map((msg) => msg.toJson())
                              .toList(),
                          'notifications': updatedWorkspace.notifications
                              .map((notif) => notif.toJson())
                              .toList(),
                          'transferHistory': updatedWorkspace.transferHistory
                              .map((transfer) => transfer.toJson())
                              .toList(),
                          'joinRequests': updatedWorkspace.joinRequests
                              .map((requestItem) => requestItem.toJson())
                              .toList(),
                          'workspaceSettings': {
                            'visibility': updatedWorkspace.visibility,
                            'type': updatedWorkspace.type,
                            'icon': updatedWorkspace.icon,
                            'ownerName': updatedWorkspace.ownerName,
                          },
                          'grantedRights': grantedRights,
                          'permissions': [
                            for (final right in grantedRights)
                              '$clientId:$right',
                          ],
                          'workspaceRole': 'contributor',
                        },
                      );

                      // Send workspace sync as control message
                      await nearby.sendControl(
                        clientEndpointId,
                        {
                          'type': 'WORKSPACE_SYNC',
                          ...workspaceSyncPayload,
                          // Ensure both naming variants are present for compat.
                          'sharedFolders':
                              workspaceSyncPayload['folders'] ?? [],
                          'sharedResources':
                              workspaceSyncPayload['resources'] ?? [],
                          'workspaceMembers': workspaceSyncPayload['members'] ??
                              workspaceSyncPayload['workspaceMembers'] ??
                              [],
                        },
                      );

                      // Mark host session active so _syncFromWorkspaceService broadcasts changes.
                      sessionManager.connectionState = 'connected';
                      sessionManager.workspaceSessionActive = true;

                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(
                            content: Text('Approved ${request.requesterName}')),
                      );
                      setState(() {});
                    },
                    child: const Text('Approve'),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      final nearby = context.read<NearbyService>();
                      final workspaceService = context.read<WorkspaceService>();
                      final sessionManager =
                          context.read<WorkspaceSessionManager>();
                      final messenger = ScaffoldMessenger.of(context);
                      final clientEndpointId =
                          sessionManager.endpointIdForClientDeviceId(
                              request.requesterDeviceId);
                      if (clientEndpointId == null) {
                        messenger.showSnackBar(
                          const SnackBar(
                              content: Text('Client is no longer connected')),
                        );
                        return;
                      }
                      await workspaceService.rejectJoinRequest(
                          workspace.id, request.id);
                      final rejectedPayload = {
                        'accepted': false,
                        'workspaceId': workspace.id,
                        'workspaceName': workspace.name,
                      };
                      await nearby.respondJoin(
                          clientEndpointId, rejectedPayload);
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(
                            content: Text('Rejected ${request.requesterName}')),
                      );
                      setState(() {});
                    },
                    child: const Text('Reject'),
                  ),
                ],
              ),
            );
          },
        );
      case 'Resources':
        final resources = workspace.resources;
        final folders = workspace.folders;
        final filteredResources = resources.where((resource) {
          if (_selectedFolderId != null &&
              resource.folderId != _selectedFolderId) {
            return false;
          }
          final query = _searchQuery.trim().toLowerCase();
          if (query.isEmpty) return true;
          return resource.name.toLowerCase().contains(query) ||
              resource.kind.toLowerCase().contains(query);
        }).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: const InputDecoration(
                hintText: 'Search resources',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            if (folders.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Shared folders',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  Text('${folders.length} total',
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: folders.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _buildFolderChip(
                        id: null,
                        name: 'All resources',
                      );
                    }
                    final folder = folders[index - 1];
                    return _buildFolderChip(
                      id: folder.id,
                      name: folder.name,
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Resources',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                Text('${filteredResources.length} found',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filteredResources.isEmpty
                  ? const Center(
                      child: Text('No resources yet.',
                          style: TextStyle(color: Colors.white70)))
                  : ListView.builder(
                      itemCount: filteredResources.length,
                      itemBuilder: (context, index) {
                        final resource = filteredResources[index];
                        return ListTile(
                          title: Text(resource.name),
                          subtitle: Text(
                              '${resource.kind} • ${resource.sizeBytes} bytes'),
                          trailing: const Icon(Icons.folder_open_rounded),
                        );
                      },
                    ),
            ),
          ],
        );
      case 'Members':
        return ListView(
          children: workspace.members.map((member) {
            final shortId = (member.deviceId.length >= 6)
                ? member.deviceId.substring(0, 6)
                : (member.deviceId.isNotEmpty ? member.deviceId : member.id);
            return ListTile(
              title: Text(member.name),
              subtitle: Text(member.role.name),
              trailing: Text(shortId),
            );
          }).toList(),
        );
      case 'Announcements':
        return ListView(
          children: workspace.announcements.map((announcement) {
            return Card(
              child: ListTile(
                title: Text(announcement.title),
                subtitle: Text(announcement.body),
              ),
            );
          }).toList(),
        );
      case 'Activity':
        return ListView(
          children: workspace.activityLogs.map((entry) {
            return ListTile(
              title: Text(entry.title),
              subtitle: Text(entry.detail),
            );
          }).toList(),
        );
      default:
        final unreadCount =
            workspace.inboxMessages.where((message) => !message.read).length;
        return ListView(
          children: [
            ListTile(
                title: Text(workspace.name),
                subtitle: Text(workspace.description)),
            ListTile(
                title: const Text('Visibility'),
                subtitle: Text(workspace.visibility)),
            ListTile(title: const Text('Type'), subtitle: Text(workspace.type)),
            ListTile(
                title: const Text('Owner'),
                subtitle: Text(workspace.ownerName)),
            const Divider(color: Color(0xFF22304A)),
            ListTile(
              title: const Text('Shared folders'),
              subtitle: Text('${workspace.folders.length} folders'),
              trailing: ElevatedButton(
                onPressed: () => _showCreateFolderDialog(workspace.id),
                child: const Text('New folder'),
              ),
            ),
            ListTile(
              title: const Text('Inbox'),
              subtitle: Text('$unreadCount unread messages'),
            ),
            if (workspace.inboxMessages.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('No inbox messages yet.',
                    style: TextStyle(color: Colors.white70)),
              )
            else
              ...workspace.inboxMessages
                  .take(4)
                  .map((message) => ListTile(
                        title: Text(message.subject),
                        subtitle: Text(message.senderName),
                        trailing: IconButton(
                          icon: Icon(
                            message.read
                                ? Icons.mark_email_read_rounded
                                : Icons.mark_email_unread_rounded,
                            color: message.read
                                ? Colors.greenAccent
                                : Colors.amber,
                          ),
                          onPressed: () async {
                            await context
                                .read<WorkspaceService>()
                                .markInboxMessageRead(workspace.id, message.id);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content:
                                    Text('Marked "${message.subject}" read'),
                              ),
                            );
                          },
                        ),
                      ))
                  .toList(),
          ],
        );
    }
  }

  Widget _buildFolderChip({required String? id, required String name}) {
    final selected = _selectedFolderId == id;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _selectedFolderId = id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF17304C) : const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color:
                  selected ? const Color(0xFF00D9FF) : const Color(0xFF22304A),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_outlined,
                  size: 18, color: Color(0xFF00D9FF)),
              const SizedBox(width: 8),
              Text(name, style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCreateFolderDialog(String workspaceId) async {
    final nameController = TextEditingController();
    final workspaceService = context.read<WorkspaceService>();
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: const Color(0xFF0F172A),
            title: const Text('New shared folder'),
            content: TextField(
              controller: nameController,
              decoration: const InputDecoration(
                hintText: 'Folder name',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel')),
              ElevatedButton(
                  onPressed: () {
                    if (nameController.text.trim().isEmpty) return;
                    Navigator.of(dialogContext).pop(true);
                  },
                  child: const Text('Create')),
            ],
          );
        });
    if (result != true) return;
    final folderName = nameController.text.trim();
    if (folderName.isEmpty) return;
    await workspaceService.createFolder(
      workspaceId: workspaceId,
      name: folderName,
    );

    // Broadcast updated workspace to connected peers so clients see new folders
    // After creating the folder, re-check mounted and broadcast from the
    // live session manager to avoid using BuildContext across an await.
    if (!mounted) return;
    try {
      final sessionManager = context.read<WorkspaceSessionManager>();
      final connectionService = context.read<ConnectionService>();
      final active = workspaceService.activeWorkspace;
      if (active != null && sessionManager.connectionState == 'connected') {
        await sessionManager.broadcastWorkspaceSync(
          workspace: active,
          role: sessionManager.isHostMode ? 'owner' : 'contributor',
          hostEndpointId:
              connectionService.deviceId ?? sessionManager.connectedHost,
          members: active.members,
          permissions: sessionManager.permissions,
          folders: active.folders,
          resources: active.resources,
        );
      }
    } catch (e) {
      debugPrint('[DASHBOARD_DEBUG] Failed to broadcast workspace sync: $e');
    }
    messenger.showSnackBar(
      SnackBar(content: Text('Created folder "$folderName"')),
    );
  }
}
