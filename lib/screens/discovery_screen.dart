import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/discovery_service.dart';
import '../services/connection_service.dart';
import '../services/nearby_service.dart';
import '../services/profile_service.dart';
import '../services/workspace_service.dart';
import '../services/offline_session_service.dart';
import '../services/workspace_session_manager.dart';
import 'workspace_dashboard_screen.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({Key? key}) : super(key: key);

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  late final TextEditingController _searchController;
  late final NearbyService _nearbyService;
  late final WorkspaceSessionManager _workspaceSessionManager;
  StreamSubscription<String>? _uiEventsSub;

  Map<String, Map<String, dynamic>> get _nearbyEndpoints =>
      _workspaceSessionManager.nearbyEndpoints;
  bool get _nearbyDiscovering => _workspaceSessionManager.nearbyDiscovering;
  bool get _advertisingNearby => _workspaceSessionManager.advertisingNearby;
  bool get _isHostMode => _workspaceSessionManager.isHostMode;
  bool get _joinRequestPending => _workspaceSessionManager.joinRequestPending;
  String get _joinRequestStatus => _workspaceSessionManager.joinRequestStatus;
  bool get _workspaceSessionActive =>
      _workspaceSessionManager.workspaceSessionActive;
  String? get _joinedWorkspaceName =>
      _workspaceSessionManager.joinedWorkspaceName;
  String get _joinedWorkspaceType =>
      _workspaceSessionManager.joinedWorkspaceType;
  String get _joinedOwnerName => _workspaceSessionManager.joinedOwnerName;
  int get _joinedMembers => _workspaceSessionManager.joinedMembers;
  int get _joinedResources => _workspaceSessionManager.joinedResources;
  String? get _approvalPendingWorkspaceId =>
      _workspaceSessionManager.approvalPendingWorkspaceId;

  set _workspaceSessionActive(bool v) =>
      _workspaceSessionManager.workspaceSessionActive = v;
  set _joinedWorkspaceName(String? v) =>
      _workspaceSessionManager.joinedWorkspaceName = v;
  set _joinedWorkspaceType(String v) =>
      _workspaceSessionManager.joinedWorkspaceType = v;
  set _joinedOwnerName(String v) =>
      _workspaceSessionManager.joinedOwnerName = v;
  set _joinedMembers(int v) => _workspaceSessionManager.joinedMembers = v;
  set _joinedResources(int v) => _workspaceSessionManager.joinedResources = v;
  set _advertisingNearby(bool v) =>
      _workspaceSessionManager.advertisingNearby = v;
  set _isHostMode(bool v) => _workspaceSessionManager.isHostMode = v;
  set _joinRequestPending(bool v) =>
      _workspaceSessionManager.joinRequestPending = v;
  set _joinRequestStatus(String v) =>
      _workspaceSessionManager.joinRequestStatus = v;

  final List<_ActivityItem> _recentActivities = [];
  final List<_NotificationItem> _notifications = [];
  int _sharedResourcesCount = 0;
  int _sharedFolderCount = 0;
  int _storageUsedBytes = 0;
  int _downloadsCompleted = 0;
  int _uploadsCompleted = 0;
  int _unreadInboxCount = 0;
  int _unreadNotifications = 0;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _nearbyService = context.read<NearbyService>();
    _workspaceSessionManager = context.read<WorkspaceSessionManager>();

    _uiEventsSub = _workspaceSessionManager.uiEvents.listen((event) {
      if (event == 'NAVIGATE_TO_DASHBOARD') {
        final workspace = _workspaceSessionManager.currentWorkspace;
        if (workspace != null && mounted) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => WorkspaceDashboardScreen(
              workspaceName: workspace.name,
              workspaceType: workspace.type,
              ownerName: workspace.ownerName,
              members: workspace.members.length,
              resources: workspace.resources.length,
              isProtected: true,
            ),
          ));
        }
      } else if (event.startsWith('FILE_LIST_UPDATED:')) {
        final from = event.split(':').last;
        _showFileListDialog(from);
      }
    });

    _refreshLiveStats();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final connectionService = context.read<ConnectionService>();
      final sessionService = context.read<OfflineSessionService>();
      await connectionService.ensureDeviceIdReady();
      sessionService.setLocalDeviceId(
        connectionService.deviceId ?? 'local-device',
      );
      await _workspaceSessionManager.load();
      _syncWorkspaceFromService();
      await _startNearbyDiscovery();
    });

    _addActivity('Workspace ready', 'Offline workspace is ready for discovery',
        icon: Icons.workspace_premium_outlined);
    _pushNotification('Welcome', 'Your offline workspace is ready');
  }

  @override
  void dispose() {
    _uiEventsSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _startNearbyDiscovery() async {
    debugPrint(
        '[DISCOVERY_DEBUG] _startNearbyDiscovery called – nearbyDiscovering=${_workspaceSessionManager.nearbyDiscovering}');
    try {
      await _workspaceSessionManager.startNearbyDiscovery();
      debugPrint('[DISCOVERY_DEBUG] startNearbyDiscovery returned');
    } catch (e) {
      debugPrint('[DISCOVERY_DEBUG] startNearbyDiscovery THREW: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nearby discovery failed: $e')),
      );
    }
  }

  void _showFileListDialog(String from) {
    final arr = _workspaceSessionManager.remoteFiles[from];
    if (arr == null || !mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Files from $from'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: arr.map((e) {
              final fid = e['id'].toString();
              final fname = e['name'].toString();
              return ListTile(
                title: Text(fname),
                subtitle: Text('${e['size']} bytes'),
                trailing: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _workspaceSessionManager.downloadBuffers.remove(fid);
                    _nearbyService.requestFileChunk(from, fid, 0);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Requested download for $fname')));
                  },
                  child: const Text('Download'),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          )
        ],
      ),
    );
  }

  Future<void> _handleRefresh() async {
    debugPrint(
        '[APPROVAL_DEBUG] _handleRefresh: sessionActive=$_workspaceSessionActive status=$_joinRequestStatus approvalPendingId=$_approvalPendingWorkspaceId');
    if (_workspaceSessionActive ||
        _joinRequestStatus == 'approved' ||
        _approvalPendingWorkspaceId != null) {
      debugPrint(
          '[APPROVAL_DEBUG] Skipping discovery restart – approval/session in progress (status=$_joinRequestStatus)');
      _refreshLiveStats();
      _syncWorkspaceFromService();
      return;
    }
    await _startNearbyDiscovery();
    _refreshLiveStats();
    _syncWorkspaceFromService();
    await Future.delayed(const Duration(milliseconds: 350));
  }

  void _syncWorkspaceFromService() {
    if (!mounted) return;
    final workspaceService = context.read<WorkspaceService>();
    final persistedWorkspace = workspaceService.activeWorkspace;
    if (persistedWorkspace == null) return;

    setState(() {
      _workspaceSessionActive = true;
      _joinedWorkspaceName ??= persistedWorkspace.name;
      _joinedWorkspaceType = persistedWorkspace.type.isNotEmpty
          ? persistedWorkspace.type
          : _joinedWorkspaceType;
      _joinedOwnerName = persistedWorkspace.ownerName.isNotEmpty
          ? persistedWorkspace.ownerName
          : _joinedOwnerName;
      _joinedMembers = persistedWorkspace.members.length;
      _joinedResources = persistedWorkspace.resources.length;
      _sharedResourcesCount = persistedWorkspace.resources.length;
      _sharedFolderCount = persistedWorkspace.folders.length;
      _unreadInboxCount = persistedWorkspace.inboxMessages
          .where((message) => !message.read)
          .length;
      _storageUsedBytes = math.max(
        2048,
        persistedWorkspace.resources.fold<int>(
              0,
              (sum, resource) => sum + resource.sizeBytes,
            ) +
            persistedWorkspace.transferHistory.fold<int>(
              0,
              (sum, transfer) => sum + transfer.transferredBytes,
            ),
      );
      _downloadsCompleted = persistedWorkspace.transferHistory
          .where((transfer) => transfer.direction == 'download')
          .length;
      _uploadsCompleted = persistedWorkspace.transferHistory
          .where((transfer) => transfer.direction == 'upload')
          .length;
      _unreadNotifications = persistedWorkspace.notifications.length;
    });
  }

  void _refreshLiveStats() {
    if (!mounted) return;
    setState(() {
      _storageUsedBytes = math.max(
          2048,
          _joinedResources * 1024 +
              _sharedResourcesCount * 512 +
              _uploadsCompleted * 1024 +
              _downloadsCompleted * 256);
      _unreadNotifications = _notifications.length;
    });
  }

  void _addActivity(String title, String description,
      {required IconData icon}) {
    if (!mounted) return;
    setState(() {
      _recentActivities.insert(
          0, _ActivityItem(title: title, description: description, icon: icon));
      if (_recentActivities.length > 6) {
        _recentActivities.removeLast();
      }
    });
  }

  void _pushNotification(String title, String message) {
    if (!mounted) return;
    setState(() {
      _notifications.insert(
          0, _NotificationItem(title: title, message: message));
      if (_notifications.length > 6) {
        _notifications.removeLast();
      }
      _unreadNotifications = _notifications.length;
    });
  }

  void _showActivitySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Recent activity',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              const SizedBox(height: 12),
              if (_recentActivities.isEmpty)
                const Text(
                    'Activity will appear here as you create or join nearby workspaces.',
                    style: TextStyle(color: Colors.white70))
              else
                ..._recentActivities.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                  color: const Color(0xFF17304C),
                                  borderRadius: BorderRadius.circular(12)),
                              child: Icon(item.icon,
                                  color: const Color(0xFF00D9FF))),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(item.title,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600)),
                                Text(item.description,
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 12))
                              ]))
                        ],
                      ),
                    )),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<WorkspaceSessionManager>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nexus Bridge'),
        elevation: 0,
        actions: [
          Stack(
            alignment: Alignment.topRight,
            children: [
              IconButton(
                onPressed: () {
                  _pushNotification('Notifications',
                      'You have ${_notifications.length} offline updates');
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: const Color(0xFF0F172A),
                    shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(24))),
                    builder: (context) => Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Notifications',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                          const SizedBox(height: 12),
                          if (_notifications.isEmpty)
                            const Text('No offline notifications yet.',
                                style: TextStyle(color: Colors.white70))
                          else
                            ..._notifications.map((item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Row(
                                    children: [
                                      Container(
                                          width: 38,
                                          height: 38,
                                          decoration: BoxDecoration(
                                              color: const Color(0xFF17304C),
                                              borderRadius:
                                                  BorderRadius.circular(12)),
                                          child: const Icon(
                                              Icons.notifications_rounded,
                                              color: Color(0xFF00D9FF))),
                                      const SizedBox(width: 10),
                                      Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                            Text(item.title,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                            Text(item.message,
                                                style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 12))
                                          ]))
                                    ],
                                  ),
                                )),
                        ],
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.notifications_rounded),
              ),
              if (_unreadNotifications > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                        color: Color(0xFF00D9FF), shape: BoxShape.circle),
                    child: Text(_unreadNotifications.toString(),
                        style: const TextStyle(
                            fontSize: 10,
                            color: Colors.black,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
          IconButton(
            onPressed: _handleRefresh,
            icon: AnimatedRotation(
              turns: _nearbyDiscovering ? 0.5 : 0,
              duration: const Duration(milliseconds: 700),
              child: const Icon(Icons.refresh_rounded),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateWorkspaceSheet(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Create Workspace'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF00D9FF),
          onRefresh: _handleRefresh,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCurrentWorkspaceCard(),
                const SizedBox(height: 16),
                _buildHeroSection(context),
                const SizedBox(height: 16),
                _buildSearchBar(),
                const SizedBox(height: 16),
                _buildQuickActionsRow(),
                const SizedBox(height: 24),
                _buildNearbySection(context),
                const SizedBox(height: 24),
                _buildWorkspaceHubSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSection(BuildContext context) {
    final workspaceService = context.watch<WorkspaceService>();
    final workspaceCount = workspaceService.workspaces.length;
    final resourceCount = workspaceService.workspaces.fold<int>(
      0,
      (sum, workspace) => sum + workspace.resources.length,
    );
    final folderCount = workspaceService.workspaces.fold<int>(
      0,
      (sum, workspace) => sum + workspace.folders.length,
    );
    final unreadMessages = workspaceService.workspaces.fold<int>(
      0,
      (sum, workspace) =>
          sum + workspace.inboxMessages.where((m) => !m.read).length,
    );
    final storageBytes = workspaceService.workspaces.fold<int>(
      0,
      (sum, workspace) =>
          sum +
          workspace.resources.fold<int>(
            0,
            (resourceSum, resource) => resourceSum + resource.sizeBytes,
          ),
    );
    final transferCount = workspaceService.workspaces.fold<int>(
      0,
      (sum, workspace) => sum + workspace.transferHistory.length,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
            colors: [Color(0xFF11223A), Color(0xFF0F172A)]),
        border: Border.all(color: const Color(0xFF2E3E5D)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x3300D9FF), blurRadius: 20, offset: Offset(0, 10))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                        colors: [Color(0xCC00BCD4), Color(0x990000FF)])),
                child: const Icon(Icons.workspaces_outline,
                    size: 28, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Offline Digital Workspace',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(_buildWorkspaceStatusText(),
                        style: TextStyle(
                            fontSize: 13, color: _buildWorkspaceStatusColor())),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildStatusChip(),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildMiniStatCard('My Workspaces', '$workspaceCount',
                  Icons.folder_copy_outlined),
              _buildMiniStatCard('Shared Resources', '$resourceCount',
                  Icons.folder_open_rounded),
              _buildMiniStatCard('Shared Folders', '$folderCount',
                  Icons.folder_shared_rounded),
              _buildMiniStatCard('Unread Messages', '$unreadMessages',
                  Icons.mark_email_unread_rounded),
              _buildMiniStatCard('Storage Used',
                  '${(storageBytes / 1024).round()} KB', Icons.storage_rounded),
              _buildMiniStatCard('Recent Transfers', '$transferCount',
                  Icons.swap_horiz_rounded),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF121B2D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF22304A)),
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: 'Search workspaces, resources, members, announcements',
          hintStyle: TextStyle(color: Colors.grey),
          border: InputBorder.none,
          prefixIcon: Icon(Icons.search_rounded, color: Color(0xFF00D9FF)),
        ),
      ),
    );
  }

  Widget _buildQuickActionsRow() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
                child: _buildQuickAction(
                    'Create Workspace',
                    Icons.add_circle_outline_rounded,
                    () => _showCreateWorkspaceSheet(),
                    'Launch a private nearby workspace')),
            const SizedBox(width: 10),
            Expanded(
                child: _buildQuickAction(
                    'Discover Nearby',
                    Icons.explore_rounded,
                    _startNearbyDiscovery,
                    'Scan and find shared spaces')),
          ],
        ),
        const SizedBox(height: 12),
        _buildQuickAction('Recent Activity', Icons.history_rounded,
            _showActivitySheet, 'Review transfers and workspace events',
            fullWidth: true),
      ],
    );
  }

  Widget _buildWorkspaceHubSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Quick Actions',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF00D9FF))),
        const SizedBox(height: 12),
        _buildProfileCard(),
        const SizedBox(height: 16),
        _buildRoleSection(),
        const SizedBox(height: 16),
        _buildActivitySection(),
      ],
    );
  }

  Widget _buildQuickAction(
      String title, IconData icon, VoidCallback onTap, String subtitle,
      {bool fullWidth = false}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: fullWidth ? double.infinity : null,
      child: Material(
        color: const Color(0xFF1A2740),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF30415E)),
            ),
            child: Row(
              children: [
                Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: Color(0xFF17304C)),
                    child:
                        Icon(icon, color: const Color(0xFF00D9FF), size: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded,
                    color: Color(0xFF00D9FF), size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStatCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111B2C),
        border: Border.all(color: const Color(0xFF22304A)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF00D9FF), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    final profile = context.read<ProfileService>().profile;
    final displayName = profile?.displayName ?? 'Offline Member';
    final deviceName = profile?.deviceName ?? 'Local Device';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121B2D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF22304A)),
      ),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                    colors: [Color(0xFF4FC3F7), Color(0xFF7C4DFF)])),
            child:
                const Icon(Icons.person_outline, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const SizedBox(height: 4),
                const Text('Current role • Contributor',
                    style: TextStyle(fontSize: 12, color: Color(0xFF8FB5D8))),
                const SizedBox(height: 6),
                Text('$deviceName • ${_joinedWorkspaceName ?? 'No workspace'}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                Text('Storage used • ${(_storageUsedBytes / 1024).round()} KB',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121B2D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF22304A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Roles & Permissions',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildRoleChip('Owner', 'Full control', const Color(0xFF00D9FF)),
              _buildRoleChip(
                  'Admin', 'Manage members', const Color(0xFF7C4DFF)),
              _buildRoleChip(
                  'Contributor', 'Upload & download', const Color(0xFF4CAF50)),
              _buildRoleChip('Viewer', 'Read only', const Color(0xFFFFB300)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoleChip(String role, String description, Color color) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: const Color(0xFF17304C),
          borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(role, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(description,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]),
    );
  }

  Widget _buildActivitySection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121B2D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF22304A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recent Activity',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF00D9FF))),
          const SizedBox(height: 10),
          if (_recentActivities.isEmpty)
            const Text('Your latest workspace activity will appear here.',
                style: TextStyle(color: Colors.white70))
          else
            ..._recentActivities.map((item) =>
                _buildActivityRow(item.icon, item.title, item.description)),
        ],
      ),
    );
  }

  Widget _buildActivityRow(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: const Color(0xFF17304C),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: const Color(0xFF00D9FF), size: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoverySection(BuildContext context) {
    final nearbyServers = _nearbyEndpoints.entries.map((entry) {
      final endpoint = entry.value;
      final name = endpoint['endpointName']?.toString() ?? 'Nearby Workspace';
      return DiscoveredServer(
        name: name,
        ip: entry.key,
        port: 0,
        deviceId: entry.key,
      );
    }).toList();
    debugPrint(
        '[ENDPOINT_DEBUG] _buildDiscoverySection: discovering=$_nearbyDiscovering endpoints=${nearbyServers.length}');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Nearby Workspaces',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF00D9FF))),
            Text('${nearbyServers.length} available',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 12),
        // [DISCOVERY_DEBUG] Spinner and list are now independent:
        // spinner shows while scanning, list shows whenever endpoints exist.
        if (_nearbyDiscovering)
          const Center(
              child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Color(0xFF00D9FF))))),
        if (nearbyServers.isEmpty && !_nearbyDiscovering)
          _buildEmptyState()
        else if (nearbyServers.isNotEmpty)
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: nearbyServers.length,
            itemBuilder: (context, index) {
              final server = nearbyServers[index];
              return _buildWorkspaceCard(
                context,
                server,
                endpointId: server.deviceId,
                endpointName: server.name,
              );
            },
          ),
      ],
    );
  }

  Widget _buildNearbySection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDiscoverySection(context),
        const SizedBox(height: 8),
        if (_advertisingNearby && _isHostMode)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showHostFiles,
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Browse Workspace Resources'),
            ),
          ),
      ],
    );
  }

  Future<void> _startNearbyAdvertising() async {
    debugPrint('[ADVERTISING_DEBUG] _startNearbyAdvertising called');
    // Capture context-dependent references before the async gap.
    final messenger = ScaffoldMessenger.of(context);
    final sessionService = context.read<OfflineSessionService>();
    // Stop discovery when switching to host mode so the spinner clears.
    await _workspaceSessionManager.stopNearbyDiscovery();
    if (!mounted) return;
    setState(() => _advertisingNearby = true);
    try {
      sessionService.setAdvertisingActive(true);
      const name = 'Nexus Bridge Host';
      debugPrint(
          '[ADVERTISING_DEBUG] invoking startAdvertising name=$name serviceId=nexus-community');
      await _nearbyService.startAdvertising('nexus-community', name);
      debugPrint('[ADVERTISING_DEBUG] startAdvertising returned successfully');
      if (!mounted) return;
      final workspaceService = context.read<WorkspaceService>();
      final workspace = await workspaceService.ensureWorkspace(
        name: _joinedWorkspaceName ?? 'My Workspace',
        description: 'Offline workspace created for nearby collaboration',
        visibility: 'Local',
        password: '',
        type: 'Host',
        icon: 'workspaces',
        ownerName: 'You',
        ownerDeviceId:
            context.read<ConnectionService>().deviceId ?? 'local-device',
      );
      await workspaceService.setActiveWorkspace(workspace.id);
      if (!mounted) return;
      sessionService.beginHostSession(
        workspaceId: workspace.id,
        workspaceName: workspace.name,
        ownerName: 'You',
        ownerDeviceId:
            context.read<ConnectionService>().deviceId ?? 'local-device',
      );
      setState(() {
        _isHostMode = true;
        _joinedWorkspaceName = workspace.name;
        _joinedWorkspaceType = 'Host';
        _joinedOwnerName = 'You';
        _joinedMembers = workspace.members.length;
        _joinedResources = workspace.resources.length;
      });
      _addActivity(
          'Workspace created', 'This device is now broadcasting locally',
          icon: Icons.wifi_tethering_outlined);
      _pushNotification(
          'Workspace created', 'Your workspace is now discoverable nearby');
      messenger.showSnackBar(
          const SnackBar(content: Text('Nearby advertising started')));
    } catch (e) {
      if (!mounted) return;
      context
          .read<OfflineSessionService>()
          .recordError('Advertising failed: $e');
      context.read<OfflineSessionService>().setAdvertisingActive(false);
      setState(() => _advertisingNearby = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Nearby advertising failed: $e')),
      );
    }
  }

  Future<void> _showCreateWorkspaceSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Create a workspace',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              const SizedBox(height: 8),
              const Text(
                  'Advertise this device as a nearby host so other members can join and exchange files.',
                  style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await _startNearbyAdvertising();
                  },
                  icon: const Icon(Icons.wifi_tethering_rounded),
                  label: const Text('Start Workspace'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF22304A)),
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF121B2D),
      ),
      child: Column(
        children: [
          const Icon(Icons.wifi_tethering_rounded,
              size: 44, color: Color(0xFF00D9FF)),
          const SizedBox(height: 10),
          const Text('No Nearby Workspace Found',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
          const SizedBox(height: 6),
          const Text(
              'There are currently no nearby workspaces available. Create a workspace or wait for nearby users.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: ElevatedButton.icon(
                    onPressed: () => _showCreateWorkspaceSheet(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Create Workspace'))),
            const SizedBox(width: 10),
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: _handleRefresh,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Refresh'))),
          ])
        ],
      ),
    );
  }

  Future<void> _showHostFiles() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final files = dir.listSync().whereType<File>().toList();
      if (!mounted) return;
      await showDialog(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: const Text('Host Files'),
              content: SizedBox(
                width: double.maxFinite,
                child: files.isEmpty
                    ? const Text('No files')
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: files.length,
                        itemBuilder: (context, index) {
                          final f = files[index];
                          final name = f.uri.pathSegments.last;
                          return ListTile(
                            title: Text(name),
                            subtitle: Text('${f.lengthSync()} bytes'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () async {
                                final messenger = ScaffoldMessenger.of(context);
                                final dialogNavigator = Navigator.of(context);
                                final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (c2) {
                                      return AlertDialog(
                                        title: const Text('Confirm delete'),
                                        content: Text('Delete $name?'),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.of(c2).pop(false),
                                              child: const Text('Cancel')),
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.of(c2).pop(true),
                                              child: const Text('Delete')),
                                        ],
                                      );
                                    });
                                if (ok != true) return;
                                try {
                                  // Broadcast delete request to connected peers
                                  await _nearbyService.sendControl(null, {
                                    'type': 'FILE_DELETE_REQUEST',
                                    'file_id': name,
                                    'path': f.path,
                                    'owner': 'host'
                                  });
                                  // small grace period for peers to react
                                  await Future.delayed(
                                      const Duration(seconds: 1));

                                  await f.delete();
                                  // notify connected clients about deletion with structured info
                                  await _nearbyService.sendControl(null, {
                                    'type': 'FILE_DELETE_RESULT',
                                    'file_id': name,
                                    'path': f.path,
                                    'owner': 'host',
                                    'status': 'deleted'
                                  });
                                  if (!mounted) return;
                                  messenger.showSnackBar(
                                      SnackBar(content: Text('Deleted $name')));
                                  dialogNavigator.pop();
                                  // reopen to refresh
                                  _showHostFiles();
                                } catch (e) {
                                  if (!mounted) return;
                                  messenger.showSnackBar(SnackBar(
                                      content: Text('Delete failed: $e')));
                                }
                              },
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Close')),
              ],
            );
          });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to list files: $e')));
    }
  }

  Widget _buildWorkspaceCard(
    BuildContext context,
    DiscoveredServer server, {
    required String endpointId,
    required String endpointName,
  }) {
    final workspaceName = server.name.isEmpty ? 'Workspace' : server.name;
    final workspaceType = _pickWorkspaceType(server.name);
    final isProtected = workspaceName.toLowerCase().contains('secure') ||
        workspaceName.toLowerCase().contains('private');
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFF121B2D),
        borderRadius: BorderRadius.circular(20),
        elevation: 3,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showWorkspacePreviewSheet(
            server,
            workspaceName,
            workspaceType,
            isProtected,
            endpointId: endpointId,
            endpointName: endpointName,
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF22304A))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                        width: 46,
                        height: 46,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: [
                              Color(0xFF00D9FF),
                              Color(0xFF7C4DFF)
                            ])),
                        child: const Icon(Icons.group_work_rounded,
                            color: Colors.white)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(workspaceName,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                          const SizedBox(height: 2),
                          Text(workspaceType,
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF8FB5D8)))
                        ])),
                    if (isProtected)
                      const Icon(Icons.lock_outline_rounded,
                          color: Color(0xFF00D9FF), size: 18),
                  ],
                ),
                const SizedBox(height: 12),
                const Row(children: [
                  Icon(Icons.person_outline_rounded,
                      size: 16, color: Colors.grey),
                  SizedBox(width: 6),
                  Text('Owner: Nearby Host',
                      style: TextStyle(fontSize: 12, color: Colors.grey))
                ]),
                const SizedBox(height: 6),
                const Row(children: [
                  Icon(Icons.people_alt_outlined, size: 16, color: Colors.grey),
                  SizedBox(width: 6),
                  Text('Members: 2',
                      style: TextStyle(fontSize: 12, color: Colors.grey))
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.folder_open_rounded,
                      size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text('Resources: ${_sharedResourcesCount + 2}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey))
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                              color: const Color(0xFF17304C),
                              borderRadius: BorderRadius.circular(12)),
                          child: const Center(
                              child: Text('Available',
                                  style: TextStyle(
                                      color: Color(0xFF00D9FF),
                                      fontWeight: FontWeight.w700))))),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                      onPressed: () => _connectToServer(
                            context,
                            server.url,
                            endpointId: endpointId,
                            endpointName: endpointName,
                          ),
                      icon: const Icon(Icons.login_rounded, size: 18),
                      label: const Text('Join')),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showWorkspacePreviewSheet(
    DiscoveredServer server,
    String workspaceName,
    String workspaceType,
    bool isProtected, {
    required String endpointId,
    required String endpointName,
  }) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(workspaceName,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              const SizedBox(height: 8),
              const Text(
                  'A polished offline workspace for nearby collaboration and file sharing.',
                  style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                const Chip(
                    label: Text('Workspace'),
                    backgroundColor: Color(0xFF17304C),
                    labelStyle: TextStyle(color: Color(0xFF00D9FF))),
                Chip(
                    label: Text(isProtected ? 'Protected' : 'Public'),
                    backgroundColor: const Color(0xFF17304C),
                    labelStyle: const TextStyle(color: Color(0xFF00D9FF))),
              ]),
              const SizedBox(height: 14),
              _buildInfoRow(
                  Icons.person_outline_rounded, 'Owner', 'Nearby Host'),
              _buildInfoRow(
                  Icons.people_alt_outlined, 'Members', '2 active members'),
              _buildInfoRow(Icons.folder_open_rounded, 'Shared Resources',
                  '${_sharedResourcesCount + 2} files'),
              const SizedBox(height: 18),
              SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _connectToServer(
                          context,
                          server.url,
                          endpointId: endpointId,
                          endpointName: endpointName,
                        );
                      },
                      icon: const Icon(Icons.send_rounded),
                      label: const Text('Request to Join'))),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF00D9FF), size: 18),
          const SizedBox(width: 8),
          Text('$label: ',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
          Expanded(
              child:
                  Text(value, style: const TextStyle(color: Colors.white70))),
        ],
      ),
    );
  }

  Widget _buildCurrentWorkspaceCard() {
    final workspaceService = context.watch<WorkspaceService>();
    final persistedWorkspace = workspaceService.activeWorkspace;
    final displayName = _joinedWorkspaceName ?? persistedWorkspace?.name;

    if (displayName == null || displayName.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: const Color(0xFF121B2D),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF22304A))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Create Your First Workspace',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          const SizedBox(height: 6),
          const Text(
              'Start an offline workspace and invite nearby members to collaborate.',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
              onPressed: () => _showCreateWorkspaceSheet(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create Workspace')),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: const Color(0xFF121B2D),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF22304A))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.workspaces_rounded, color: Color(0xFF00D9FF)),
          SizedBox(width: 8),
          Text('Current Workspace',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white))
        ]),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                displayName,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF17304C),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _joinedWorkspaceType,
                style: const TextStyle(color: Color(0xFF00D9FF), fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
            'Owner: $_joinedOwnerName • Members: $_joinedMembers • Resources: $_joinedResources • Folders: $_sharedFolderCount • Unread: $_unreadInboxCount',
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 12),
        ElevatedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => WorkspaceDashboardScreen(
                    workspaceName: displayName,
                    workspaceType: _joinedWorkspaceType,
                    ownerName: _joinedOwnerName,
                    members: _joinedMembers,
                    resources: _joinedResources,
                    isProtected: _advertisingNearby))),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Open Workspace')),
      ]),
    );
  }

  Widget _buildStatusChip() {
    final statusColor = _buildWorkspaceStatusColor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: const Color(0xFF17304C),
          borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 10,
            height: 10,
            decoration:
                BoxDecoration(color: statusColor, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(_buildWorkspaceStatusText(),
            style: TextStyle(
                color: statusColor, fontWeight: FontWeight.w700, fontSize: 12))
      ]),
    );
  }

  String _buildWorkspaceStatusText() {
    if (_workspaceSessionActive ||
        (_joinedWorkspaceName != null && _joinedWorkspaceName!.isNotEmpty)) {
      return 'Connected';
    }
    if (_joinRequestPending) return 'Request Pending';
    if (_advertisingNearby && _isHostMode) return 'Active';
    if (_nearbyDiscovering) return 'Searching Nearby';
    if (_nearbyEndpoints.isNotEmpty) return 'Connected';
    return 'No Nearby Workspace';
  }

  Color _buildWorkspaceStatusColor() {
    if (_workspaceSessionActive ||
        (_joinedWorkspaceName != null && _joinedWorkspaceName!.isNotEmpty)) {
      return const Color(0xFF00D9FF);
    }
    if (_advertisingNearby && _isHostMode) return const Color(0xFF4CAF50);
    if (_nearbyDiscovering) return const Color(0xFFFFB300);
    if (_nearbyEndpoints.isNotEmpty) return const Color(0xFF00D9FF);
    return const Color(0xFFFF5252);
  }

  String _pickWorkspaceType(String name) {
    final lowercase = name.toLowerCase();
    if (lowercase.contains('edu')) {
      return 'Education';
    }
    if (lowercase.contains('office') || lowercase.contains('biz')) {
      return 'Office';
    }
    if (lowercase.contains('project')) {
      return 'Projects';
    }
    if (lowercase.contains('family')) {
      return 'Family';
    }
    if (lowercase.contains('event')) {
      return 'Events';
    }
    if (lowercase.contains('community')) {
      return 'Community';
    }
    if (lowercase.contains('friend')) {
      return 'Friends';
    }
    return 'Personal';
  }

  Future<void> _connectToServer(
    BuildContext context,
    String url, {
    String? endpointId,
    String? endpointName,
  }) async {
    final connectionService = context.read<ConnectionService>();
    final messenger = ScaffoldMessenger.of(context);
    final workspaceService = context.read<WorkspaceService>();
    final navigator = Navigator.of(context);
    final profile = context.read<ProfileService>().profile;
    final requesterName = profile?.displayName ?? 'Nearby Member';
    final ownerDeviceId = connectionService.deviceId ?? 'local-device';

    final success = await connectionService.connect(url);
    if (!mounted) return;
    if (!success) {
      messenger.showSnackBar(
        SnackBar(content: Text('Unable to connect to $url')),
      );
      return;
    }

    if (endpointId != null && endpointId.isNotEmpty) {
      final localDeviceId = connectionService.deviceId ?? 'local-device';
      final requestPayload = {
        'workspaceId': _joinedWorkspaceName == null
            ? 'workspace_unknown'
            : _joinedWorkspaceName!.replaceAll(' ', '_').toLowerCase(),
        'workspaceName':
            _joinedWorkspaceName ?? endpointName ?? 'Nearby Workspace',
        'requesterName': requesterName,
        'requesterDeviceId': localDeviceId,
        'requestedRights': ['read', 'write', 'list'],
        'timestamp': DateTime.now().toIso8601String(),
      };
      debugPrint('[Nearby] JOIN_REQUEST_SENT');
      await _nearbyService.requestJoin(endpointId, requestPayload);
      setState(() {
        _joinRequestPending = true;
        _joinRequestStatus = 'pending';
      });
      _addActivity('Join request sent', 'Waiting for host approval',
          icon: Icons.send_rounded);
      _pushNotification(
          'Join request sent', 'Your request is pending approval');
      messenger.showSnackBar(
        SnackBar(
            content: Text('Join request sent to ${endpointName ?? 'host'}')),
      );
      return;
    }

    final workspace = await workspaceService.ensureWorkspace(
      name: _joinedWorkspaceName ?? 'Connected Workspace',
      description: 'Offline workspace joined from nearby discovery',
      visibility: 'Local',
      password: '',
      type: 'Connected',
      icon: 'workspaces',
      ownerName: 'Nearby Host',
      ownerDeviceId: ownerDeviceId,
    );
    await workspaceService.setActiveWorkspace(workspace.id);
    if (!mounted) return;
    setState(() {
      _joinedWorkspaceName = workspace.name;
      _joinedWorkspaceType = 'Connected';
      _joinedOwnerName = 'Nearby Host';
      _joinedMembers = workspace.members.length;
      _joinedResources = workspace.resources.length;
    });
    _addActivity('Workspace joined', 'You connected to a nearby workspace',
        icon: Icons.login_rounded);
    _pushNotification(
        'Workspace joined', 'You are now connected to a nearby workspace');
    _refreshLiveStats();
    _syncWorkspaceFromService();
    if (!mounted) return;
    navigator.push(MaterialPageRoute(
      builder: (_) => WorkspaceDashboardScreen(
        workspaceName: workspace.name,
        workspaceType: _joinedWorkspaceType,
        ownerName: _joinedOwnerName,
        members: _joinedMembers,
        resources: _joinedResources,
        isProtected: true,
      ),
    ));
  }
}

class _ActivityItem {
  final String title;
  final String description;
  final IconData icon;

  const _ActivityItem(
      {required this.title, required this.description, required this.icon});
}

class _NotificationItem {
  final String title;
  final String message;

  const _NotificationItem({required this.title, required this.message});
}
