// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexus_bridge/main.dart';
import 'package:nexus_bridge/screens/workspace_dashboard_screen.dart';
import 'package:nexus_bridge/services/workspace_service.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const NexusBridgeApp());

    // Verify that the app title is present.
    expect(find.text('Nexus Bridge'), findsOneWidget);
  });

  testWidgets('selecting a folder shows only its resources',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final workspaceService = WorkspaceService();
    await workspaceService.activateWorkspaceSession(
      workspaceId: 'folder-ui-workspace',
      name: 'Folder UI Workspace',
      description: 'test',
      visibility: 'Local',
      password: '',
      type: 'Connected',
      icon: 'workspaces',
      ownerName: 'Host',
      ownerDeviceId: 'host-app-id',
      localDeviceId: 'host-app-id',
      localMemberName: 'Host',
      localRole: WorkspaceRole.owner,
      folders: [
        WorkspaceFolder(
          id: 'folder-design',
          name: 'Design',
          parentId: '',
          createdAt: '2026-09-01T00:00:00.000',
        ),
      ],
      resources: [
        ResourceItem(
          id: 'resource-design',
          name: 'Design brief.pdf',
          kind: 'Document',
          sizeBytes: 512,
          path: '/files/design-brief.pdf',
          folderId: 'folder-design',
          createdAt: '2026-09-01T00:00:00.000',
        ),
        ResourceItem(
          id: 'resource-root',
          name: 'Shared notes.txt',
          kind: 'Document',
          sizeBytes: 256,
          path: '/files/shared-notes.txt',
          createdAt: '2026-09-01T00:00:00.000',
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: workspaceService,
        child: const MaterialApp(
          home: WorkspaceDashboardScreen(
            workspaceName: 'Folder UI Workspace',
            workspaceType: 'Connected',
            ownerName: 'Host',
            members: 1,
            resources: 2,
            isProtected: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Resources').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Design'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Design brief.pdf'), findsOneWidget);
    expect(find.text('Shared notes.txt'), findsNothing);
  });
}
