import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../screens/workspace_dashboard_screen.dart';
import '../services/connection_service.dart';
import '../services/workspace_service.dart';
import '../services/workspace_session_manager.dart';

class MainScreen extends StatelessWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final workspaceService = context.watch<WorkspaceService>();
    final workspaceSessionManager = context.watch<WorkspaceSessionManager>();
    final workspace = workspaceService.activeWorkspace ??
        workspaceSessionManager.currentWorkspace;

    debugPrint(
        '[STATE] MAINSCREEN_OPEN -> ${workspace?.name ?? 'no workspace'}');
    if (workspace != null) {
      debugPrint(
          '[DEBUG_LOG] MAIN SCREEN RECEIVED WORKSPACE: ${workspace.id} name=${workspace.name}');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nexus Bridge'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _confirmDisconnect(context),
          ),
        ],
      ),
      body: workspace == null
          ? _buildNoWorkspace(context)
          : _buildWorkspacePreview(context, workspace),
    );
  }

  Widget _buildNoWorkspace(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded,
                size: 72, color: Color(0xFF00D9FF)),
            const SizedBox(height: 24),
            const Text(
              'No active workspace found.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: Colors.white),
            ),
            const SizedBox(height: 12),
            const Text(
              'Return to discovery and join or create a nearby workspace to continue working offline.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                context.read<ConnectionService>().disconnect();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00D9FF),
                foregroundColor: Colors.black,
              ),
              child: const Text('Return to discovery'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspacePreview(BuildContext context, dynamic workspace) {
    final members = workspace.members.length;
    final resources = workspace.resources.length;
    final folders = workspace.folders.length;
    final hasProtection = workspace.visibility.toLowerCase() != 'local';

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF121B2D),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF22304A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFF00D9FF), Color(0xFF7C4DFF)],
                        ),
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
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                          const SizedBox(height: 4),
                          Text(workspace.type,
                              style: const TextStyle(
                                  fontSize: 13, color: Color(0xFF8FB5D8))),
                        ],
                      ),
                    ),
                    if (hasProtection)
                      const Icon(Icons.lock_outline_rounded,
                          color: Color(0xFF00D9FF), size: 18),
                  ],
                ),
                const SizedBox(height: 16),
                Text(workspace.description,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildStatChip('${workspace.ownerName}', 'Owner'),
                    _buildStatChip('$members', 'Members'),
                    _buildStatChip('$resources', 'Resources'),
                    _buildStatChip('$folders', 'Folders'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView(
              children: [
                _buildInfoTile(Icons.cloud_off_rounded, 'Offline Mode',
                    'This workspace is stored and available locally without internet.'),
                _buildInfoTile(Icons.storage_rounded, 'Local Persistence',
                    'Workspace state and resources are persisted on this device.'),
                _buildInfoTile(Icons.group_rounded, 'Nearby Discovery',
                    'Use the discovery tab to share and join workspaces with nearby devices.'),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => WorkspaceDashboardScreen(
                  workspaceName: workspace.name,
                  workspaceType: workspace.type,
                  ownerName: workspace.ownerName,
                  members: members,
                  resources: resources,
                  isProtected: hasProtection,
                ),
              ));
            },
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Open Workspace'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D9FF),
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(50),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF17304C),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String title, String subtitle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121B2D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF22304A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF00D9FF), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDisconnect(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1E2F),
        title: const Text('Disconnect'),
        content: const Text('Leave the workspace and return to discovery?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final connectionService = context.read<ConnectionService>();
              final workspaceManager = context.read<WorkspaceSessionManager>();
              await workspaceManager.terminateWorkspaceSession();
              connectionService.disconnect();
              navigator.pop();
            },
            child: const Text(
              'Disconnect',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
