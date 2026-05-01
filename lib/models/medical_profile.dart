class MedicalProfile { 
  const MedicalProfile({
    required this.bloodType, 
    required this.allergies, 
    required this.medications, 
    required this.mobilityNeeds, 
    required this.communicationNeeds, 
    required this.emergencyNotes, 
  });

  final String bloodType; 
  final List<String> allergies; 
  final List<String> medications; 
  final List<String> mobilityNeeds; 
  final List<String> communicationNeeds; 
  final String emergencyNotes; 
}
