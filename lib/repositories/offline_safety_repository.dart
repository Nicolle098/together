import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/offline_seed_data.dart';
import '../models/emergency_contact.dart';
import '../models/medical_profile.dart';
import '../models/safety_place.dart';

class OfflineSafetyRepository {
  const OfflineSafetyRepository();

  static const _shelterAssetPath = 'assets/data/shelters_ro_2026_03_09.json';
  static const _hospitalAssetPath = 'assets/data/hospitals_ro_ministry.json';
  static const _policeStationsAssetPath = 'lib/data/police_stations.csv';
  static const _mapEditsKey = 'temporary_map_edits_v1';
  static const _userHazardsKey = 'user_hazard_reports_v1';
  static const _pendingUploadsKey = 'pending_hazard_uploads_v1';
  static Future<List<SafetyPlace>>? _cachedSheltersFuture;
  static Future<List<SafetyPlace>>? _cachedHospitalsFuture;
  static Future<List<SafetyPlace>>? _cachedPoliceStationsFuture;

  Future<List<SafetyPlace>> loadMapPlaces() async {
    final shelters = await (_cachedSheltersFuture ??= _loadSheltersFromAsset());
    final hospitals =
        await (_cachedHospitalsFuture ??= _loadHospitalsFromAsset());
    final policeStations =
        await (_cachedPoliceStationsFuture ??= _loadPoliceStationsFromAsset());
    final userHazards = await loadUserHazards();
    final supportingPlaces = OfflineSeedData.nearbyPlaces
        .where(
          (place) =>
              place.category != SafetyPlaceCategory.shelter &&
              place.category != SafetyPlaceCategory.hospital &&
              place.category != SafetyPlaceCategory.police,
        )
        .toList();
    final combined = [
      ...shelters,
      ...hospitals,
      ...policeStations,
      ...supportingPlaces,
      ...userHazards,
    ];

    return _applyLocalEdits(combined);
  }

  // ── User hazard reports ────────────────────────────────────────────────────

