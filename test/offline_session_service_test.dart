import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexus_bridge/services/offline_session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('tracks host heartbeat and registered members', () async {
    SharedPreferences.setMockInitialValues({});
    final service = OfflineSessionService();

    await service.load();
    service.beginHostSession(
      workspaceId: 'workspace-1',
      workspaceName: 'Test Workspace',
      ownerName: 'Owner',
      ownerDeviceId: 'owner-1',
    );
    service.registerMember(
      deviceId: 'member-1',
      name: 'Ava',
      role: 'contributor',
      connected: true,
    );
    service.markHeartbeatReceived(from: 'member-1');

    expect(service.sessionActive, isTrue);
    expect(service.members.containsKey('member-1'), isTrue);
    expect(service.lastHeartbeatAt, isNotNull);
  });

  test('defers listener notifications until after the current frame', () async {
    SharedPreferences.setMockInitialValues({});
    final service = OfflineSessionService();
    await service.load();

    var notified = false;
    service.addListener(() {
      notified = true;
    });

    service.recordEvent('frame-safe notification');

    expect(notified, isFalse);

    await Future<void>.delayed(Duration.zero);
    expect(notified, isTrue);
  });
}
