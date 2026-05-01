import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../config/api_keys.dart';

/// Cloud AI tier — Gemini Flash via the Generative AI API.
/// Fast (<2s), smart, requires internet. Auto-selected when online.
class GeminiAssistantService {
  GenerativeModel? _model;
  ChatSession? _chat;
  String? _systemInstruction;

  bool get isReady => _chat != null;
  bool get isConfigured => ApiKeys.geminiApiKey.isNotEmpty;

  // ── Initialisation ─────────────────────────────────────────────────────────

  Future<void> init({String? systemInstruction}) async {
    if (!isConfigured) {
      debugPrint('GeminiAssistantService: no API key configured');
      return;
    }
    _systemInstruction = systemInstruction;
    try {
      _model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: ApiKeys.geminiApiKey,
        systemInstruction: systemInstruction != null
            ? Content.system(systemInstruction)
            : null,
        generationConfig: GenerationConfig(
          temperature: 0.7, // echilibru între creativitate și coerență
          topK: 40,
          topP: 0.95,
          maxOutputTokens: 2048,
        ),
        safetySettings: [
          SafetySetting(HarmCategory.harassment, HarmBlockThreshold.none),
          SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.none),
          SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.none),
          SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.none),
        ],
      );
      _chat = _model!.startChat();
      debugPrint('GeminiAssistantService: ready');
    } catch (e) {
      debugPrint('GeminiAssistantService: init error — $e');
      rethrow;
    }
  }

  // ── Messaging ──────────────────────────────────────────────────────────────

  /// Streams text tokens as they arrive from the Gemini API.
  /// Pass [imageBytes] to include an image in the message (vision).
  Stream<String> sendTextStream(String text, {Uint8List? imageBytes}) async* {
    if (!isReady) {
      yield 'AI is not ready. Please check your connection.';
      return;
    }
    try {
      final Content content;
      if (imageBytes != null) {
        content = Content.multi([
          DataPart('image/jpeg', imageBytes),
          TextPart(text),
        ]);
      } else {
        content = Content.text(text);
      }
      final response = _chat!.sendMessageStream(content);
      await for (final chunk in response) {
        final token = chunk.text;
        if (token != null && token.isNotEmpty) yield token;
      }
    } catch (e) {
      debugPrint('GeminiAssistantService: send error — $e');
      if (e.toString().contains('API_KEY') ||
          e.toString().contains('403') ||
          e.toString().contains('401')) {
        yield '[Error: invalid Gemini API key]';
      } else {
        yield '[Error: $e]';
      }
    }
  }

  // ── Reset ──────────────────────────────────────────────────────────────────

  Future<void> reset({String? systemInstruction}) async {
    final instruction = systemInstruction ?? _systemInstruction;
    await dispose();
    await init(systemInstruction: instruction);
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    _chat = null;
    _model = null;
    debugPrint('GeminiAssistantService: disposed');
  }
}
