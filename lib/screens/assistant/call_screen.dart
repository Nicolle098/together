import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../config/api_keys.dart';
import '../../services/gemini_assistant_service.dart';
import '../../services/huggingface_assistant_service.dart';
import 'gemma_assistant_screen.dart';

const _kBg = Color(0xFF08080E);
const _kSurface = Color(0xFF14141F);
const _kGreen = Color(0xFF059669);
const _kRed = Color(0xFFDC2626);
const _kCaption = Color(0xFFE2E8F0);
const _kSubtle = Color(0xFF64748B);

// ── Call screen ───────────────────────────────────────────────────────────────
/// - pulsing rings while AI speaks, mic icon while listening.
/// - PiP cameraif surroundings mode is on
/// - Captions bar shows live STT input and full AI responses.
/// - captures a frame alongside each voice message and describes what it sees 
class CallScreen extends StatefulWidget {
  const CallScreen({super.key});
  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with TickerProviderStateMixin {
  final _gemini = GeminiAssistantService();
  final _hf = HuggingFaceAssistantService();
  final _tts = FlutterTts();
  final _stt = stt.SpeechToText();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isOnline = false;

  // Camera
  CameraController? _camera;
  bool _cameraReady = false;

  // State flags
  bool _modelReady = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _cameraOn = false;
  bool _micMuted = false;
  bool _isSendingVoice = false;
  final List<String> _ttsQueue = [];

  String _caption = 'Tap the mic or just speak';
  String _lastRecognized = '';

  // animatiions
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseScale;
  late Animation<double> _pulseAlpha;
  late AnimationController _waveCtrl;

  static const _systemPrompt =
      'You are Together AI, a voice safety assistant. '
      'Give detailed, complete answers. '
      'For immediate danger say: call 112 immediately, then explain what to do. '
      'For first aid, give full step-by-step instructions. '
      'For general questions, answer thoroughly and accurately. '
      'If shown an image, describe everything relevant you see.';

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initTts();
    _initConnectivity();
    setState(() { _modelReady = true; });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _pulseCtrl.dispose();
    _waveCtrl.dispose();
    _tts.stop();
    if (_isListening) _stt.stop();
    _camera?.dispose();
    _gemini.dispose();
    _hf.dispose();
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
    setState(() => _isOnline = online);
    if (online) {
      await _hf.init(systemInstruction: _systemPrompt);

      if (ApiKeys.geminiApiKey.isNotEmpty && !_gemini.isReady) {
        try {
          await _gemini.init(systemInstruction: _systemPrompt);
        } catch (_) {}
      }

      // Unlock UI immediately — at least one online tier is available.
      if (mounted && !_modelReady) {
        setState(() {
          _modelReady = true;
          _caption = 'Ready — tap the mic or just speak';
        });
        await _tts.speak('Together AI ready. How can I help you?');
      }
    }
  }

  // ── Animations ─────────────────────────────────────────────────────────────

