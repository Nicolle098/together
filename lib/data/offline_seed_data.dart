import '../models/emergency_contact.dart';
import '../models/medical_profile.dart';
import '../models/safety_place.dart';

class OfflineSeedData {
  const OfflineSeedData._();

  static const medicalProfile = MedicalProfile(
    bloodType: 'O+',
    allergies: ['Penicillin'],
    medications: ['Rescue inhaler'],
    mobilityNeeds: ['Step-free entrance preferred'],
    communicationNeeds: ['Speak clearly', 'Confirm directions aloud'],
    emergencyNotes: 'Carries a small medical pouch in the front backpack.',
  );

  static const emergencyContacts = [
    EmergencyContact(
      name: 'Alexandra Popescu',
      role: 'Primary caregiver',
      phoneNumber: '+40 712 345 678',
      priorityLabel: 'Call first',
    ),
    EmergencyContact(
      name: 'Dr. Mihai Ionescu',
      role: 'Family doctor',
      phoneNumber: '+40 721 234 567',
      priorityLabel: 'Medical support',
    ),
    EmergencyContact(
      name: 'Unified Emergency',
      role: 'National emergency number',
      phoneNumber: '112',
      priorityLabel: 'Urgent danger',
    ),
  ];

  static const nearbyPlaces = [
    SafetyPlace(
      id: 'shelter-1',
      name: 'Piata Victoriei Shelter',
      category: SafetyPlaceCategory.shelter,
      latitude: 44.4527,
      longitude: 26.0861,
      address: 'Bulevardul Aviatorilor 3, Bucharest',
      distanceLabel: '450 m',
      accessibilityFeatures: ['Ramp access', 'Wide doorway'],
      hazardTags: [],
      lastVerified: 'Verified Jan 18, 2026',
      notes: 'Civil protection shelter with indoor waiting space.',
    ),
    SafetyPlace(
      id: 'hospital-1',
      name: 'Elias Emergency Hospital',
      category: SafetyPlaceCategory.hospital,
      latitude: 44.4650,
      longitude: 26.0726,
      address: 'Bulevardul Marasti 17, Bucharest',
      distanceLabel: '1.2 km',
      accessibilityFeatures: ['Wheelchair access', 'Reception support'],
      hazardTags: [],
      lastVerified: 'Verified Feb 2, 2026',
      notes: '24/7 emergency intake.',
    ),
    SafetyPlace(
      id: 'police-1',
      name: 'Section 1 Police Station',
      category: SafetyPlaceCategory.police,
      latitude: 44.4557,
      longitude: 26.0849,
      address: 'Calea Victoriei 19, Bucharest',
      distanceLabel: '950 m',
      accessibilityFeatures: ['Street-level access', 'Help desk'],
      hazardTags: [],
      lastVerified: 'Verified Feb 9, 2026',
      notes: 'Nearest police support point for reports and urgent guidance.',
    ),
    SafetyPlace(
      id: 'fire-1',
      name: 'ISU Bucharest Unit 1',
      category: SafetyPlaceCategory.fireStation,
      latitude: 44.4471,
      longitude: 26.0816,
      address: 'Strada Buzesti 9, Bucharest',
      distanceLabel: '1.8 km',
      accessibilityFeatures: ['Staff support'],
      hazardTags: [],
      lastVerified: 'Verified Jan 4, 2026',
      notes: 'Fire response and rescue support point.',
    ),
    SafetyPlace(
      id: 'toilet-1',
      name: 'Accessible Public Toilet Gara de Nord',
      category: SafetyPlaceCategory.accessibleToilet,
      latitude: 44.4468,
      longitude: 26.0748,
      address: 'Piata Garii de Nord, Bucharest',
      distanceLabel: '1.1 km',
      accessibilityFeatures: ['Step-free entry', 'Support rails'],
      hazardTags: [],
      lastVerified: 'Verified Mar 1, 2026',
      notes: 'Accessible toilet with wide turning space and rail support.',
    ),
    SafetyPlace(
      id: 'hazard-1',
      name: 'Broken Sidewalk Segment',
      category: SafetyPlaceCategory.hazard,
      latitude: 44.4489,
      longitude: 26.0894,
      address: 'Bulevardul Lascar Catargiu 12, Bucharest',
      distanceLabel: '600 m',
      accessibilityFeatures: [],
      hazardTags: ['Trip hazard', 'Wheelchair obstruction'],
      lastVerified: 'Reported Mar 28, 2026',
      notes: 'Raised pavement and missing curb section. Use alternate crossing.',
      isUserSubmitted: true,
    ),
    SafetyPlace(
      id: 'hazard-2',
      name: 'Poor Lighting Underpass',
      category: SafetyPlaceCategory.hazard,
      latitude: 44.4442,
      longitude: 26.0901,
      address: 'Underpass near Piata Romana, Bucharest',
      distanceLabel: '1.4 km',
      accessibilityFeatures: [],
      hazardTags: ['Low visibility', 'Unsafe at night'],
      lastVerified: 'Reported Apr 2, 2026',
      notes: 'Limited lighting after sunset. Prefer surface route when possible.',
      isUserSubmitted: true,
    ),
  ];

  static const communicationCards = [
    'I need medical help.',
    'I am disabled and may need extra evacuation support.',
    'Please speak slowly and clearly.',
    'I need help reaching a shelter.',
  ];
}
