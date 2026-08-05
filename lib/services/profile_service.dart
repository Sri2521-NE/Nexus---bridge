import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalProfile {
  final String displayName;
  final String deviceName;
  final String deviceId;
  final String theme;
  final String language;

  const LocalProfile({
    required this.displayName,
    required this.deviceName,
    required this.deviceId,
    required this.theme,
    required this.language,
  });

  Map<String, String> toMap() => {
        'displayName': displayName,
        'deviceName': deviceName,
        'deviceId': deviceId,
        'theme': theme,
        'language': language,
      };

  factory LocalProfile.fromMap(Map<String, dynamic> map) => LocalProfile(
        displayName: map['displayName']?.toString() ?? 'Member',
        deviceName: map['deviceName']?.toString() ?? 'Local Device',
        deviceId: map['deviceId']?.toString() ?? 'offline-device',
        theme: map['theme']?.toString() ?? 'Dark',
        language: map['language']?.toString() ?? 'English',
      );
}

class ProfileService extends ChangeNotifier {
  static const String _profileKey = 'local_profile';
  static const String _onboardingKey = 'onboarding_completed';
  static const String _profileReadyKey = 'profile_ready';

  LocalProfile? _profile;
  bool _onboardingCompleted = false;
  bool _profileReady = false;

  LocalProfile? get profile => _profile;
  bool get onboardingCompleted => _onboardingCompleted;
  bool get profileReady => _profileReady;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedProfile = prefs.getString(_profileKey);
    _onboardingCompleted = prefs.getBool(_onboardingKey) ?? false;
    _profileReady = prefs.getBool(_profileReadyKey) ?? false;

    if (savedProfile != null && savedProfile.isNotEmpty) {
      try {
        final decoded = Map<String, dynamic>.from(
          __decodeMap(savedProfile),
        );
        _profile = LocalProfile.fromMap(decoded);
      } catch (_) {
        _profile = null;
      }
    }

    notifyListeners();
  }

  Future<void> saveProfile(LocalProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, profile.toMap().toString());
    await prefs.setBool(_onboardingKey, true);
    await prefs.setBool(_profileReadyKey, true);
    _profile = profile;
    _onboardingCompleted = true;
    _profileReady = true;
    notifyListeners();
  }

  Future<void> markOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingKey, true);
    _onboardingCompleted = true;
    notifyListeners();
  }

  Future<void> clearProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profileKey);
    await prefs.remove(_onboardingKey);
    await prefs.remove(_profileReadyKey);
    _profile = null;
    _onboardingCompleted = false;
    _profileReady = false;
    notifyListeners();
  }

  Map<String, dynamic> __decodeMap(String raw) {
    final cleaned = raw.replaceAll('{', '').replaceAll('}', '').trim();
    if (cleaned.isEmpty) return <String, dynamic>{};

    final items = <String, dynamic>{};
    for (final part in cleaned.split(', ')) {
      final index = part.indexOf(':');
      if (index <= 0) continue;
      final key = part.substring(0, index).trim();
      final value = part.substring(index + 1).trim();
      items[key] = value;
    }
    return items;
  }
}
