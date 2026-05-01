import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show Firebase;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists and exposes all user-configurable accessibility and display
/// preferences. Call [load] once at app start (before runApp) so the correct
/// theme is applied on the very first frame.
///
/// Other widgets listen with [ListenableBuilder] or [AnimatedBuilder]:
///
/// ```dart
/// ListenableBuilder(
///   listenable: AppSettings.instance,
///   builder: (context, _) => MaterialApp(
///     themeMode: AppSettings.instance.themeMode,
///     ...
///   ),
/// );
/// ```
class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  // ── Keys ──────────────────────────────────────────────────────────────────

  static const _kLowBattery = 'pref_low_battery';
  static const _kLargeText = 'pref_large_text';
  static const _kHighContrast = 'pref_high_contrast';
  static const _kVoiceGuidance = 'pref_voice_guidance';
  static const _kDisplayName = 'pref_display_name';

  // ── State ─────────────────────────────────────────────────────────────────

  bool _lowBattery = false;
  bool _largeText = false;
  bool _highContrast = false;
  bool _voiceGuidance = false;
  String _displayName = '';

  // ── Getters ───────────────────────────────────────────────────────────────

  /// Pure-black AMOLED theme. Saves meaningful battery on OLED screens.
  bool get lowBattery => _lowBattery;

  /// Increases the global text scale factor to 1.3× for readability under
  /// stress or for users with low vision.
  bool get largeText => _largeText;

  /// Switches to a high-contrast colour scheme (stronger borders, bolder ink)
  /// for users with low vision or in bright outdoor environments.
  bool get highContrast => _highContrast;

  /// When true, the AI assistant and emergency guides will be read aloud via
  /// TTS. The actual TTS engine is wired in the assistant layer; this flag is
  /// the single source of truth for whether audio output is wanted.
  bool get voiceGuidance => _voiceGuidance;

  /// Name shown to nearby P2P users. Falls back to 'Together user' if empty.
  String get displayName => _displayName.isNotEmpty ? _displayName : 'Together user';

  /// Raw stored value — empty string if the user hasn't set a name yet.
  String get displayNameRaw => _displayName;

  /// Text scale to apply via MediaQuery. 1.0 = normal, 1.3 = large.
  double get textScaleFactor => _largeText ? 1.3 : 1.0;

  // ── Load ──────────────────────────────────────────────────────────────────

  /// Reads persisted preferences from SharedPreferences. Designed to be
  /// awaited before [runApp] so the first frame uses the correct theme.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _lowBattery = prefs.getBool(_kLowBattery) ?? false;
    _largeText = prefs.getBool(_kLargeText) ?? false;
    _highContrast = prefs.getBool(_kHighContrast) ?? false;
    _voiceGuidance = prefs.getBool(_kVoiceGuidance) ?? false;
    _displayName = prefs.getString(_kDisplayName) ?? '';
    notifyListeners();
  }

  // ── Setters ───────────────────────────────────────────────────────────────

  Future<void> setLowBattery(bool value) =>
      _persist(_kLowBattery, value, () => _lowBattery = value);

  Future<void> setLargeText(bool value) =>
      _persist(_kLargeText, value, () => _largeText = value);

  Future<void> setHighContrast(bool value) =>
      _persist(_kHighContrast, value, () => _highContrast = value);

  Future<void> setVoiceGuidance(bool value) =>
      _persist(_kVoiceGuidance, value, () => _voiceGuidance = value);

  Future<void> setDisplayName(String value) async {
    _displayName = value.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDisplayName, _displayName);
    _pushNameToFirestore(_displayName); // fire-and-forget
  }

  /// Called once after sign-in. Pulls the saved display name from Firestore
  /// and updates local storage if the cloud value is newer / different.
  Future<void> syncFromFirestore(String uid) async {
    try {
      // Read the user's Firestore document, checking both server and local cache
      final doc = await _firestoreDb
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.serverAndCache));
      final cloudName = doc.data()?['displayName'] as String?;

      if (cloudName != null &&
          cloudName.isNotEmpty &&
          cloudName != _displayName) {
        _displayName = cloudName;
        notifyListeners();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kDisplayName, _displayName);
      }
    } catch (e) {
      debugPrint('AppSettings.syncFromFirestore: $e');
    }
  }

  void _pushNameToFirestore(String name) {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      _firestoreDb
          .collection('users')
          .doc(uid)
          .set({'displayName': name}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('AppSettings._pushNameToFirestore: $e');
    }
  }

  FirebaseFirestore get _firestoreDb => FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'users',
      );

  // ── Internal ──────────────────────────────────────────────────────────────

  Future<void> _persist(
    String key,
    bool value,
    VoidCallback update,
  ) async {
    update();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }
}