  /// Persists a user-submitted hazard pin to local storage.
  Future<void> addUserHazard(SafetyPlace place) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await _readUserHazardsRaw(prefs);
    existing.add({
      'id': place.id,
      'name': place.name,
      'latitude': place.latitude,
      'longitude': place.longitude,
      'address': place.address,
      'notes': place.notes,
      'hazardTags': place.hazardTags,
      'lastVerified': place.lastVerified,
      if (place.expiresAt != null)
        'expiresAt': place.expiresAt!.toIso8601String(),
    });
    await prefs.setString(_userHazardsKey, jsonEncode(existing));
  }

  /// Loads all user-submitted hazard pins from local storage.
  Future<List<SafetyPlace>> loadUserHazards() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = await _readUserHazardsRaw(prefs);
    final now = DateTime.now();
    return raw.map((json) {
      final expiresRaw = json['expiresAt'] as String?;
      final expiresAt =
          expiresRaw != null ? DateTime.tryParse(expiresRaw) : null;
      return SafetyPlace(
        id: json['id'] as String,
        name: json['name'] as String,
        category: SafetyPlaceCategory.hazard,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        address: (json['address'] as String?) ?? '',
        accessibilityFeatures: const [],
        hazardTags: List<String>.from(
          (json['hazardTags'] as List<dynamic>?) ?? const [],
        ),
        lastVerified: (json['lastVerified'] as String?) ?? '',
        notes: (json['notes'] as String?) ?? '',
        isUserSubmitted: true,
        expiresAt: expiresAt,
      );
    }).where((p) => p.expiresAt == null || p.expiresAt!.isAfter(now)).toList();
  }

  Future<List<Map<String, dynamic>>> _readUserHazardsRaw(
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString(_userHazardsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  Future<SafetyPlace?> getPlaceById(String id) async {
    final places = await loadMapPlaces();
    for (final place in places) {
      if (place.id == id) {
        return place;
      }
    }

    return null;
  }

  Future<void> movePlace({
    required String placeId,
    required double latitude,
    required double longitude,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final edits = await _readMapEdits(prefs);
    final moved = Map<String, dynamic>.from(
      edits['moved'] as Map<String, dynamic>? ?? const {},
    );
    moved[placeId] = {
      'latitude': latitude,
      'longitude': longitude,
    };
    edits['moved'] = moved;
    await prefs.setString(_mapEditsKey, jsonEncode(edits));
  }

  Future<void> hidePlace(String placeId) async {
    final prefs = await SharedPreferences.getInstance();
    final edits = await _readMapEdits(prefs);
    final hidden = List<String>.from(
      edits['hidden'] as List<dynamic>? ?? const [],
    );
    if (!hidden.contains(placeId)) {
      hidden.add(placeId);
    }
    edits['hidden'] = hidden;
    await prefs.setString(_mapEditsKey, jsonEncode(edits));
  }

  Future<void> clearMapEdits() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_mapEditsKey);
  }

  // ── Pending upload queue ──────────────────────────────────────────────────

  /// Adds a hazard to the pending-upload queue. Called when an upload fails
  /// due to being offline so the sync can be retried later.
  Future<void> addPendingUpload(SafetyPlace place, {required String uid}) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await _readPendingRaw(prefs);
    // Avoid duplicates — replace if the same id is already queued.
    existing.removeWhere((m) => m['id'] == place.id);
    existing.add(_pendingToMap(place, uid: uid));
    await prefs.setString(_pendingUploadsKey, jsonEncode(existing));
  }

  /// Returns all hazards that are waiting to be synced to Firestore.
  Future<List<({SafetyPlace place, String uid})>> getPendingUploads() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = await _readPendingRaw(prefs);
    final result = <({SafetyPlace place, String uid})>[];
    for (final m in raw) {
      final place = _pendingFromMap(m);
      if (place == null) continue;
      result.add((place: place, uid: m['uid'] as String? ?? ''));
    }
    return result;
  }

  /// Removes successfully uploaded hazards from the pending queue by their IDs.
  Future<void> clearPendingUploads(List<String> syncedIds) async {
    if (syncedIds.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final existing = await _readPendingRaw(prefs);
    existing.removeWhere((m) => syncedIds.contains(m['id']));
    await prefs.setString(_pendingUploadsKey, jsonEncode(existing));
  }

  Future<List<Map<String, dynamic>>> _readPendingRaw(
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString(_pendingUploadsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.cast<Map<String, dynamic>>();
    } catch (_) {}
    return [];
  }

  Map<String, dynamic> _pendingToMap(SafetyPlace place, {required String uid}) => {
        'id': place.id,
        'uid': uid,
        'name': place.name,
        'latitude': place.latitude,
        'longitude': place.longitude,
        'address': place.address,
        'notes': place.notes,
        'hazardTags': place.hazardTags,
        'lastVerified': place.lastVerified,
        if (place.expiresAt != null)
          'expiresAt': place.expiresAt!.toIso8601String(),
      };

  SafetyPlace? _pendingFromMap(Map<String, dynamic> json) {
    try {
      final lat = (json['latitude'] as num?)?.toDouble();
      final lng = (json['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      final expiresRaw = json['expiresAt'] as String?;
      return SafetyPlace(
        id: json['id'] as String,
        name: json['name'] as String,
        category: SafetyPlaceCategory.hazard,
        latitude: lat,
        longitude: lng,
        address: (json['address'] as String?) ?? '',
        accessibilityFeatures: const [],
        hazardTags: List<String>.from(
          (json['hazardTags'] as List<dynamic>?) ?? const [],
        ),
        lastVerified: (json['lastVerified'] as String?) ?? '',
        notes: (json['notes'] as String?) ?? '',
        isUserSubmitted: true,
        expiresAt: expiresRaw != null ? DateTime.tryParse(expiresRaw) : null,
      );
    } catch (_) {
      return null;
    }
  }

  List<EmergencyContact> getEmergencyContacts() =>
      OfflineSeedData.emergencyContacts;

  MedicalProfile getMedicalProfile() => OfflineSeedData.medicalProfile;

  List<String> getCommunicationCards() => OfflineSeedData.communicationCards;

  Future<List<SafetyPlace>> _loadSheltersFromAsset() async {
    final rawJson = await rootBundle.loadString(_shelterAssetPath);
    final decoded = jsonDecode(rawJson) as List<dynamic>;

    return decoded
        .cast<Map<String, dynamic>>()
        .map(_mapShelterToPlace)
        .where((place) => place.latitude.isFinite && place.longitude.isFinite)
        .toList();
  }

  Future<List<SafetyPlace>> _loadHospitalsFromAsset() async {
    final rawJson = await rootBundle.loadString(_hospitalAssetPath);
    final decoded = jsonDecode(rawJson) as List<dynamic>;

    return decoded
        .cast<Map<String, dynamic>>()
        .map(_mapHospitalToPlace)
        .where((place) => place.latitude.isFinite && place.longitude.isFinite)
        .toList();
  }

  Future<List<SafetyPlace>> _loadPoliceStationsFromAsset() async {
    final rawCsv = await rootBundle.loadString(_policeStationsAssetPath);
    final rows = _parseCsv(rawCsv);

    if (rows.isEmpty) {
      return const [];
    }

    final header = rows.first;
    final stations = <SafetyPlace>[];

    for (final row in rows.skip(1)) {
      if (row.every((value) => value.trim().isEmpty)) {
        continue;
      }

      final json = <String, String>{};
      for (var index = 0; index < header.length; index++) {
        json[header[index]] = index < row.length ? row[index] : '';
      }

      final station = _mapPoliceStationToPlace(json);
      if (station.latitude.isFinite && station.longitude.isFinite) {
        stations.add(station);
      }
    }

    return stations;
  }

  Future<List<SafetyPlace>> _applyLocalEdits(List<SafetyPlace> places) async {
    final prefs = await SharedPreferences.getInstance();
    final edits = await _readMapEdits(prefs);
    final hidden = List<String>.from(edits['hidden'] as List<dynamic>? ?? []);
    final moved = Map<String, dynamic>.from(
      edits['moved'] as Map<String, dynamic>? ?? const {},
    );

    return places
        .where((place) => !hidden.contains(place.id))
        .map((place) {
          final override = moved[place.id];
          if (override is Map<String, dynamic>) {
            final latitude = (override['latitude'] as num?)?.toDouble();
            final longitude = (override['longitude'] as num?)?.toDouble();
            if (latitude != null && longitude != null) {
              return place.copyWith(
                latitude: latitude,
                longitude: longitude,
                notes: '${place.notes} Temporary local pin adjustment applied.',
              );
            }
          }
          return place;
        })
        .toList();
  }

  Future<Map<String, dynamic>> _readMapEdits(SharedPreferences prefs) async {
    final raw = prefs.getString(_mapEditsKey);
    if (raw == null || raw.isEmpty) {
      return {
        'hidden': <String>[],
        'moved': <String, dynamic>{},
      };
    }

    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    return {
      'hidden': <String>[],
      'moved': <String, dynamic>{},
    };
  }

  SafetyPlace _mapShelterToPlace(Map<String, dynamic> json) {
    final city = (json['city'] as String? ?? '').trim();
    final address = (json['address'] as String? ?? '').trim();
    final shelterType = (json['shelterType'] as String? ?? '').trim();
    final functionalState = (json['functionalState'] as String? ?? '').trim();
    final capacity = json['capacity'] as int?;

    return SafetyPlace(
      id: json['id'] as String,
      name: _buildShelterName(city: city, address: address),
      category: SafetyPlaceCategory.shelter,
      latitude: (json['latitude'] as num?)?.toDouble() ?? double.nan,
      longitude: (json['longitude'] as num?)?.toDouble() ?? double.nan,
      address: address,
      accessibilityFeatures: _buildShelterTags(
        shelterType: shelterType,
        capacity: capacity,
      ),
      hazardTags: functionalState == 'non_functional'
          ? ['Unavailable shelter']
          : const [],
      lastVerified: 'Official list updated ${json['sourceUpdatedAt']}',
      notes: _buildShelterNotes(
        city: city,
        shelterType: shelterType,
        capacity: capacity,
        functionalState: functionalState,
      ),
      isOfflineAvailable: json['isOfflineAvailable'] as bool? ?? true,
      city: city,
      countyCode: json['countyCode'] as String?,
      shelterType: shelterType,
      capacity: capacity,
      functionalState: functionalState,
    );
  }

  SafetyPlace _mapHospitalToPlace(Map<String, dynamic> json) {
    final name = (json['name'] as String? ?? '').trim();
    final address = (json['address'] as String? ?? '').trim();

    return SafetyPlace(
      id: json['id'] as String,
      name: name.isEmpty ? 'Hospital' : name,
      category: SafetyPlaceCategory.hospital,
      latitude: (json['latitude'] as num?)?.toDouble() ?? double.nan,
      longitude: (json['longitude'] as num?)?.toDouble() ?? double.nan,
      address: address,
      accessibilityFeatures: const ['Medical support'],
      hazardTags: const [],
      lastVerified: 'Ministry page snapshot ${json['sourceUpdatedAt']}',
      notes: 'Official hospital entry imported from the Ministry of Health list.',
      isOfflineAvailable: json['isOfflineAvailable'] as bool? ?? true,
    );
  }

  SafetyPlace _mapPoliceStationToPlace(Map<String, String> json) {
    final id = (json['id'] ?? '').trim();
    final name = (json['name'] ?? '').trim();
    final address = (json['address'] ?? '').trim();
    final phone = (json['phone'] ?? '').trim();
    final commander = (json['commander'] ?? '').trim();
    final city = (json['city'] ?? '').trim();
    final county = (json['county'] ?? '').trim();
    final sourceUpdatedAt = (json['sourceUpdatedAt'] ?? '').trim();
    final sourceUrl = (json['sourceUrl'] ?? '').trim();

    return SafetyPlace(
      id: id.isEmpty ? 'police-${name.toLowerCase().replaceAll(' ', '-')}' : id,
      name: name.isEmpty ? 'Police station' : name,
      category: SafetyPlaceCategory.police,
      latitude: double.tryParse((json['latitude'] ?? '').trim()) ?? double.nan,
      longitude:
          double.tryParse((json['longitude'] ?? '').trim()) ?? double.nan,
      address: address,
      accessibilityFeatures: const ['In-person assistance'],
      hazardTags: const [],
      lastVerified: sourceUpdatedAt.isEmpty
          ? 'Official police directory'
          : 'Official list updated $sourceUpdatedAt',
      notes: _buildPoliceNotes(
        city: city,
        county: county,
        phone: phone,
        commander: commander,
        sourceUrl: sourceUrl,
      ),
      isOfflineAvailable: true,
      city: city,
      countyCode: county,
    );
  }

  String _buildShelterName({
    required String city,
    required String address,
  }) {
    final normalizedAddress = address.replaceAll('–', '-');
    final segments = normalizedAddress.split('-');
    final candidate = segments.first.trim();

    if (candidate.isNotEmpty && candidate.length <= 54) {
      return candidate;
    }

    return city.isEmpty ? 'Civil protection shelter' : '$city shelter';
  }

  List<String> _buildShelterTags({
    required String shelterType,
    required int? capacity,
  }) {
    final tags = <String>[];

    if (shelterType.isNotEmpty) {
      tags.add(_labelForShelterType(shelterType));
    }
    if (capacity != null) {
      tags.add('Capacity $capacity');
    }

    return tags;
  }

  String _buildShelterNotes({
    required String city,
    required String shelterType,
    required int? capacity,
    required String functionalState,
  }) {
    final parts = <String>[];

    if (city.isNotEmpty) {
      parts.add('Shelter in $city.');
    }
    if (shelterType.isNotEmpty) {
      parts.add('Type: ${_labelForShelterType(shelterType)}.');
    }
    if (capacity != null) {
      parts.add('Listed capacity: $capacity people.');
    }
    if (functionalState.isNotEmpty) {
      parts.add('Status: ${_labelForFunctionalState(functionalState)}.');
    }

    return parts.join(' ');
  }

  String _labelForShelterType(String shelterType) {
    switch (shelterType) {
      case 'public':
        return 'Public shelter';
      case 'private':
        return 'Private shelter';
      default:
        return shelterType;
    }
  }

  String _labelForFunctionalState(String functionalState) {
    switch (functionalState) {
      case 'functional':
        return 'Functional';
      case 'partially_functional':
        return 'Partially functional';
      case 'non_functional':
        return 'Non-functional';
      case 'n/a':
        return 'Status unavailable';
      default:
        return functionalState;
    }
  }

  String _buildPoliceNotes({
    required String city,
    required String county,
    required String phone,
    required String commander,
    required String sourceUrl,
  }) {
    final parts = <String>[];

    if (city.isNotEmpty || county.isNotEmpty) {
      final location = [city, county].where((value) => value.isNotEmpty).join(', ');
      parts.add('Police support point in $location.');
    }
    if (phone.isNotEmpty && phone != '-') {
      parts.add('Phone: $phone.');
    }
    if (commander.isNotEmpty && commander != '-') {
      parts.add('Commander: $commander.');
    }
    if (sourceUrl.isNotEmpty) {
      parts.add('Source: $sourceUrl.');
    }

    return parts.join(' ');
  }

  List<List<String>> _parseCsv(String input) {
    final rows = <List<String>>[];
    final row = <String>[];
    final cell = StringBuffer();
    var inQuotes = false;

    for (var index = 0; index < input.length; index++) {
      final char = input[index];

      if (char == '"') {
        if (inQuotes && index + 1 < input.length && input[index + 1] == '"') {
          cell.write('"');
          index++;
        } else {
          inQuotes = !inQuotes;
        }
        continue;
      }

      if (!inQuotes && char == ',') {
        row.add(cell.toString());
        cell.clear();
        continue;
      }

      if (!inQuotes && (char == '\n' || char == '\r')) {
        if (char == '\r' && index + 1 < input.length && input[index + 1] == '\n') {
          index++;
        }
        row.add(cell.toString());
        cell.clear();
        if (row.isNotEmpty && !(row.length == 1 && row.first.isEmpty)) {
          rows.add(List<String>.from(row));
        }
        row.clear();
        continue;
      }

      cell.write(char);
    }

    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString());
      if (row.isNotEmpty && !(row.length == 1 && row.first.isEmpty)) {
        rows.add(List<String>.from(row));
      }
    }

    return rows;
  }
}