  void _setupAnimations() {
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _pulseScale = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _pulseAlpha = Tween<double>(begin: 0.45, end: 0.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut),
    );

    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  // ── TTS ────────────────────────────────────────────────────────────────────

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1.0);

    _tts.setStartHandler(() {
      if (!mounted) return;
      setState(() => _isSpeaking = true);
      _pulseCtrl.repeat(reverse: true);
    });

    _tts.setCompletionHandler(() {
      if (!mounted) return;
      if (_ttsQueue.isNotEmpty) {
        // More sentences queued — speak next immediately
        _playNextQueued();
      } else {
        _pulseCtrl..stop()..reset();
        setState(() => _isSpeaking = false);
        if (!_micMuted) _startListening();
      }
    });

    _tts.setCancelHandler(() {
      if (!mounted) return;
      _ttsQueue.clear();
      _pulseCtrl..stop()..reset();
      setState(() => _isSpeaking = false);
    });
  }

  // ── Camera ─────────────────────────────────────────────────────────────────

  Future<void> _toggleCamera() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera not available on web. Use the mobile app.'),
        ),
      );
      return;
    }

    if (_cameraOn) {
      await _camera?.dispose();
      if (mounted) {
        setState(() {
          _camera = null;
          _cameraReady = false;
          _cameraOn = false;
        });
      }
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No camera found on this device.')),
          );
        }
        return;
      }
      final controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _cameraReady = true;
        _cameraOn = true;
        _caption = 'Surroundings mode ON — I can see through the camera';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
      }
    }
  }

  Future<Uint8List?> _captureFrame() async {
    if (_camera == null || !_cameraReady) return null;
    try {
      final file = await _camera!.takePicture();
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  // ── STT ────────────────────────────────────────────────────────────────────

  Future<void> _startListening() async {
    if (_isListening || _micMuted || !_modelReady) return;

    final available = await _stt.initialize(
      onError: (_) {
        if (mounted) setState(() => _isListening = false);
      },
      onStatus: (status) {
        if ((status == 'done' || status == 'notListening') && mounted) {
          setState(() => _isListening = false);
          // Fallback submit in case finalResult never fired (engine-dependent).
          final text = _lastRecognized.trim();
          _lastRecognized = '';
          if (text.isNotEmpty && !_isSpeaking && _modelReady) _sendVoice(text);
        }
      },
    );

    if (!available || !mounted) return;
    await _tts.stop();

    setState(() {
      _isListening = true;
      _caption = 'Listening…';
    });

    await _stt.listen(
      onResult: (result) {
        if (!mounted) return;
        _lastRecognized = result.recognizedWords;
        setState(() => _caption = result.recognizedWords);
        if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
          _lastRecognized = '';
          _sendVoice(result.recognizedWords.trim());
        }
      },
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 3),
      listenOptions: stt.SpeechListenOptions(
        cancelOnError: false,
        partialResults: true,
        autoPunctuation: true,
        enableHapticFeedback: true,
      ),
    );
  }

  Future<void> _toggleMic() async {
    if (_isSpeaking) await _tts.stop();

    if (_micMuted) {
      setState(() => _micMuted = false);
      _startListening();
    } else {
      await _stt.stop();
      setState(() {
        _micMuted = true;
        _isListening = false;
        _caption = 'Microphone muted';
      });
    }
  }

  // ── TTS queue helpers ──────────────────────────────────────────────────────

  void _playNextQueued() {
    if (_ttsQueue.isEmpty || !mounted) return;
    _tts.speak(_ttsQueue.removeAt(0));
  }

  void _enqueueSpeech(String text) {
    final s = text.trim();
    if (s.isEmpty) return;
    _ttsQueue.add(s);
    if (!_isSpeaking) _playNextQueued();
  }

  // ── Send message ───────────────────────────────────────────────────────────

  static final _sentenceEnd = RegExp(r'[.!?…]\s*$');

  Future<void> _sendVoice(String text) async {
    if (!_modelReady || _isSendingVoice) return;
    _isSendingVoice = true;
    await _stt.stop();
    await _tts.stop();
    _ttsQueue.clear();

    setState(() {
      _isListening = false;
      _caption = text;
    });

    Uint8List? imageBytes;
    if (_cameraOn) imageBytes = await _captureFrame();

    setState(() => _caption = 'Thinking…');

    final fullBuf = StringBuffer();
    final sentenceBuf = StringBuffer();

    void handleToken(String token) {
      fullBuf.write(token);
      sentenceBuf.write(token);
      if (mounted) setState(() => _caption = fullBuf.toString());
      final chunk = sentenceBuf.toString();
      if (_sentenceEnd.hasMatch(chunk) && chunk.trim().length > 8) {
        _enqueueSpeech(chunk);
        sentenceBuf.clear();
      }
    }

    if (_isOnline && _gemini.isReady) {
      // Tier 1: Gemini Flash
      await for (final token in _gemini.sendTextStream(text, imageBytes: imageBytes)) {
        handleToken(token);
      }
    } else if (_isOnline && _hf.isConfigured) {
      // Tier 2: HuggingFace fine-tuned model
      await for (final token in _hf.sendTextStream(text)) {
        handleToken(token);
      }
    } else {
      handleToken('No internet connection — please reconnect to use the AI assistant.');
    }

    // Speak any trailing text that didn't end with punctuation
    _enqueueSpeech(sentenceBuf.toString());
    _isSendingVoice = false;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _TopBar(
                  cameraOn: _cameraOn,
                  tierLabel: _isOnline
                      ? (_gemini.isReady ? 'Gemini' : 'Fine-tuned')
                      : 'Offline',
                  onSwitchToChat: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                        builder: (_) => const GemmaAssistantScreen()),
                  ),
                ),
                // Avatar
                Expanded(
                  child: Center(
                    child: _AiAvatar(
                      pulseCtrl: _pulseCtrl,
                      pulseScale: _pulseScale,
                      pulseAlpha: _pulseAlpha,
                      waveCtrl: _waveCtrl,
                      isSpeaking: _isSpeaking,
                      isListening: _isListening,
                      isLoading: !_modelReady,
                    ),
                  ),
                ),
                // Caption
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: screenWidth > 400 ? 32 : 20,
                    vertical: 8,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      _caption,
                      key: ValueKey(_caption),
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _kCaption,
                        fontSize: 15,
                        height: 1.55,
                      ),
                    ),
                  ),
                ),
                // Controls
                _ControlStrip(
                  micMuted: _micMuted,
                  isListening: _isListening,
                  cameraOn: _cameraOn,
                  modelReady: _modelReady,
                  onToggleMic: _toggleMic,
                  onToggleCamera: _toggleCamera,
                  onEndCall: () => Navigator.of(context).pop(),
                ),
              ],
            ),

            // PiP camera preview
            if (_cameraOn && _cameraReady && _camera != null)
              Positioned(
                top: 56,
                right: 12,
                child: _PipCamera(controller: _camera!),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.cameraOn, required this.tierLabel, required this.onSwitchToChat});
  final bool cameraOn;
  final String tierLabel;
  final VoidCallback onSwitchToChat;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
      child: Row(
        children: [
          const Icon(Icons.memory_rounded, color: _kGreen, size: 18),
          const SizedBox(width: 8),
          const Text(
            'Together AI',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 16,
              fontFamily: 'RobotoSlab',
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _kGreen.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              tierLabel,
              style: const TextStyle(
                fontSize: 10,
                color: _kGreen,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (cameraOn) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Surroundings',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.tealAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const Spacer(),
          Tooltip(
            message: 'Switch to chat',
            child: IconButton(
              icon: const Icon(
                Icons.chat_bubble_outline_rounded,
                color: Colors.white54,
                size: 20,
              ),
              onPressed: onSwitchToChat,
            ),
          ),
        ],
      ),
    );
  }
}

