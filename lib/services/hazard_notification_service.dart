import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart' show Firebase;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:latlong2/latlong.dart';

/// Manages local notifications and FCM token registration for hazard alerts.
///
/// Call [initialize] once at app start (before Firebase).
/// Call [requestPermission] after the user is confirmed as registered.
/// Call [startListening] with the user's location to begin proximity alerts.
/// Call [stopListening] in the screen's dispose().
/// Call [showHazardAlert] to trigger a system notification with sound.
/// Call [registerFcmToken] to persist the FCM token for server-side targeting.
class HazardNotificationService {
  HazardNotificationService._();

  // flutter_local_notifications v21 is a singleton factory.
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  // Must match the channel ID declared in AndroidManifest meta-data.
  static const _channelId = 'hazard_alerts';
  static const _channelName = 'Nearby Hazard Alerts';
  static const _channelDesc =
      'Alerts when community hazards are reported near you';

  static const _databaseId = 'users';
  static const double _defaultRadiusKm = 500.0;

  // ── Firestore listener state ──────────────────────────────────────────────

  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  static LatLng? _userLocation;
  static double _radiusKm = _defaultRadiusKm;

  /// Records when we started listening so we skip pre-existing documents.
  static DateTime? _listenStartedAt;

  static FirebaseFirestore get _db => FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: _databaseId,
      );

  // ── Initialise ────────────────────────────────────────────────────────────

  static Future<void> initialize() async {
    if (_ready) return;

    // v21: initialize() takes named `settings` parameter.
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    // Create the high-importance channel once; Android is idempotent here.
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _ready = true;
  }

  // ── Permission ────────────────────────────────────────────────────────────

  /// Requests the POST_NOTIFICATIONS runtime permission (Android 13+).
  static Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  // ── Firestore proximity listener ──────────────────────────────────────────

  /// Begins listening to Firestore hazard reports. Any new report within
  /// [radiusKm] of [userLocation] triggers a local notification with sound.
  ///
  /// Safe to call multiple times — cancels the previous subscription first.
  /// Only new documents (added after this call) are considered.
  static void startListening(
    LatLng userLocation, {
    double radiusKm = _defaultRadiusKm,
  }) {
    _userLocation = userLocation;
    _radiusKm = radiusKm;
    _listenStartedAt = DateTime.now();

    _subscription?.cancel();
    _subscription = _db
        .collection('hazards')
        .snapshots()
        .listen(_onSnapshot, onError: (_) {});
  }

  /// Updates the user's position without restarting the Firestore stream.
  static void updateUserLocation(LatLng userLocation) {
    _userLocation = userLocation;
  }

  /// Cancels the Firestore listener. Call this in dispose().
  static Future<void> stopListening() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  static void _onSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final userLoc = _userLocation;
    if (userLoc == null) return;

    for (final change in snapshot.docChanges) {
      // Only react to newly added documents.
      if (change.type != DocumentChangeType.added) continue;

      final data = change.doc.data();
      if (data == null) continue;

      // Skip documents that already existed before we started listening.
      final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
      if (createdAt != null && _listenStartedAt != null) {
        if (createdAt.isBefore(_listenStartedAt!)) continue;
      }

      final lat = (data['latitude'] as num?)?.toDouble();
      final lng = (data['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      final distKm = _haversineKm(lat, lng, userLoc.latitude, userLoc.longitude);

      if (distKm > _radiusKm) continue;

      // BUG FIX: HazardSyncService writes 'name' and 'notes', not 'type'/'description'.
      final type = (data['name'] as String?)?.isNotEmpty == true
          ? data['name'] as String
          : ((data['hazardTags'] as List?)?.isNotEmpty == true
              ? (data['hazardTags'] as List).first as String
              : 'Hazard');
      final description = (data['notes'] as String?) ?? '';

      showHazardAlert(type: type, description: description, distanceKm: distKm);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Haversine great-circle distance in kilometres. Avoids the latlong2
  /// `Distance().as()` call which crashes on web DDC due to a const
  /// initializer issue with the default `DistanceHaversine` algorithm.
  static double _haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  // ── Show notification ─────────────────────────────────────────────────────

  /// Shows a max-importance system notification with sound for a nearby hazard.
  static Future<void> showHazardAlert({
    required String type,
    required String description,
    required double distanceKm,
  }) async {
    if (!_ready) return;

    final distanceText = distanceKm < 1.0
        ? '${(distanceKm * 1000).round()} m away'
        : '${distanceKm.toStringAsFixed(1)} km away';

    final body = '$distanceText · $description';

    // v21: show() takes all named parameters; notificationDetails is named.
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000,
      title: '⚠️ $type Reported Nearby',
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          ticker: 'Hazard nearby',
          category: AndroidNotificationCategory.alarm,
          styleInformation: BigTextStyleInformation(''),
        ),
      ),
    );
  }

  // ── FCM token ─────────────────────────────────────────────────────────────

  /// Requests FCM permission and stores the device token under `users/{uid}`
  /// in Firestore. Enables server-side targeted push notifications (the
  /// backend component needed for true out-of-app RoAlert delivery).
  static Future<void> registerFcmToken({required String uid}) async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        sound: true,
        badge: false,
      );

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      await _db.collection('users').doc(uid).set(
        {'fcmToken': token, 'tokenUpdatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    } catch (e, stackTrace) {
      // Best-effort; a token registration failure must not surface to the UI.
      debugPrint('FCM Token registration failed: $e\n$stackTrace');
    }
  }
}
