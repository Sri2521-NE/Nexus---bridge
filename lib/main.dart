import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/discovery_service.dart';
import 'services/connection_service.dart';
import 'services/download_service.dart';
import 'services/profile_service.dart';
import 'services/workspace_service.dart';
import 'services/offline_session_service.dart';
import 'services/nearby_service.dart';
import 'services/workspace_session_manager.dart';
import 'screens/discovery_screen.dart';
import 'screens/main_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/workspace_dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[DEBUG_LOG] APP_STARTED');
  runApp(const NexusBridgeApp());
}

class NexusBridgeApp extends StatelessWidget {
  const NexusBridgeApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DiscoveryService()),
        ChangeNotifierProvider(create: (_) => ConnectionService()),
        ChangeNotifierProvider(create: (_) => DownloadService()),
        ChangeNotifierProvider(create: (_) => ProfileService()),
        ChangeNotifierProvider(create: (_) => WorkspaceService()),
        ChangeNotifierProvider(create: (_) => OfflineSessionService()),
        Provider(create: (_) => NearbyService()),
        ChangeNotifierProvider(
            create: (context) => WorkspaceSessionManager(
                  nearbyService: context.read<NearbyService>(),
                  workspaceService: context.read<WorkspaceService>(),
                  offlineSessionService: context.read<OfflineSessionService>(),
                )),
      ],
      child: MaterialApp(
        title: 'Nexus Bridge',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Roboto',
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF00D9FF),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF07111F),
          cardColor: const Color(0xFF121B2D),
          dividerColor: const Color(0xFF22304A),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF07111F),
            elevation: 0,
            centerTitle: true,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        home: const _Home(),
      ),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home({Key? key}) : super(key: key);

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  @override
  void initState() {
    super.initState();
    debugPrint('[DEBUG_LOG] PROVIDERS_CREATED');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final connectionService = context.read<ConnectionService>();
      final discoveryService = context.read<DiscoveryService>();
      final profileService = context.read<ProfileService>();
      final workspaceService = context.read<WorkspaceService>();
      final offlineSessionService = context.read<OfflineSessionService>();
      final workspaceSessionManager = context.read<WorkspaceSessionManager>();

      connectionService.loadSavedSessionToken();
      discoveryService.startDiscovery();
      connectionService.tryAutoReconnect();

      () async {
        await profileService.load();
        await workspaceService.load();
        await offlineSessionService.load();
        await workspaceSessionManager.load();
        try {
          debugPrint('[DEBUG_LOG] START_NEARBY_DISCOVERY_FROM_MAIN');
          await workspaceSessionManager.startNearbyDiscovery();
        } catch (e) {
          debugPrint('[DEBUG_LOG] startNearbyDiscovery failed: $e');
        }
      }();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<ConnectionService, ProfileService,
        WorkspaceSessionManager>(
      builder: (context, connectionService, profileService,
          workspaceSessionManager, _) {
        if (!profileService.profileReady &&
            !profileService.onboardingCompleted) {
          return const OnboardingScreen();
        }
        final restoredWorkspace = workspaceSessionManager.currentWorkspace;
        if (restoredWorkspace != null &&
            workspaceSessionManager.connectionState == 'connected' &&
            context.read<OfflineSessionService>().sessionActive) {
          return WorkspaceDashboardScreen(
            workspaceName: restoredWorkspace.name,
            workspaceType: restoredWorkspace.type,
            ownerName: restoredWorkspace.ownerName,
            members: restoredWorkspace.members.length,
            resources: restoredWorkspace.resources.length,
            isProtected: true,
          );
        }
        if (connectionService.isConnected) {
          return const MainScreen();
        }
        return const DiscoveryScreen();
      },
    );
  }
}
