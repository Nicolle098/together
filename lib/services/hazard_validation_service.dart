/// Offline-capable rule-based hazard validation service.
///
/// Acts as a local "AI" that decides whether a user's description
/// sounds like a genuine hazard report. Uses keyword matching with a
/// confidence score. Designed to be replaced or augmented by an
/// on-device ML model in a future iteration (see details.txt AI vision).
class HazardValidationResult {
  const HazardValidationResult({
    required this.isValid,
    required this.feedback,
    required this.confidence,
  });

  /// Whether the report should be accepted.
  final bool isValid;

  /// Human-readable feedback to display to the user.
  final String feedback;

  /// Confidence score in [0.0, 1.0].
  final double confidence;
}

class HazardValidationService {
  const HazardValidationService();

  static const _minDescriptionLength = 10;
  static const _maxDescriptionLength = 300;

  // Words that strongly suggest a genuine hazard observation.
  static const _hazardKeywords = [
    // English — general danger
    'danger', 'dangerous', 'hazard', 'unsafe', 'risk', 'warning', 'caution',
    'emergency', 'accident', 'incident', 'crash', 'collision',
    'injured', 'injury', 'wounded', 'trapped', 'stuck',
    // English — water / flood
    'flood', 'flooding', 'flooded', 'inundated', 'water', 'submerged',
    'overflow', 'puddle',
    // English — fire / smoke
    'fire', 'smoke', 'burning', 'flames', 'blaze', 'on fire',
    // English — structural
    'collapse', 'collapsed', 'fallen', 'broken', 'damaged', 'unstable',
    'debris', 'rubble', 'crumbling', 'cracked', 'sinkhole',
    // English — road / path
    'road', 'street', 'path', 'sidewalk', 'pavement', 'bridge',
    'blocked', 'obstruction', 'pothole', 'hole',
    // English — utilities
    'gas leak', 'gas', 'electricity', 'electric', 'power line', 'cable',
    'sewage', 'pipe', 'burst', 'leaking', 'spill', 'chemical',
    // English — weather / terrain
    'ice', 'icy', 'slippery', 'snow', 'mud', 'landslide', 'rockfall',
    // Romanian — general danger
    'pericol', 'periculos', 'periculoasa', 'risc', 'avertisment',
    'urgenta', 'urgență', 'accident', 'incident',
    // Romanian — water / flood
    'inundatie', 'inundație', 'inundatii', 'inundații', 'inundat',
    'apa', 'apă', 'aluviuni', 'revarsare',
    // Romanian — fire / smoke
    'incendiu', 'foc', 'fum', 'arde', 'flacare',
    // Romanian — structural
    'prabusit', 'prăbușit', 'daramat', 'dărâmat', 'spart', 'deteriorat',
    'avariat', 'avarie', 'fisura', 'fisură',
    // Romanian — road / path
    'drum', 'strada', 'stradă', 'trotuar', 'blocaj', 'blocat',
    'groapa', 'groapă', 'alunecare',
    // Romanian — utilities
    'gaz', 'electricitate', 'curent', 'cablu', 'conducta', 'conductă',
  ];

  // Obvious test / junk submissions.
  static const _spamPatterns = [
    'test',
    'testing',
    'asdf',
    'qwerty',
    'aaa',
    'bbb',
    'hello',
    'hi',
    'hey',
    'foo',
    'bar',
    'lorem',
    'ipsum',
    'zzz',
    'xxx',
    '123',
    '1234',
    '12345',
    'ceva',
    'nimic',
    'test123',
    'smomething',
    'idk',
  ];

  /// Validates a hazard description.
  ///
  /// Introduces a short artificial delay to communicate that a review
  /// step is happening (matches the UI's "AI reviewing..." label).
  Future<HazardValidationResult> validate(String description) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));

    final trimmed = description.trim();

    if (trimmed.length < _minDescriptionLength) {
      return const HazardValidationResult(
        isValid: false,
        feedback:
            'Description is too short. Please describe the hazard in more detail.',
        confidence: 0.0,
      );
    }

    if (trimmed.length > _maxDescriptionLength) {
      return const HazardValidationResult(
        isValid: false,
        feedback: 'Description is too long. Please keep it under 300 characters.',
        confidence: 0.0,
      );
    }

    final lower = trimmed.toLowerCase();

    // Reject obvious spam / test submissions.
    for (final spam in _spamPatterns) {
      final normalized = lower.replaceAll(RegExp(r'\s+'), '');
      if (normalized == spam || RegExp('^($spam)+\$').hasMatch(normalized)) {
        return const HazardValidationResult(
          isValid: false,
          feedback:
              'This does not appear to be a valid hazard report. Please describe a real safety concern you observed.',
          confidence: 0.0,
        );
      }
    }

    // Count how many hazard keywords appear in the description.
    var matchCount = 0;
    for (final keyword in _hazardKeywords) {
      if (lower.contains(keyword)) {
        matchCount++;
      }
    }

    if (matchCount == 0) {
      return const HazardValidationResult(
        isValid: false,
        feedback:
            'Your description does not clearly identify a hazard. Please mention the type of danger or unsafe condition you observed.',
        confidence: 0.1,
      );
    }

    // Confidence scales with keyword density, capped at 1.0.
    final confidence = (0.4 + matchCount * 0.2).clamp(0.0, 1.0);

    final feedback = confidence >= 0.8
        ? 'Report verified with high confidence. Thank you for helping keep the community safe.'
        : 'Hazard report accepted. Thank you for reporting.';

    return HazardValidationResult(
      isValid: true,
      feedback: feedback,
      confidence: confidence,
    );
  }
}
