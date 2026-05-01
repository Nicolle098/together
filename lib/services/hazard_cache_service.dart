import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart' show getApplicationDocumentsDirectory;

import '../models/safety_place.dart';

/// Persists community hazard pins to a local JSON file in the device's
/// documents directory.
///
/// This gives community pins the same offline resilience as the bundled
/// shelter and hospital datasets:
///
///   App opens → load cache instantly → display community pins
///             → fetch fresh data from Firestore in background
///             → overwrite cache → refresh map if anything changed
///
/// The cache file lives at `{documentsDir}/hazard_cache_v1.json`.
/// Expired pins are stripped from both [load] and [save] so the file
/// never grows with stale data.
class HazardCacheService {
  const HazardCacheService();

  static const _fileName = 'hazard_cache_v1.json';

  // ── Public API ────────────────────────────────────────────────────────────

  /// Loads cached community hazard pins.
  ///
  /// Returns an empty list if no cache exists yet or if the file is
  /// unreadable. Expired pins are filtered out automatically.
  /// On web (where `path_provider` is unsupported) always returns empty.
  Future<List<SafetyPlace>> load() async {
    if (kIsWeb) return const [];
    try {
      final file = await _cacheFile;
      if (!file.existsSync()) return const [];

      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return const [];

      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];

      final now = DateTime.now();
      return decoded
          .cast<Map<String, dynamic>>()
          .map(_fromMap)
          .whereType<SafetyPlace>()
          .where((p) => p.expiresAt == null || p.expiresAt!.isAfter(now))
          .toList();
    } catch (e) {
      debugPrint('HazardCacheService.load: $e');
      return const [];
    }
  }

  /// Writes [hazards] to the cache file, replacing any previous contents.
  ///
  /// Expired pins are stripped before writing so the file stays lean.
  /// Silently no-ops on write errors to avoid disrupting the UI.
  /// On web (where `path_provider` is unsupported) silently no-ops.
  Future<void> save(List<SafetyPlace> hazards) async {
    if (kIsWeb) return;
    try {
      final now = DateTime.now();
      final active = hazards
          .where((p) => p.expiresAt == null || p.expiresAt!.isAfter(now))
          .toList();

      final file = await _cacheFile;
      await file.writeAsString(
        jsonEncode(active.map(_toMap).toList()),
        flush: true,
      );
    } catch (e) {
      debugPrint('HazardCacheService.save: $e');
    }
  }

  /// Deletes the cache file. Useful for testing or a full data reset.
  Future<void> clear() async {
    if (kIsWeb) return;
    try {
      final file = await _cacheFile;
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  Future<File> get _cacheFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Map<String, dynamic> _toMap(SafetyPlace p) => {
        'id': p.id,
        'name': p.name,
        'latitude': p.latitude,
        'longitude': p.longitude,
        'address': p.address,
        'notes': p.notes,
        'hazardTags': p.hazardTags,
        'lastVerified': p.lastVerified,
        if (p.expiresAt != null) 'expiresAt': p.expiresAt!.toIso8601String(),
      };

  SafetyPlace? _fromMap(Map<String, dynamic> m) {
    try {
      final lat = (m['latitude'] as num?)?.toDouble();
      final lng = (m['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null || !lat.isFinite || !lng.isFinite) {
        return null;
      }
      final expiresRaw = m['expiresAt'] as String?;
      return SafetyPlace(
        id: (m['id'] as String?) ?? '',
        name: (m['name'] as String?) ?? 'Community hazard',
        category: SafetyPlaceCategory.hazard,
        latitude: lat,
        longitude: lng,
        address: (m['address'] as String?) ?? '',
        accessibilityFeatures: const [],
        hazardTags: List<String>.from(
          (m['hazardTags'] as List<dynamic>?) ?? const [],
        ),
        lastVerified: (m['lastVerified'] as String?) ?? '',
        notes: (m['notes'] as String?) ?? '',
        isUserSubmitted: true,
        expiresAt: expiresRaw != null ? DateTime.tryParse(expiresRaw) : null,
      );
    } catch (_) {
      return null;
    }
  }
}
