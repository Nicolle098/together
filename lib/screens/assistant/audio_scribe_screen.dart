import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../config/api_keys.dart';
import '../../services/app_settings_service.dart';
import '../../services/gemini_assistant_service.dart';
import '../../services/huggingface_assistant_service.dart';
import '../../theme/app_theme.dart';

// ── Accent colours ────────────────────────────────────────────────────────────
const _kTeal = Color(0xFF0D9488);
const _kTealLight = Color(0xFFCCFBF1);
const _kTealDark = Color(0xFF134E4A);
const _kRed = Color(0xFFDC2626);

enum _ScribeState { idle, recording, enhancing, done }
/// 1. Press the mic to start recording (STT)
/// 2. Stop
/// 3. Choose: Enhance, Translate, or Summarise via gemeni (gemma in future)
class AudioScribeScreen extends StatefulWidget {
  const AudioScribeScreen({super.key});

  @override
  State<AudioScribeScreen> createState() => _AudioScribeScreenState();
}

class _AudioScribeScreenState extends State<AudioScribeScreen>
    with SingleTickerProviderStateMixin {
  final _stt = stt.SpeechToText();
  final _tts = FlutterTts();
  final _gemini = GeminiAssistantService();
  final _hf = HuggingFaceAssistantService();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isOnline = false;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  _ScribeState _state = _ScribeState.idle;
  String _transcript = '';
  String _aiResult = '';
  bool _sttReady = false;
  String _enhanceMode = 'Enhance'; 
  static const _modes = ['Enhance', 'Translate', 'Summarise'];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _initStt();
    _initConnectivity();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _gemini.dispose();
    _hf.dispose();
    _pulseCtrl.dispose();
    _stt.stop();
    _tts.stop();
    super.dispose();
  }


  Future<void> _initConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    await _onConnectivityChanged(results);
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen(_onConnectivityChanged);
  }

  Future<void> _onConnectivityChanged(List<ConnectivityResult> results) async {
    final online = results.any((r) =>
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.ethernet);
    if (online == _isOnline) return;
    if (mounted) setState(() => _isOnline = online);

    if (online) {
      const instruction =
          'You are a precise transcription and language assistant. '
          'Follow instructions exactly. Output only the result, no explanations.';
      await _hf.init(systemInstruction: instruction);
      if (ApiKeys.geminiApiKey.isNotEmpty && !_gemini.isReady) {
        try {
          await _gemini.init(systemInstruction: instruction);
        } catch (_) {}
      }
    }
  }

  Future<void> _initStt() async {
    final ready = await _stt.initialize(
      onError: (_) {
        if (mounted) {
          setState(() => _state = _ScribeState.idle);
          _pulseCtrl.stop();
        }
      },
      onStatus: (status) {
        if ((status == 'done' || status == 'notListening') && mounted) {
          _stopRecording();
        }
      },
    );
    if (mounted) setState(() => _sttReady = ready);
  }


  Future<void> _startRecording() async {
    if (!_sttReady) return;
    setState(() {
      _state = _ScribeState.recording;
      _transcript = '';
      _aiResult = '';
    });
    _pulseCtrl.repeat(reverse: true);

    await _stt.listen(
      onResult: (r) {
        if (mounted) setState(() => _transcript = r.recognizedWords);
      },
      listenOptions: stt.SpeechListenOptions(
        cancelOnError: false,
        partialResults: true,
      ),
    );
  }

  Future<void> _stopRecording() async {
    await _stt.stop();
    _pulseCtrl.stop();
    _pulseCtrl.reset();
    if (mounted) setState(() => _state = _ScribeState.idle);
  }

  void _toggleRecording() {
    if (_state == _ScribeState.recording) {
      _stopRecording();
    } else {
      _startRecording();
    }
  }


  Future<void> _enhance() async {
    if (_transcript.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No transcript yet — record something first.')),
      );
      return;
    }
    if (!_isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI enhancement requires an internet connection.')),
      );
      return;
    }

    final prompt = switch (_enhanceMode) {
      'Translate' =>
        'Translate the following text to English (if not already) and fix any spelling or writing'
        'errors. Output only the translated text:\n\n$_transcript',
      'Summarise' =>
        'Summarise the key points from this transcription in 2-3 bullet points. '
        'Output only the summary:\n\n$_transcript',
      _ =>
        'Clean up this voice transcription — fix grammar, punctuation, and '
        'filler words while preserving the meaning. '
        'Output only the cleaned text:\n\n$_transcript',
    };

    setState(() {
      _state = _ScribeState.enhancing;
      _aiResult = '';
    });

    final buf = StringBuffer();
    if (_gemini.isReady) {
      await for (final token in _gemini.sendTextStream(prompt)) {
        buf.write(token);
        if (mounted) setState(() => _aiResult = buf.toString());
      }
    } else if (_hf.isConfigured) {
      await for (final token in _hf.sendTextStream(prompt)) {
        buf.write(token);
        if (mounted) setState(() => _aiResult = buf.toString());
      }
    } else {
      setState(() => _aiResult = 'AI service unavailable — check your API keys.');
    }

    if (mounted) setState(() => _state = _ScribeState.done);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _speak(String text) async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.48);
    await _tts.speak(text);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppSettings.instance.lowBattery;
    final bg = isDark ? Colors.black : const Color(0xFFF4F7FA);
    final barBg = isDark ? TogetherTheme.amoledSurface : Colors.white;
    final titleColor =
        isDark ? TogetherTheme.amoledTextPrimary : TogetherTheme.deepOcean;
    final bodyColor =
        isDark ? TogetherTheme.amoledTextSecondary : TogetherTheme.ink;

    final isRecording = _state == _ScribeState.recording;
    final isEnhancing = _state == _ScribeState.enhancing;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: barBg,
        foregroundColor: titleColor,
        elevation: 0,
        title: Text(
          'Audio Scribe',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: titleColor,
            fontFamily: 'RobotoSlab',
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: isDark ? _kTealDark : _kTealLight,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _isOnline ? 'AI Ready' : 'Offline',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _kTeal,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // ── Record button ──────────────────────────────────────────────
              const SizedBox(height: 16),
              _PulsingMic(
                isRecording: isRecording,
                animation: _pulseAnim,
                enabled: _sttReady,
                isDark: isDark,
                onTap: _toggleRecording,
              ),
              const SizedBox(height: 12),
              Text(
                isRecording
                    ? 'Recording… tap to stop'
                    : (_sttReady
                        ? 'Tap to start recording'
                        : 'Speech recognition unavailable'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isRecording ? _kRed : bodyColor,
                ),
              ),
              const SizedBox(height: 28),

              // ── Live transcript ────────────────────────────────────────────
              _TranscriptCard(
                transcript: _transcript,
                isRecording: isRecording,
                isDark: isDark,
                onCopy: _transcript.isNotEmpty
                    ? () => _copyToClipboard(_transcript)
                    : null,
                onSpeak: _transcript.isNotEmpty
                    ? () => _speak(_transcript)
                    : null,
              ),

              const SizedBox(height: 20),

              // ── Mode selector + Enhance button ─────────────────────────────
              _EnhanceBar(
                modes: _modes,
                selected: _enhanceMode,
                isDark: isDark,
                loading: isEnhancing,
                aiReady: _isOnline,
                onModeChanged: (m) => setState(() => _enhanceMode = m),
                onEnhance: _enhance,
              ),

              const SizedBox(height: 20),

              // ── AI result ──────────────────────────────────────────────────
              if (_aiResult.isNotEmpty || isEnhancing)
                _AiResultCard(
                  result: _aiResult,
                  mode: _enhanceMode,
                  isStreaming: isEnhancing,
                  isDark: isDark,
                  onCopy: _aiResult.isNotEmpty
                      ? () => _copyToClipboard(_aiResult)
                      : null,
                  onSpeak: _aiResult.isNotEmpty
                      ? () => _speak(_aiResult)
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PulsingMic extends StatelessWidget {
  const _PulsingMic({
    required this.isRecording,
    required this.animation,
    required this.enabled,
    required this.isDark,
    required this.onTap,
  });

  final bool isRecording, enabled, isDark;
  final Animation<double> animation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final scale = isRecording ? animation.value : 1.0;
          return Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow ring
              if (isRecording)
                Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kRed.withValues(alpha: 0.15),
                    ),
                  ),
                ),
              // Main button
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isRecording
                      ? _kRed
                      : (isDark ? _kTealDark : _kTealLight),
                  boxShadow: [
                    BoxShadow(
                      color: (isRecording ? _kRed : _kTeal)
                          .withValues(alpha: 0.3),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                  size: 40,
                  color: isRecording ? Colors.white : _kTeal,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TranscriptCard extends StatelessWidget {
  const _TranscriptCard({
    required this.transcript,
    required this.isRecording,
    required this.isDark,
    required this.onCopy,
    required this.onSpeak,
  });

  final String transcript;
  final bool isRecording, isDark;
  final VoidCallback? onCopy;
  final VoidCallback? onSpeak;

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? TogetherTheme.amoledSurface : Colors.white;
    final border = isDark ? TogetherTheme.amoledBorder : const Color(0xFFDCE4EA);
    final textColor =
        isDark ? TogetherTheme.amoledTextPrimary : TogetherTheme.deepOcean;
    final hintColor =
        isDark ? TogetherTheme.amoledTextSecondary : TogetherTheme.ink;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isRecording
              ? _kRed.withValues(alpha: 0.4)
              : border,
          width: isRecording ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.record_voice_over_rounded,
                size: 16,
                color: isRecording ? _kRed : _kTeal,
              ),
              const SizedBox(width: 6),
              Text(
                'Live Transcript',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isRecording ? _kRed : _kTeal,
                ),
              ),
              const Spacer(),
              if (onCopy != null)
                _IconAction(
                    icon: Icons.copy_rounded, onTap: onCopy!, isDark: isDark),
              if (onSpeak != null) ...[
                const SizedBox(width: 4),
                _IconAction(
                    icon: Icons.volume_up_rounded,
                    onTap: onSpeak!,
                    isDark: isDark),
              ],
            ],
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 80),
            child: transcript.isEmpty
                ? Text(
                    isRecording
                        ? 'Listening…'
                        : 'Your transcription will appear here.',
                    style: TextStyle(
                      fontSize: 15,
                      color: hintColor.withValues(alpha: 0.5),
                      fontStyle: FontStyle.italic,
                    ),
                  )
                : Text(
                    transcript,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.6,
                      color: textColor,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _EnhanceBar extends StatelessWidget {
  const _EnhanceBar({
    required this.modes,
    required this.selected,
    required this.isDark,
    required this.loading,
    required this.aiReady,
    required this.onModeChanged,
    required this.onEnhance,
  });

  final List<String> modes;
  final String selected;
  final bool isDark, loading, aiReady;
  final ValueChanged<String> onModeChanged;
  final VoidCallback onEnhance;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Mode chips
        Row(
          children: modes.map((m) {
            final active = m == selected;
            return Expanded(
              child: GestureDetector(
                onTap: loading ? null : () => onModeChanged(m),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: active
                        ? _kTeal
                        : (isDark
                            ? TogetherTheme.amoledSurface
                            : const Color(0xFFEDF1F5)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    m,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: active
                          ? Colors.white
                          : (isDark
                              ? TogetherTheme.amoledTextSecondary
                              : TogetherTheme.ink),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        // Enhance button
        ElevatedButton.icon(
          onPressed: loading ? null : onEnhance,
          icon: loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.auto_fix_high_rounded),
          label: Text(loading ? 'Processing…' : '$selected with AI'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _kTeal,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
            textStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        if (!aiReady)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Connect to the internet to use AI enhancement',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? TogetherTheme.amoledTextSecondary
                    : TogetherTheme.ink,
              ),
            ),
          ),
      ],
    );
  }
}

class _AiResultCard extends StatelessWidget {
  const _AiResultCard({
    required this.result,
    required this.mode,
    required this.isStreaming,
    required this.isDark,
    required this.onCopy,
    required this.onSpeak,
  });

  final String result, mode;
  final bool isStreaming, isDark;
  final VoidCallback? onCopy;
  final VoidCallback? onSpeak;

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF134E4A) : _kTealLight;
    final textColor =
        isDark ? TogetherTheme.amoledTextPrimary : const Color(0xFF0F4C3F);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kTeal.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_fix_high_rounded, size: 16, color: _kTeal),
              const SizedBox(width: 6),
              Text(
                'AI · $mode',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _kTeal,
                ),
              ),
              const Spacer(),
              if (isStreaming)
                _StreamingDot()
              else ...[
                if (onCopy != null)
                  _IconAction(
                      icon: Icons.copy_rounded, onTap: onCopy!, isDark: isDark),
                if (onSpeak != null) ...[
                  const SizedBox(width: 4),
                  _IconAction(
                      icon: Icons.volume_up_rounded,
                      onTap: onSpeak!,
                      isDark: isDark),
                ],
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            result.isEmpty ? '…' : result,
            style: TextStyle(
              fontSize: 15,
              height: 1.6,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _StreamingDot extends StatefulWidget {
  @override
  State<_StreamingDot> createState() => _StreamingDotState();
}

class _StreamingDotState extends State<_StreamingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          3,
          (i) => Padding(
            padding: EdgeInsets.only(right: i < 2 ? 3 : 0),
            child: Opacity(
              opacity: (_anim.value - i * 0.2).clamp(0.2, 1.0),
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: _kTeal,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.onTap,
    required this.isDark,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: isDark
              ? TogetherTheme.amoledSurfaceElevated
              : const Color(0xFFEDF1F5),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 15, color: _kTeal),
      ),
    );
  }
}

