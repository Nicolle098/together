enum SafetyPlaceCategory {
  shelter,
  hospital,
  pharmacy,
  police,
  fireStation,
  accessibleToilet,
  hazard,
}

class SafetyPlace {
  const SafetyPlace({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.accessibilityFeatures,
    required this.hazardTags,
    required this.lastVerified,
    required this.notes,
    this.distanceLabel,
    this.isUserSubmitted = false,
    this.isOfflineAvailable = true,
    this.city,
    this.countyCode,
    this.shelterType,
    this.capacity,
    this.functionalState,
    this.expiresAt,
  });

  final String id;
  final String name;
  final SafetyPlaceCategory category;
  final double latitude;
  final double longitude;
  final String address;
  final String? distanceLabel;
  final List<String> accessibilityFeatures;
  final List<String> hazardTags;
  final String lastVerified;
  final String notes;
  final bool isUserSubmitted;
  final bool isOfflineAvailable;
  final String? city;
  final String? countyCode;
  final String? shelterType;
  final int? capacity;
  final String? functionalState;
  final DateTime? expiresAt;
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  SafetyPlace copyWith({
    String? id,
    String? name,
    SafetyPlaceCategory? category,
    double? latitude,
    double? longitude,
    String? address,
    String? distanceLabel,
    List<String>? accessibilityFeatures,
    List<String>? hazardTags,
    String? lastVerified,
    String? notes,
    bool? isUserSubmitted,
    bool? isOfflineAvailable,
    String? city,
    String? countyCode,
    String? shelterType,
    int? capacity,
    String? functionalState,
    DateTime? expiresAt,
  }) {
    return SafetyPlace(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      distanceLabel: distanceLabel ?? this.distanceLabel,
      accessibilityFeatures:
          accessibilityFeatures ?? this.accessibilityFeatures,
      hazardTags: hazardTags ?? this.hazardTags,
      lastVerified: lastVerified ?? this.lastVerified,
      notes: notes ?? this.notes,
      isUserSubmitted: isUserSubmitted ?? this.isUserSubmitted,
      isOfflineAvailable: isOfflineAvailable ?? this.isOfflineAvailable,
      city: city ?? this.city,
      countyCode: countyCode ?? this.countyCode,
      shelterType: shelterType ?? this.shelterType,
      capacity: capacity ?? this.capacity,
      functionalState: functionalState ?? this.functionalState,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}
