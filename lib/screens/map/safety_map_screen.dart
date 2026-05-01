import 'dart:async' show unawaited;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../map/tile_cache_provider.dart';
import '../../models/safety_place.dart';
import '../../repositories/offline_safety_repository.dart';
import '../../services/hazard_cache_service.dart';
import '../../services/hazard_notification_service.dart';
import '../../services/hazard_sync_service.dart';
import '../../theme/app_theme.dart';
import 'report_hazard_sheet.dart';

class SafetyMapScreen extends StatefulWidget {
  const SafetyMapScreen({super.key, this.firebaseReady = false});

  /// Whether Firebase was successfully initialized on this platform/run.
  /// When false, auth checks always return guest and Firestore is never called.
  final bool firebaseReady;

  @override
  State<SafetyMapScreen> createState() => _SafetyMapScreenState();
}

class _SafetyMapScreenState extends State<SafetyMapScreen> {
  static final LatLng _fallbackCenter = LatLng(44.4479, 26.0979); // București
  static const int _maxRenderedShelters = 250; // keeps marker count manageable

  final _repository = const OfflineSafetyRepository();
  final _syncService = const HazardSyncService();
  final _cacheService = const HazardCacheService();
  final _mapController = MapController();

  final List<SafetyPlace> _allPlaces = [];

  List<SafetyPlace> _localPlaces = [];
  late final Map<String, bool> _filters;

  LatLng? _userLocation;
  String _locationLabel = 'Checking location access...';
  bool _loadingLocation = true;
  bool _loadingPlaces = true;

  bool _reportMode = false;