// ── AI avatar ─────────────────────────────────────────────────────────────────

class _AiAvatar extends StatelessWidget {
  const _AiAvatar({
    required this.pulseCtrl,
    required this.pulseScale,
    required this.pulseAlpha,
    required this.waveCtrl,
    required this.isSpeaking,
    required this.isListening,
    required this.isLoading,
  });

  final AnimationController pulseCtrl;
  final Animation<double> pulseScale;
  final Animation<double> pulseAlpha;
  final AnimationController waveCtrl;
  final bool isSpeaking;
  final bool isListening;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([pulseCtrl, waveCtrl]),
      builder: (context, _) {
        return SizedBox(
          width: 200,
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer pulse ring
              if (isSpeaking)
                Transform.scale(
                  scale: pulseScale.value,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kGreen.withValues(alpha: pulseAlpha.value * 0.5),
                    ),
                  ),
                ),
              // Inner pulse ring (slower)
              if (isSpeaking)
                Transform.scale(
                  scale: 1.0 + (pulseScale.value - 1.0) * 0.55,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kGreen.withValues(alpha: pulseAlpha.value * 0.25),
                    ),
                  ),
                ),
              // Listening ring
              if (isListening)
                Container(
                  width: 144,
                  height: 144,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _kRed.withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                ),
              // Core circle
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kSurface,
                  border: Border.all(
                    color: isSpeaking
                        ? _kGreen
                        : (isListening ? _kRed : Colors.white24),
                    width: 2,
                  ),
                ),
                child: isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(36),
                        child: CircularProgressIndicator(
                          color: _kGreen,
                          strokeWidth: 2.5,
                        ),
                      )
                    : (isSpeaking
                        ? _Waveform(ctrl: waveCtrl)
                        : Icon(
                            isListening
                                ? Icons.mic_rounded
                                : Icons.memory_rounded,
                            size: 48,
                            color: isListening ? _kRed : _kGreen,
                          )),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Waveform extends StatelessWidget {
  const _Waveform({required this.ctrl});
  final AnimationController ctrl;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(5, (i) {
        final phase = i / 4.0;
        final heightPct =
            0.5 + 0.5 * math.sin((ctrl.value + phase) * math.pi * 2);
        final barH = 14.0 + 28.0 * heightPct;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: 5,
          height: barH,
          decoration: BoxDecoration(
            color: _kGreen,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}


class _PipCamera extends StatelessWidget {
  const _PipCamera({required this.controller});
  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.6), width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: SizedBox(
          width: 96,
          height: 130,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

class _ControlStrip extends StatelessWidget {
  const _ControlStrip({
    required this.micMuted,
    required this.isListening,
    required this.cameraOn,
    required this.modelReady,
    required this.onToggleMic,
    required this.onToggleCamera,
    required this.onEndCall,
  });

  final bool micMuted;
  final bool isListening;
  final bool cameraOn;
  final bool modelReady;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleCamera;
  final VoidCallback onEndCall;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Camera
          _Btn(
            icon: cameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
            label: cameraOn ? 'Camera on' : 'Camera',
            active: cameraOn,
            activeColor: Colors.teal,
            onTap: onToggleCamera,
          ),
          // Mic — large centre button
          _Btn(
            icon: micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            label: micMuted ? 'Unmute' : (isListening ? 'Listening' : 'Speak'),
            active: isListening && !micMuted,
            activeColor: _kRed,
            large: true,
            onTap: modelReady ? onToggleMic : null,
          ),
          // End call
          _Btn(
            icon: Icons.call_end_rounded,
            label: 'End',
            active: true,
            activeColor: _kRed,
            onTap: onEndCall,
          ),
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.activeColor = _kGreen,
    this.large = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final Color activeColor;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final size = large ? 72.0 : 56.0;
    final iconSz = large ? 28.0 : 22.0;

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? activeColor : const Color(0xFF1E1E2E),
                border: Border.all(
                  color: active ? activeColor : Colors.white12,
                  width: 1.5,
                ),
              ),
              child: Icon(icon, color: Colors.white, size: iconSz),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(color: _kSubtle, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
