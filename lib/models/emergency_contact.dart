class EmergencyContact { 
  const EmergencyContact({ 
    this.id = '', 
    required this.name, 
    required this.role, 
    required this.phoneNumber, 
    required this.priorityLabel, 
    this.isFromPhone = false,
  });


  final String id; 
  final String name; 
  final String role; 
  final String phoneNumber;
  final String priorityLabel; 
  final bool isFromPhone; 
}