  SafetyPlace? _selectedPlace;
  CachedTileProvider? _tileProvider;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _filters = {
      'shelter': true,
      'hospital': true,
      'pharmacy': true,
      'police': true,
      'fire': false,
      'accessibility': true,
      'hazards': true,
    };
    _loadPlaces();
    _loadCurrentLocation();
    _initTileCache();
    if (widget.firebaseReady && _isRegisteredUser) {
      HazardNotificationService.requestPermission();
    }
  }

  @override
  void dispose() {
    if (widget.firebaseReady) {
      HazardNotificationService.stopListening();
    }
    super.dispose();
  }

  Future<void> _initTileCache() async {
    final provider = await CachedTileProvider.create();
    if (mounted) setState(() => _tileProvider = provider);
  }

  // ── Data loading ─────────────────────────────────────────────────────────────

  Future<void> _loadPlaces() async {
    setState(() => _loadingPlaces = true);

    try {
      // ── Phase 1: show local + cached data immediately ────────────────────
      // Loads the static offline pack (shelters, hospitals, user hazards) and
      // the last-known community hazard pins from the local JSON cache.
      // This is fast (~0 ms I/O) so the map is useful even before the network
      // responds.
      final local = await _repository.loadMapPlaces();
      final cached = await _cacheService.load();

      _localPlaces = local;

      // Deduplicate: local pack wins if an ID appears in both.
      final localIds = {for (final p in local) p.id};
      final newCached =
          cached.where((p) => !localIds.contains(p.id)).toList();
      final phase1 = [...local, ...newCached];

      if (!mounted) return;
      setState(() {
        _allPlaces
          ..clear()
          ..addAll(phase1);
        _loadingPlaces = false;
        _selectedPlace = _selectedPlace == null
            ? _pickDefaultSelectedPlace(phase1)
            : _pickSelectedOrFallback(phase1, _selectedPlace!.id);
      });

      // ── Phase 2: background refresh ───────────────────────────────────────
      // Push any offline-queued pins, then fetch fresh community hazards from
      // Firestore and silently update the map + cache. The user sees the map
      // immediately; the refresh happens behind the scenes.
      unawaited(_syncPendingUploads());
      if (_isRegisteredUser) {
        unawaited(_refreshCommunityHazards());
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPlaces = false);
    }
  }

  Future<void> _refreshCommunityHazards() async {
    try {
      final fresh = await _syncService
          .fetchCommunityHazards()
          .timeout(const Duration(seconds: 8));

      unawaited(_cacheService.save(fresh));

      if (!mounted) return;

      final localIds = {for (final p in _localPlaces) p.id};
      final newRemote =
          fresh.where((p) => !localIds.contains(p.id)).toList();
      final merged = [..._localPlaces, ...newRemote];

      setState(() {
        _allPlaces
          ..clear()
          ..addAll(merged);
        _selectedPlace = _selectedPlace == null
            ? _pickDefaultSelectedPlace(merged)
            : _pickSelectedOrFallback(merged, _selectedPlace!.id);
      });
    } catch (_) {
      // Network unavailable or Firestore not yet enabled — ignore.
      // The cache loaded in phase 1 remains visible.
    }
  }

  SafetyPlace? _pickSelectedOrFallback(
    List<SafetyPlace> places,
    String placeId,
  ) {
    for (final place in places) {
      if (place.id == placeId) return place;
    }
    return _pickDefaultSelectedPlace(places);
  }

  SafetyPlace? _pickDefaultSelectedPlace(List<SafetyPlace> places) {
    if (places.isEmpty) return null;
    for (final place in places) {
      if (place.category == SafetyPlaceCategory.shelter) return place;
    }
    return places.first;
  }

  // ── Pending upload sync ───────────────────────────────────────────────────────

  /// Tries to upload any hazards that were queued while offline.
  /// Silently no-ops if Firebase is not ready or the user is not logged in.
  Future<void> _syncPendingUploads() async {
    if (!_isRegisteredUser) return;
    try {
      final pending = await _repository.getPendingUploads();
      if (pending.isEmpty) return;

      final places = pending.map((r) => r.place).toList();
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final synced = await _syncService.syncPendingUploads(places, uid: uid);

      if (synced.isNotEmpty) {
        await _repository.clearPendingUploads(synced);
        if (mounted && synced.length == pending.length) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${synced.length} offline hazard ${synced.length == 1 ? 'pin' : 'pins'} synced to the community map.',
              ),
            ),
          );
        }
      }
    } catch (_) {
      // Best-effort — will retry next time the screen loads.
    }
  }

  // ── Location ─────────────────────────────────────────────────────────────────

  Future<void> _loadCurrentLocation() async {
    setState(() {
      _loadingLocation = true;
      _locationLabel = 'Checking location access...';
    });

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      setState(() {
        _loadingLocation = false;
        _locationLabel = 'Location is off. Offline places are still ready.';
      });
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      setState(() {
        _loadingLocation = false;
        _locationLabel = 'Location permission denied. Showing offline pack.';
      });
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final userLocation = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() {
        _userLocation = userLocation;
        _loadingLocation = false;
        _locationLabel = 'GPS active. Distances use your current position.';
      });
      // Schedule the map move after the current frame — controller isn't ready until the map widget renders
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(userLocation, 14.2);
      });
      if (widget.firebaseReady && _isRegisteredUser) {
        HazardNotificationService.startListening(userLocation, radiusKm: 5.0);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingLocation = false;
        _locationLabel = 'Could not fetch GPS. Using the offline center.';
      });
    }
  }

  // ── Auth helpers ──────────────────────────────────────────────────────────────

  /// Returns true only when Firebase is ready **and** a verified user is
  /// signed in. Guarding on [widget.firebaseReady] prevents calling
  /// FirebaseAuth on platforms where Firebase was never initialized.
  bool get _isRegisteredUser {
    if (!widget.firebaseReady) return false;
    try {
      final user = FirebaseAuth.instance.currentUser;
      return user != null && user.emailVerified;
    } catch (_) {
      return false;
    }
  }

  // ── Filters and selection ─────────────────────────────────────────────────────

  List<SafetyPlace> get _visiblePlaces {
    final filteredPlaces = _allPlaces.where((place) {
      switch (place.category) {
        case SafetyPlaceCategory.shelter:
          return _filters['shelter']!;
        case SafetyPlaceCategory.hospital:
          return _filters['hospital']!;
        case SafetyPlaceCategory.pharmacy:
          return _filters['pharmacy']!;
        case SafetyPlaceCategory.police:
          return _filters['police']!;
        case SafetyPlaceCategory.fireStation:
          return _filters['fire']!;
        case SafetyPlaceCategory.accessibleToilet:
          return _filters['accessibility']!;
        case SafetyPlaceCategory.hazard:
          return _filters['hazards']!;
      }
    }).toList();

    final shelters = <SafetyPlace>[];
    final otherPlaces = <SafetyPlace>[];
    for (final place in filteredPlaces) {
      if (place.category == SafetyPlaceCategory.shelter) {
        shelters.add(place);
      } else {
        otherPlaces.add(place);
      }
    }

    final anchor = _userLocation ?? _fallbackCenter;
    shelters.sort(
      (l, r) => _distanceFrom(anchor, l).compareTo(_distanceFrom(anchor, r)),
    );

    final places = [
      ...shelters.take(_maxRenderedShelters),
      ...otherPlaces,
    ];

    if (_userLocation != null) {
      places.sort((a, b) => _distanceTo(a).compareTo(_distanceTo(b)));
    }

    return places;
  }

  int get _visibleHazardCount => _visiblePlaces
      .where((p) => p.category == SafetyPlaceCategory.hazard)
      .length;

  int get _visibleAccessibleCount => _visiblePlaces
      .where(
        (p) =>
            p.category == SafetyPlaceCategory.accessibleToilet ||
            p.accessibilityFeatures.isNotEmpty,
      )
      .length;

  void _toggleFilter(String key) {
    setState(() {
      _filters[key] = !_filters[key]!;
      if (_selectedPlace != null &&
          !_visiblePlaces.contains(_selectedPlace)) {
        _selectedPlace =
            _visiblePlaces.isEmpty ? null : _visiblePlaces.first;
      }
    });
  }

  void _selectPlace(SafetyPlace place) {
    setState(() => _selectedPlace = place);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _mapController.move(LatLng(place.latitude, place.longitude), 15.1);
      }
    });
  }

  void _centerOnUser() {
    if (_userLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enable location to center on your position.'),
        ),
      );
      return;
    }
    _mapController.move(_userLocation!, 14.6);
  }

  // ── Report flow ───────────────────────────────────────────────────────────────

  /// Entry point for the report button.
  /// Checks auth before entering report-placement mode.
  void _openReport() {
    if (!_isRegisteredUser) {
      _showSignInRequiredDialog();
      return;
    }

    setState(() => _reportMode = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tap the map to mark the hazard location.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _showSignInRequiredDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: const Text('Sign In Required'),
        content: const Text(
          'Reporting hazards is only available to registered users. '
          'Sign in to help keep your community safe.',
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pushNamed('/auth');
            },
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
  }

  Future<void> _placeReportPin(LatLng point) async {
    setState(() => _reportMode = false);

    final place = await showModalBottomSheet<SafetyPlace?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ReportHazardSheet(location: point),
    );

    if (!mounted) return;

    if (place != null) {
      // Always persist locally first so the pin appears immediately and
      // survives offline sessions.
      await _repository.addUserHazard(place);

      if (_isRegisteredUser) {
        try {
          final user = FirebaseAuth.instance.currentUser!;
          // Force-refresh the ID token so Firestore receives the latest
          // email_verified claim — without this the token can be stale.
          await user.getIdToken(true);
          await _syncService
              .uploadHazard(place, uid: user.uid)
              .timeout(const Duration(seconds: 10));
        } catch (_) {
          // Offline or transient failure — queue for later sync.
          await _repository.addPendingUpload(
            place,
            uid: FirebaseAuth.instance.currentUser!.uid,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Pin saved on your device. It will sync to the community map when you\'re back online.',
                ),
                duration: Duration(seconds: 5),
              ),
            );
          }
        }
      }

      await _loadPlaces();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hazard pin added. Thank you for reporting.'),
          ),
        );
      }
    }
  }

  void _handleMapTap(LatLng point) {
    if (_reportMode) {
      _placeReportPin(point);
      return;
    }
    setState(() => _selectedPlace = null);
  }

  // ── Distance helpers ──────────────────────────────────────────────────────────

  double _distanceTo(SafetyPlace place) {
    if (_userLocation == null) return double.infinity;
    return _distanceFrom(_userLocation!, place);
  }

  double _distanceFrom(LatLng point, SafetyPlace place) {
    return Geolocator.distanceBetween(
      point.latitude,
      point.longitude,
      place.latitude,
      place.longitude,
    );
  }

  String _distanceLabelFor(SafetyPlace place) {
    final d = _distanceTo(place);
    if (d.isFinite) {
      return d < 1000
          ? '${d.round()} m away'
          : '${(d / 1000).toStringAsFixed(1)} km away';
    }
    return place.distanceLabel ?? 'Offline pack item';
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final visiblePlaces = _visiblePlaces;
    final isBusy = _loadingLocation || _loadingPlaces;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety Map'),
        backgroundColor: Colors.transparent,
        foregroundColor: TogetherTheme.deepOcean,
        actions: [
          IconButton(
            tooltip: 'Refresh location',
            onPressed: _loadCurrentLocation,
            icon: isBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.my_location_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          child: Column(
            children: [
              _MapStatusBar(
                locationLabel: _loadingPlaces
                    ? 'Loading the Romania shelter dataset for offline use...'
                    : _locationLabel,
                visibleCount: visiblePlaces.length,
                accessibleCount: _visibleAccessibleCount,
                hazardCount: _visibleHazardCount,
                shelterCount: _allPlaces
                    .where((p) => p.category == SafetyPlaceCategory.shelter)
                    .length,
                reportMode: _reportMode,
              ),
              const SizedBox(height: 14),
              _FilterStrip(filters: _filters, onToggle: _toggleFilter),
              const SizedBox(height: 14),
              Expanded(
                child: _loadingPlaces
                    ? const _MapLoadingState()
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Stack(
                          children: [
                            FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                initialCenter:
                                    _userLocation ?? _fallbackCenter,
                                initialZoom: 13.8,
                                onTap: (_, point) =>
                                    _handleMapTap(point),
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName:
                                      'com.together.safety',
                                  tileProvider: _tileProvider ??
                                      NetworkTileProvider(),
                                ),
                                MarkerLayer(
                                  markers: _buildMarkers(visiblePlaces),
                                ),
                                const RichAttributionWidget(
                                  alignment:
                                      AttributionAlignment.bottomLeft,
                                  attributions: [
                                    TextSourceAttribution(
                                      'OpenStreetMap contributors',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Positioned(
                              right: 14,
                              top: 14,
                              child: Column(
                                children: [
                                  _MapActionButton(
                                    icon: Icons.my_location_rounded,
                                    label: 'Center',
                                    onTap: _centerOnUser,
                                  ),
                                  const SizedBox(height: 10),
                                  _MapActionButton(
                                    icon: Icons.add_location_alt_rounded,
                                    label: 'Report',
                                    onTap: _openReport,
                                    highlighted: _reportMode,
                                  ),
                                ],
                              ),
                            ),
                            Positioned(
                              left: 14,
                              right: 14,
                              bottom: 14,
                              child: _selectedPlace == null
                                  ? _MapHintCard(
                                      visibleCount: visiblePlaces.length,
                                      reportMode: _reportMode,
                                    )
                                  : _CompactSelectedPlaceCard(
                                      place: _selectedPlace!,
                                      distanceLabel: _distanceLabelFor(
                                        _selectedPlace!,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Marker> _buildMarkers(List<SafetyPlace> visiblePlaces) {
    final markers = visiblePlaces
        .map(
          (place) => Marker(
            point: LatLng(place.latitude, place.longitude),
            width: 88,
            height: 88,
            child: GestureDetector(
              onTap: () => _selectPlace(place),
              child: _MapMarker(
                place: place,
                isSelected: _selectedPlace?.id == place.id,
              ),
            ),
          ),
        )
        .toList();

    if (_userLocation != null) {
      markers.add(
        Marker(
          point: _userLocation!,
          width: 70,
          height: 70,
          child: const _UserLocationMarker(),
        ),
      );
    }

    return markers;
  }
}

// ── Status bar ────────────────────────────────────────────────────────────────

class _MapStatusBar extends StatelessWidget {
  const _MapStatusBar({
    required this.locationLabel,
    required this.visibleCount,
    required this.accessibleCount,
    required this.hazardCount,
    required this.shelterCount,
    required this.reportMode,
  });

  final String locationLabel;
  final int visibleCount;
  final int accessibleCount;
  final int hazardCount;
  final int shelterCount;
  final bool reportMode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.gps_fixed_rounded,
              size: 18,
              color: TogetherTheme.deepOcean,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                locationLabel,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: TogetherTheme.ink,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Showing $visibleCount places nearby • $accessibleCount accessible '
          '• $hazardCount hazards • $shelterCount shelters loaded',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: TogetherTheme.forest,
          ),
        ),
        if (reportMode) ...[
          const SizedBox(height: 8),
          const Text(
            'Report mode on. Tap anywhere on the map to mark the hazard location.',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFFB45309),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Filter strip ──────────────────────────────────────────────────────────────

class _FilterStrip extends StatelessWidget {
  const _FilterStrip({required this.filters, required this.onToggle});

  final Map<String, bool> filters;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    const items = [
      ('shelter', 'Shelters', Icons.shield_rounded),
      ('hospital', 'Hospitals', Icons.local_hospital_rounded),
      ('police', 'Police', Icons.local_police_rounded),
      ('accessibility', 'Accessibility', Icons.accessible_forward_rounded),
      ('hazards', 'Hazards', Icons.warning_amber_rounded),
    ];

    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: items.map((item) {
            final isSelected = filters[item.$1] ?? false;
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: FilterChip(
                selected: isSelected,
                showCheckmark: false,
                avatar: Icon(
                  item.$3,
                  size: 18,
                  color: isSelected
                      ? TogetherTheme.deepOcean
                      : TogetherTheme.ink,
                ),
                label: Text(item.$2),
                onSelected: (_) => onToggle(item.$1),
                selectedColor: TogetherTheme.mist,
                side: const BorderSide(color: Color(0xFFD3DCE4)),
                backgroundColor: Colors.white,
                labelStyle: TextStyle(
                  color: isSelected
                      ? TogetherTheme.deepOcean
                      : TogetherTheme.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Map markers ───────────────────────────────────────────────────────────────

class _MapMarker extends StatelessWidget {
  const _MapMarker({required this.place, required this.isSelected});

  final SafetyPlace place;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final background = _backgroundForCategory(place.category);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: isSelected ? 54 : 46,
          height: isSelected ? 54 : 46,
          decoration: BoxDecoration(
            color: background,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white,
              width: isSelected ? 4 : 3,
            ),
            boxShadow: [
              BoxShadow(
                color: background.withValues(alpha: 0.35),
                blurRadius: isSelected ? 18 : 12,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(
            _iconForCategory(place.category),
            color: Colors.white,
            size: isSelected ? 28 : 24,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            _shortLabelForCategory(place.category),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: TogetherTheme.deepOcean,
            ),
          ),
        ),
      ],
    );
  }
}

class _UserLocationMarker extends StatelessWidget {
  const _UserLocationMarker();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: TogetherTheme.accent,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
          boxShadow: [
            BoxShadow(
              color: TogetherTheme.accent.withValues(alpha: 0.3),
              blurRadius: 18,
              spreadRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Floating action buttons ───────────────────────────────────────────────────

class _MapActionButton extends StatelessWidget {
  const _MapActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: highlighted
          ? const Color(0xFFFDE8E8)
          : Colors.white.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            children: [
              Icon(
                icon,
                color: highlighted
                    ? const Color(0xFFB45309)
                    : TogetherTheme.deepOcean,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: highlighted
                      ? const Color(0xFFB45309)
                      : TogetherTheme.deepOcean,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bottom info cards ─────────────────────────────────────────────────────────

class _MapHintCard extends StatelessWidget {
  const _MapHintCard({
    required this.visibleCount,
    required this.reportMode,
  });

  final int visibleCount;
  final bool reportMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: reportMode
                  ? const Color(0xFFFDE8E8)
                  : TogetherTheme.mist,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              reportMode
                  ? Icons.add_location_alt_rounded
                  : Icons.touch_app_rounded,
              color: reportMode
                  ? const Color(0xFFB45309)
                  : TogetherTheme.deepOcean,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              visibleCount == 0
                  ? 'No markers match the current filters.'
                  : reportMode
                      ? 'Tap anywhere on the map to place your hazard report pin.'
                      : 'Tap a marker to inspect the location, accessibility details, or hazard notes.',
              style: const TextStyle(
                fontSize: 14,
                height: 1.35,
                color: TogetherTheme.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactSelectedPlaceCard extends StatelessWidget {
  const _CompactSelectedPlaceCard({
    required this.place,
    required this.distanceLabel,
  });

  final SafetyPlace place;
  final String distanceLabel;

  @override
  Widget build(BuildContext context) {
    final tags = [
      ...place.accessibilityFeatures,
      ...place.hazardTags,
    ].take(2).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _backgroundForCategory(place.category),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _iconForCategory(place.category),
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  place.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: TogetherTheme.deepOcean,
                    fontFamily: 'RobotoSlab',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_labelForCategory(place.category)} - $distanceLabel',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: TogetherTheme.forest,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  place.address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: TogetherTheme.ink,
                  ),
                ),
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    tags.join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: TogetherTheme.deepOcean,
                    ),
                  ),
                ],
                if (place.isUserSubmitted) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Community report',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFB45309),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Loading state ─────────────────────────────────────────────────────────────

class _MapLoadingState extends StatelessWidget {
  const _MapLoadingState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE7EEF4), Color(0xFFF6F1E8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Loading the Romania shelter dataset for the offline map...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: TogetherTheme.deepOcean,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Category helpers ──────────────────────────────────────────────────────────

IconData _iconForCategory(SafetyPlaceCategory category) {
  switch (category) {
    case SafetyPlaceCategory.shelter:
      return Icons.shield_rounded;
    case SafetyPlaceCategory.hospital:
      return Icons.local_hospital_rounded;
    case SafetyPlaceCategory.pharmacy:
      return Icons.local_pharmacy_rounded;
    case SafetyPlaceCategory.police:
      return Icons.local_police_rounded;
    case SafetyPlaceCategory.fireStation:
      return Icons.local_fire_department_rounded;
    case SafetyPlaceCategory.accessibleToilet:
      return Icons.accessible_forward_rounded;
    case SafetyPlaceCategory.hazard:
      return Icons.warning_amber_rounded;
  }
}

String _labelForCategory(SafetyPlaceCategory category) {
  switch (category) {
    case SafetyPlaceCategory.shelter:
      return 'Shelter';
    case SafetyPlaceCategory.hospital:
      return 'Hospital';
    case SafetyPlaceCategory.pharmacy:
      return 'Pharmacy';
    case SafetyPlaceCategory.police:
      return 'Police';
    case SafetyPlaceCategory.fireStation:
      return 'Fire station';
    case SafetyPlaceCategory.accessibleToilet:
      return 'Accessible';
    case SafetyPlaceCategory.hazard:
      return 'Hazard';
  }
}

String _shortLabelForCategory(SafetyPlaceCategory category) {
  switch (category) {
    case SafetyPlaceCategory.shelter:
      return 'Shelter';
    case SafetyPlaceCategory.hospital:
      return 'Hospital';
    case SafetyPlaceCategory.pharmacy:
      return 'Pharmacy';
    case SafetyPlaceCategory.police:
      return 'Police';
    case SafetyPlaceCategory.fireStation:
      return 'Fire';
    case SafetyPlaceCategory.accessibleToilet:
      return 'Access';
    case SafetyPlaceCategory.hazard:
      return 'Hazard';
  }
}

Color _backgroundForCategory(SafetyPlaceCategory category) {
  switch (category) {
    case SafetyPlaceCategory.shelter:
      return TogetherTheme.deepOcean;
    case SafetyPlaceCategory.hospital:
      return const Color(0xFFD24F52);
    case SafetyPlaceCategory.pharmacy:
      return TogetherTheme.forest;
    case SafetyPlaceCategory.police:
      return const Color(0xFF365FC9);
    case SafetyPlaceCategory.fireStation:
      return const Color(0xFFE36B2C);
    case SafetyPlaceCategory.accessibleToilet:
      return const Color(0xFF6D58D8);
    case SafetyPlaceCategory.hazard:
      return const Color(0xFFB45309);
  }
}
