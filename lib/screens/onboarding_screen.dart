import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/profile_service.dart';
import 'discovery_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({Key? key}) : super(key: key);

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _index = 0;
  final TextEditingController _displayNameController =
      TextEditingController(text: 'Member');
  final TextEditingController _deviceNameController =
      TextEditingController(text: 'Local Device');

  @override
  void dispose() {
    _pageController.dispose();
    _displayNameController.dispose();
    _deviceNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          onPageChanged: (value) => setState(() => _index = value),
          children: [
            _buildWelcomePage(),
            _buildIntroPage(),
            _buildProfilePage(),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomePage() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                  colors: [Color(0xFF00D9FF), Color(0xFF7C4DFF)]),
            ),
            child: const Icon(Icons.workspaces_outline,
                size: 44, color: Colors.white),
          ),
          const SizedBox(height: 24),
          const Text('Nexus Bridge',
              style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 10),
          const Text('Create • Connect • Collaborate — Without Internet',
              style: TextStyle(fontSize: 16, color: Colors.white70)),
          const SizedBox(height: 30),
          const Text(
              'A premium offline digital workspace for nearby collaboration and resource sharing.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                  child: ElevatedButton(
                      onPressed: _next, child: const Text('Get Started'))),
              const SizedBox(width: 12),
              Expanded(
                  child: OutlinedButton(
                      onPressed: _skip, child: const Text('Learn More'))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIntroPage() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.offline_bolt_outlined,
              size: 64, color: Color(0xFF00D9FF)),
          const SizedBox(height: 18),
          const Text('Offline Workspace',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 12),
          const Text(
              'Create workspaces, invite nearby members, and share resources locally with no internet required.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          _buildFeatureTile(Icons.folder_copy_outlined, 'Resources',
              'Documents, videos, audio, images and folders'),
          const SizedBox(height: 10),
          _buildFeatureTile(Icons.groups_outlined, 'Collaboration',
              'Members, roles, permissions and activity tracking'),
          const SizedBox(height: 10),
          _buildFeatureTile(Icons.security_outlined, 'Local Privacy',
              'Everything stays on your device and nearby peers'),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                  child: OutlinedButton(
                      onPressed: _back, child: const Text('Back'))),
              const SizedBox(width: 12),
              Expanded(
                  child: ElevatedButton(
                      onPressed: _next, child: const Text('Continue'))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfilePage() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Create Local Profile',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 12),
          const Text('This is stored locally and persists after restart.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
          TextField(
              controller: _displayNameController,
              decoration: const InputDecoration(labelText: 'Display Name')),
          const SizedBox(height: 12),
          TextField(
              controller: _deviceNameController,
              decoration: const InputDecoration(labelText: 'Device Name')),
          const SizedBox(height: 24),
          ElevatedButton.icon(
              onPressed: _finishProfile,
              icon: const Icon(Icons.check),
              label: const Text('Continue to Workspace')),
          const SizedBox(height: 12),
          TextButton(onPressed: _skip, child: const Text('Skip for now')),
        ],
      ),
    );
  }

  Widget _buildFeatureTile(IconData icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: const Color(0xFF121B2D),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF22304A))),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF00D9FF)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: Colors.white)),
                Text(subtitle,
                    style: const TextStyle(color: Colors.grey, fontSize: 12))
              ])),
        ],
      ),
    );
  }

  void _next() {
    if (_index < 2) {
      _pageController.animateToPage(_index + 1,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _back() {
    if (_index > 0) {
      _pageController.animateToPage(_index - 1,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  Future<void> _skip() async {
    final profileService = context.read<ProfileService>();
    await profileService.markOnboardingComplete();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const _HomeRedirect()));
  }

  Future<void> _finishProfile() async {
    final profileService = context.read<ProfileService>();
    final profile = LocalProfile(
      displayName: _displayNameController.text.trim().isEmpty
          ? 'Member'
          : _displayNameController.text.trim(),
      deviceName: _deviceNameController.text.trim().isEmpty
          ? 'Local Device'
          : _deviceNameController.text.trim(),
      deviceId: 'offline-${DateTime.now().millisecondsSinceEpoch}',
      theme: 'Dark',
      language: 'English',
    );
    await profileService.saveProfile(profile);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const _HomeRedirect()));
  }
}

class _HomeRedirect extends StatelessWidget {
  const _HomeRedirect({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const DiscoveryScreen();
  }
}
