import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart' show Firebase;

import '../models/safety_place.dart';

/// Handles reading and writing hazard reports to Firestore.
///
/// All methods are safe to call when offline — Firestore will throw a
/// [FirebaseException] or time-out, which callers must catch and handle
/// gracefully to preserve the app's offline-first character.
class HazardSyncService {
  const HazardSyncService();

  static const _collection = 'hazards';
  static const _databaseId = 'users';

  FirebaseFirestore get _db => FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: _databaseId,
      );

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Uploads a locally created hazard pin to Firestore.
  ///
  /// [uid] must be the authenticated user's UID — enforced by Security Rules.
  /// Uses the place's local [id] as the Firestore document ID so that the
  /// same pin is never duplicated on re-upload.
  Future<void> uploadHazard(SafetyPlace place, {required String uid}) {
    return _db.collection(_collection).doc(place.id).set({
      'id': place.id,
      'uid': uid,
      'name': place.name,
      'latitude': place.latitude,
      'longitude': place.longitude,
      'address': place.address,
      'notes': place.notes,
      'hazardTags': place.hazardTags,
      'lastVerified': place.lastVerified,
      'createdAt': FieldValue.serverTimestamp(),
      // expiresAt is stored as an explicit Timestamp so the fetch query can
      // filter on it with a simple inequality.
      if (place.expiresAt != null)
        'expiresAt': Timestamp.fromDate(place.expiresAt!),
    });
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Fetches active community hazard reports from Firestore.
  ///
  /// Only documents whose [expiresAt] is in the future are returned, so
  /// expired pins are automatically excluded. Documents that have no
  /// [expiresAt] field (legacy pins) are also excluded by this filter.
  ///
  /// Returns at most 500 reports ordered newest-first.
  /// Malformed documents are silently skipped.
  Future<List<SafetyPlace>> fetchCommunityHazards() async {
    final now = Timestamp.fromDate(DateTime.now());

    // BUG FIX: was `FirebaseFirestore.instance` (default DB); must use the
    // named 'users' database that uploadHazard() writes to.
    final snapshot = await _db
        .collection(_collection)
        .where('expiresAt', isGreaterThan: now)
        .orderBy('expiresAt', descending: false)
        .limit(500)
        .get();

    return snapshot.docs
        .map(_placeFromDoc)
        .whereType<SafetyPlace>()
        .toList();
  }

  /// Attempts to upload a batch of previously queued hazard reports.
  ///
  /// Returns the IDs of every pin that was successfully uploaded so the
  /// caller can remove them from the local pending queue.
  Future<List<String>> syncPendingUploads(
    List<SafetyPlace> pending, {
    required String uid,
  }) async {
    final synced = <String>[];
    for (final place in pending) {
      // Skip already-expired pins — no point uploading them.
      if (place.isExpired) {
        synced.add(place.id);
        continue;
      }
      try {
        await uploadHazard(place, uid: uid);
        synced.add(place.id);
      } catch (_) {
        // Leave in queue — will retry on next load.
      }
    }
    return synced;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  SafetyPlace? _placeFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    try {
      final data = doc.data();
      final lat = (data['latitude'] as num?)?.toDouble();
      final lng = (data['longitude'] as num?)?.toDouble();

      if (lat == null || lng == null || !lat.isFinite || !lng.isFinite) {
        return null;
      }

      final expiresAtTs = data['expiresAt'] as Timestamp?;

      return SafetyPlace(
        id: (data['id'] as String?)?.isNotEmpty == true
            ? data['id'] as String
            : doc.id,
        name: (data['name'] as String?)?.isNotEmpty == true
            ? data['name'] as String
            : 'Community hazard',
        category: SafetyPlaceCategory.hazard,
        latitude: lat,
        longitude: lng,
        address: (data['address'] as String?) ?? '',
        accessibilityFeatures: const [],
        hazardTags: List<String>.from(
          (data['hazardTags'] as List<dynamic>?) ?? const [],
        ),
        lastVerified: (data['lastVerified'] as String?) ?? '',
        notes: (data['notes'] as String?) ?? '',
        isUserSubmitted: true,
        expiresAt: expiresAtTs?.toDate(),
      );
    } catch (_) {
      return null;
    }
  }
}
