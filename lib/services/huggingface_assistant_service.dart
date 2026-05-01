import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_keys.dart';

/// Fine-tuned cloud tier — minico72/together-ai-gemma via HuggingFace Inference API.
/// Falls back to this when Gemini is unavailable but internet exists.
class HuggingFaceAssistantService {
  static const _endpoint =
      'https://api-inference.huggingface.co/models/minico72/together-ai-gemma';

  String? _systemInstruction;
  final List<Map<String, String>> _history = [];

  bool get isConfigured => ApiKeys.huggingFaceToken.isNotEmpty;

  // ── Initialisation ─────────────────────────────────────────────────────────

  Future<void> init({String? systemInstruction}) async {
    _systemInstruction = systemInstruction;
    _history.clear();
    debugPrint('HuggingFaceAssistantService: ready');
  }

  // ── Messaging ──────────────────────────────────────────────────────────────

  /// Calls HF Inference API and streams the response word by word.
  Stream<String> sendTextStream(String text) async* {
    _history.add({'role': 'user', 'content': text});

    final prompt = _buildPrompt();

    try {
      final response = await http.post(
        Uri.parse(_endpoint),
        headers: {
          'Authorization': 'Bearer ${ApiKeys.huggingFaceToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'inputs': prompt,
          'parameters': {
            'max_new_tokens': 512,
            'temperature': 0.7,
            'top_p': 0.95,
            'top_k': 40,
            'do_sample': true,
            'return_full_text': false,
          },
        }),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        String generated = '';
        if (decoded is List && decoded.isNotEmpty) {
          generated = (decoded[0]['generated_text'] as String? ?? '').trim();
        } else if (decoded is Map) {
          generated = (decoded['generated_text'] as String? ?? '').trim();
        }

        // Strip any trailing chat template tokens
        final cutIdx = generated.indexOf('<end_of_turn>');
        if (cutIdx != -1) generated = generated.substring(0, cutIdx).trim();

        _history.add({'role': 'assistant', 'content': generated});

        // Yield word-by-word to simulate streaming
        final words = generated.split(' ');
        for (int i = 0; i < words.length; i++) {
          yield i == 0 ? words[i] : ' ${words[i]}';
          await Future.delayed(const Duration(milliseconds: 18));
        }
      } else if (response.statusCode == 503) {
        yield '[Model is loading, please try again in a few seconds]';
        _history.removeLast();
      } else {
        debugPrint('HuggingFaceAssistantService: HTTP ${response.statusCode} — ${response.body}');
        yield '[Error: could not reach AI service]';
        _history.removeLast();
      }
    } catch (e) {
      debugPrint('HuggingFaceAssistantService: error — $e');
      yield '[Error: $e]';
      _history.removeLast();
    }
  }

  // ── Reset ──────────────────────────────────────────────────────────────────

  Future<void> reset({String? systemInstruction}) async {
    _history.clear();
    await init(systemInstruction: systemInstruction ?? _systemInstruction);
  }

  Future<void> dispose() async {
    _history.clear();
    debugPrint('HuggingFaceAssistantService: disposed');
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _buildPrompt() {
    final buf = StringBuffer();
    if (_systemInstruction != null && _systemInstruction!.isNotEmpty) {
      buf.write('<start_of_turn>system\n$_systemInstruction<end_of_turn>\n');
    }
    for (final msg in _history) {
      // Gemma folosește 'model' în loc de 'assistant'
      final role = msg['role'] == 'assistant' ? 'model' : 'user';
      buf.write('<start_of_turn>$role\n${msg['content']}<end_of_turn>\n');
    }
    buf.write('<start_of_turn>model\n');
    return buf.toString();
  }
}
