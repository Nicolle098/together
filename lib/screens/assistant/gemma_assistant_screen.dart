import 'dart:async'; 
import 'dart:typed_data'; 
import 'package:connectivity_plus/connectivity_plus.dart'; 
import 'package:flutter/material.dart'; 
import 'package:flutter_tts/flutter_tts.dart'; 
import 'package:image_picker/image_picker.dart'; 
import 'package:speech_to_text/speech_to_text.dart' as stt; 
import '../../config/api_keys.dart'; 
import '../../services/app_settings_service.dart'; 
import '../../services/gemini_assistant_service.dart'; 
import '../../services/huggingface_assistant_service.dart'; 
import '../../services/wikipedia_service.dart'; 
import '../../theme/app_theme.dart'; 
import 'call_screen.dart'; 

const _kGreen = Color(0xFF059669); 
const _kGreenLight = Color(0xFFD1FAE5);
const _kGreenDark = Color(0xFF064E3B); 
const _kThinkPurple = Color(0xFF7C3AED); 
const _kThinkPurpleLight = Color(0xFFEDE9FE); 
const _kWikiBlue = Color(0xFF1D4ED8); 
const _kWikiBlueBg = Color(0xFFEFF6FF); 

const _emergencyKeywords = [
  'fire', 'earthquake', 'flood', 'emergency', 'help me',
  'injured', 'hurt', 'accident', 'danger', 'smoke', 'gas leak',
  'trapped', 'bleeding', 'unconscious', 'cant breathe',
  'incendiu', 'cutremur', 'ajutor', 'pericol', 'ranit',
  'nu pot respira', 'sunt blocat', 'scap de sub', 'sangerez',
  'ajutor', 'urgenta', 'accident', 'foc', 'incendiu', 'cutremur',
];

const _factualPrefixes = [ // trigger the Wikipedia skill when it is enabled
  'who is', 'who was', 'what is', 'what are', 'what was',
  'when did', 'when was', 'where is', 'where was',
  'how does', 'how do', 'tell me about', 'explain',
  'describe', 'history of', 'definition of',
];

// ── Message model ─────────────────────────────────────────────────────────────

class _Msg { 
  String text; 
  String thinkingText = ''; 
  bool thinkingExpanded = false; 
  WikiResult? wikiResult; 
  final bool isUser; 
  bool isStreaming; 
  Uint8List? imageBytes; 
  final DateTime time; 

  _Msg({ 
    required this.text,
    required this.isUser,
    this.isStreaming = false, 
    this.wikiResult, 
    this.imageBytes, 
  }) : time = DateTime.now(); 
}

class GemmaAssistantScreen extends StatefulWidget { // The main screen widget — StatefulWidget because the UI changes as messages arrive and state is updated
  const GemmaAssistantScreen({super.key}); // Standard Flutter constructor; super.key lets the framework identify this widget uniquely

  @override
  State<GemmaAssistantScreen> createState() => _GemmaAssistantScreenState(); // Creates the companion State object that holds all mutable data and logic
}

class _GemmaAssistantScreenState extends State<GemmaAssistantScreen> { // The State class — this is where all the actual data and methods live
  final _inputController = TextEditingController(); // Controls the text field at the bottom — lets us read and clear what the user has typed
  final _scrollController = ScrollController(); // Controls the chat list's scroll position — used to jump to the latest message
  final _gemini = GeminiAssistantService(); // Manages the connection to Google Gemini (the online, high-quality AI backend)
  final _hf = HuggingFaceAssistantService(); // Manages the connection to HuggingFace (the fallback online AI backend)
  final _tts = FlutterTts(); // The text-to-speech engine that reads AI replies out loud
  final _stt = stt.SpeechToText(); // The speech-to-text engine that converts microphone audio into text
  final _imagePicker = ImagePicker(); // The helper object used to open the device gallery and pick a photo

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub; // Keeps a reference to the connectivity event stream so we can cancel it when the screen closes
  bool _isOnline = false; // Tracks whether the device currently has an internet connection

  final List<_Msg> _messages = []; // The ordered list of all messages shown in the chat — adding to this list rebuilds the UI
  bool _isLoading = false; // True while waiting for an AI reply — used to disable the send button and show a loading state
  bool _isListening = false; // True while the microphone is actively recording — controls the mic button colour
  bool _sttAvailable = false; // True if the device supports speech recognition — if false, the mic button shows a warning instead
  bool _contextReady = false; // True once the AI model's context (system prompt) has been loaded — used to hide the loading spinner
  bool _modelReady = false; // True once the AI model itself is ready to accept messages
  bool _emergencyMode = false; // True when an emergency keyword was detected — causes the red banner to appear at the top

  bool _agentSkillsEnabled = false; // Whether the Wikipedia "agent skill" is currently toggled on by the user

  // Pending image attachment
  Uint8List? _pendingImage; // Holds the raw bytes of an image the user has chosen but not yet sent

  // Full prompt for E2B (large model — enough context window to hold it).
  static const _activePromptFull = // The detailed system prompt sent to Gemini — it defines the AI's identity, priorities, first-aid reference, and strict behaviour rules
      'You are Together AI — a free safety and accessibility assistant '
      'built into the Together app. You help people during emergencies, answer first aid '
      'questions, guide users through the app, and support people with accessibility needs. '
      'You run entirely on-device and are always available without internet.\n\n'

      'RULES — follow in exact priority order:\n\n'

      '1. EMERGENCY ESCALATION (highest priority):\n'
      'If the user describes immediate danger — fire, heavy bleeding, cardiac arrest, '
      'choking, earthquake, unconscious person, gas leak, or violence — your FIRST words '
      'must be: "Call 112 immediately." Then add ONE action step. No other text.\n\n'

      '2. FIRST AID — always answer with direct steps, never refuse:\n'
      'Cut or wound: Apply firm pressure with a clean cloth for 5-10 minutes. Keep the '
      'wound raised above heart level. If bleeding does not stop, call 112.\n'
      'Burn: Cool under cold running water for 10 minutes. Do not use ice or butter. '
      'Cover loosely with a clean cloth.\n'
      'Choking adult: Give 5 firm back blows between the shoulder blades. If that fails, '
      'give 5 abdominal thrusts. Call 112 if the person loses consciousness.\n'
      'Cardiac arrest: Call 112 first. Push hard and fast on the centre of the chest — '
      '30 compressions then 2 rescue breaths. Repeat until help arrives.\n'
      'Broken bone: Keep the limb still. Do not try to straighten it. Call 112 if the '
      'person cannot move safely.\n'
      'Panic attack: Say — You are safe. Breathe in 4, hold 4, out 6.\n'
      'Seizure: Clear the area. Do not hold them down. Call 112 if over 5 minutes.\n'
      'NEVER say "I cannot answer" for first aid.\n\n'

      '3. ANSWER LENGTH: Match length to the task. Brief for simple questions. '
      'Complete for tasks like essays, lists, or step-by-step guides — do not cut off. '
      'Never repeat the same sentence twice.\n\n'

      '4. LANGUAGE: Reply in the same language the user used.\n\n'

      '5. TRANSLATION TASKS: Output ONLY the translated/corrected text. No explanation.\n\n'

      '6. NO ECHO: Never repeat the user\'s words as your reply.\n\n'

      '7. IDENTITY: You are ASSISTANT. Never write "User:" in your reply. '
      'Never claim to be a doctor or paramedic.\n\n'

      '8. CONFIDENCE: If uncertain say "I am not fully sure, but…" then give best answer. '
      'Never invent phone numbers or addresses.\n\n'

      'APP SCREENS: Safety Map, Emergency, Help, Settings.\n'
      'ROMANIA: emergency 112, mental health 0800 801 200, anti-violence 0800 500 333.\n\n'

      'Begin your reply directly. Never start with "User:" or "Assistant:".';

  // Compact prompt for the 1B small model — intentionally short to prevent confusion.
  static const _activePromptLite = // A shorter, simpler system prompt used with the HuggingFace model which has a smaller context window
      'You are Together AI, a helpful assistant built into the Together safety app. '
      'You answer questions about first aid, safety, emergencies, and everyday topics. '
      'You are used in Romania. Romania emergency number: 112.\n\n'

      'First aid reference:\n'
      'Minor cut: press with clean cloth 5-10 min, raise above heart level.\n'
      'Burn: cool under running water 10 min, no ice or butter, cover loosely.\n'
      'Cardiac arrest: push hard and fast centre of chest, 30 compressions then 2 breaths.\n'
      'Choking: 5 back blows between shoulder blades, then 5 abdominal thrusts.\n'
      'Seizure: clear objects away, do not restrain, call 112 if over 5 minutes.\n'
      'Panic attack: breathe in 4 counts, hold 4, out 6. Say: you are safe.\n\n'

      'Rules:\n'
      '- Reply in the same language the user used.\n'
      '- Never start with "User:" or "Assistant:".\n'
      '- Give complete answers, do not stop early.\n'
      '- For greetings, respond warmly and ask how you can help.\n'
      'Begin your reply directly.';

  final String _activePrompt = _activePromptFull; // Selects the full prompt as the one actually used — the lite prompt is only passed to HuggingFace directly in _onConnectivityChanged

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() { // Called once when the screen first appears — sets up voice, connectivity, and the welcome message
    super.initState(); // Always call super.initState() first in Flutter State classes
    _initVoice(); // Start setting up the microphone and text-to-speech engine
    _initConnectivity(); // Start listening for Wi-Fi / mobile data changes
    setState(() { _modelReady = true; _contextReady = true; }); // Mark the AI as ready immediately (API-based models don't need a loading phase)
    _addAiMsg("Hello! I'm Together AI. How can I help you today?"); // Show a greeting message as the very first chat bubble
  }

  @override
  void dispose() { // Called when the screen is permanently closed — must clean up every resource to avoid memory leaks
    _connectivitySub?.cancel(); // Stop listening for connectivity changes — the ? means "only if _connectivitySub is not null"
    _inputController.dispose(); // Release the text field controller from memory
    _scrollController.dispose(); // Release the scroll controller from memory
    _tts.stop(); // Stop any ongoing speech so it doesn't keep playing after leaving the screen
    if (_isListening) _stt.stop(); // Stop the microphone if it is still recording
    _gemini.dispose(); // Tell the Gemini service to clean up its own resources (e.g. close HTTP connections)
    _hf.dispose(); // Same for the HuggingFace service
    super.dispose(); // Always call super.dispose() last — Flutter requires this
  }

  // ── Initialisation ─────────────────────────────────────────────────────────

  // ── Connectivity ───────────────────────────────────────────────────────────

  Future<void> _initConnectivity() async { // Sets up the initial network check and subscribes to future network changes
    final results = await Connectivity().checkConnectivity(); // Do an immediate one-off check of the current network status
    await _onConnectivityChanged(results); // Process those results the same way as any later change
    _connectivitySub = Connectivity() // Start listening for all future network-status events
        .onConnectivityChanged
        .listen(_onConnectivityChanged); // Every time connectivity changes, call _onConnectivityChanged with the new list of results
  }

  Future<void> _onConnectivityChanged(List<ConnectivityResult> results) async { // Runs whenever the network status changes — decides which AI backend to use
    final online = results.any((r) => // Check if any of the reported connection types is a usable internet connection
        r == ConnectivityResult.mobile || // Mobile data counts as online
        r == ConnectivityResult.wifi || // Wi-Fi counts as online
        r == ConnectivityResult.ethernet); // Ethernet also counts as online

    if (online == _isOnline) return; // Nothing changed — skip the rest to avoid unnecessary rebuilds
    setState(() => _isOnline = online); // Update the stored online/offline flag and trigger a UI rebuild

    if (online) { // We just came online — try to initialise the AI backends
      // Always init HF when online — it's instant (no network call).
      await _hf.init(systemInstruction: _activePromptLite); // Set up HuggingFace with the compact system prompt

      if (ApiKeys.geminiApiKey.isNotEmpty && !_gemini.isReady) { // Only try Gemini if an API key exists and it hasn't been set up yet
        try {
          await _gemini.init(systemInstruction: _activePrompt); // Set up Gemini with the full detailed system prompt
          if (mounted && _gemini.isReady && _messages.isNotEmpty) { // mounted = the screen is still visible; isNotEmpty = don't show this on the very first load
            _addAiMsg('Connected — switching to Gemini Flash for faster answers.'); // Inform the user that the better model is now active
          }
        } catch (e) { // Gemini setup failed (e.g. quota exceeded, bad key, no network yet)
          debugPrint('Gemini init failed: $e'); // Print the error to the console for developers — not shown to the user
          if (mounted && _messages.isNotEmpty) {
            _addAiMsg('Could not reach Gemini (${_shortError(e)}). Using fine-tuned assistant model.'); // Tell the user why Gemini failed and that the HuggingFace fallback is being used instead
          }
        }
      }
    } else if (!online && _messages.isNotEmpty && mounted) { // We just went offline — warn the user
      _addAiMsg('Offline — AI unavailable. Please reconnect to continue.'); // Inform the user that no AI is available without internet
    }
  }

  Future<void> _initVoice() async { // Sets up both speech-to-text (microphone) and text-to-speech (speaker)
    _sttAvailable = await _stt.initialize( // Try to initialise the speech recognition engine; the return value tells us if it worked
      onError: (_) { // Callback fired if the microphone encounters an error mid-session
        if (mounted) setState(() => _isListening = false); // Reset the listening flag so the mic button goes back to its normal state
      },
      onStatus: (status) { // Callback fired whenever the STT engine changes state (e.g. "listening", "done", "notListening")
        if (status == 'done' || status == 'notListening') { // The user stopped speaking or the session timed out
          if (!mounted) return; // Guard: don't update UI if the screen has already been closed
          setState(() => _isListening = false); // Turn off the recording indicator
          final text = _inputController.text.trim(); // Grab whatever was transcribed and strip leading/trailing whitespace
          if (text.isNotEmpty && !_isLoading) _send(text); // Auto-send the transcribed text if there is something to send and the AI is not already busy
        }
      },
    );
    await _tts.setLanguage('en-US'); // Tell TTS to use an English (US) voice by default
    await _tts.setSpeechRate(0.48); // Set a comfortable speaking speed — 0.48 is slightly slower than the default 0.5 so it is easier to follow
    await _tts.setVolume(1.0); // Set TTS volume to maximum (1.0 = 100%)
  }

  // ── Image picker ───────────────────────────────────────────────────────────

  Future<void> _pickImage() async { // Opens the device gallery so the user can choose a photo to attach to their next message
    try {
      final file = await _imagePicker.pickImage( // Show the system image picker and wait for the user's selection
        source: ImageSource.gallery, // Use the photo gallery rather than the camera
        maxWidth: 1024, // Resize the image to at most 1024 pixels wide before reading it — keeps memory usage reasonable
        maxHeight: 1024, // Same limit for height
        imageQuality: 85, // Compress the image to 85% JPEG quality — smaller size while keeping good visual detail
      );
      if (file == null) return; // The user cancelled the picker without selecting anything — do nothing
      final bytes = await file.readAsBytes(); // Read the chosen image file into raw bytes so it can be displayed and sent
      if (mounted) setState(() => _pendingImage = bytes); // Store the bytes and trigger a UI rebuild to show the image preview bar
    } catch (e) { // Something went wrong (e.g. permission denied or file unreadable)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar( // Show a brief error message at the bottom of the screen
          SnackBar(content: Text('Could not load image: $e')),
        );
      }
    }
  }

  void _clearPendingImage() => setState(() => _pendingImage = null); // Removes the pending image attachment and rebuilds the UI to hide the preview bar

  // ── Messaging ──────────────────────────────────────────────────────────────

  void _addAiMsg(String text, {WikiResult? wiki}) { // Convenience method that appends a finished AI message to the chat list and reads it aloud
    if (!mounted) return; // Safety check — don't try to update UI if the screen is gone
    setState(() => _messages.add( // Add a new AI message to the list and trigger a UI rebuild
          _Msg(text: text, isUser: false, wikiResult: wiki), // isUser: false marks this as an AI bubble; wiki attaches any Wikipedia card
        ));
    _scrollToBottom(); // Scroll down so the new message is visible
    _tts.stop(); // Stop any speech that might already be playing before starting the new one
    _tts.speak(text); // Read the new AI message out loud using the TTS engine
  }

  bool _isEmergency(String text) { // Returns true if the user's message contains any emergency keyword
    final lower = text.toLowerCase(); // Convert to lower-case so the check is case-insensitive
    return _emergencyKeywords.any(lower.contains); // .any() returns true as soon as one keyword is found inside the message
  }

  bool _isFactualQuery(String text) { // Returns true if the message looks like a factual question that Wikipedia could help with
    final lower = text.toLowerCase(); // Lower-case the input for case-insensitive matching
    return _factualPrefixes.any(lower.startsWith); // Check whether the message starts with any of the known factual question prefixes
  }

  Future<void> _send(String text, {Uint8List? overrideImage}) async { // Core method — takes the user's input and gets an AI response; overrideImage is used when sending a programmatic message with a specific image
    text = text.trim(); // Remove any accidental leading/trailing spaces
    if (text.isEmpty || _isLoading || !_modelReady) return; // Do nothing if there is no text, the AI is already responding, or the model isn't ready yet

    final imageToSend = overrideImage ?? _pendingImage; // Use the override image if provided, otherwise use the one the user attached manually
    _inputController.clear(); // Wipe the text field so the user sees it is empty after sending
    setState(() => _pendingImage = null); // Clear the pending image attachment (it is now being sent)

    if (_isEmergency(text)) setState(() => _emergencyMode = true); // If the message contains an emergency keyword, show the red warning banner

    // ── Wikipedia agent skill ────────────────────────────────────────────────
    WikiResult? wikiResult; // Will hold the Wikipedia result if a lookup is performed; null otherwise
    String textToSend = text; // Start with the raw user text — may be expanded with Wikipedia context below

    if (_agentSkillsEnabled && _isFactualQuery(text) && imageToSend == null) { // Only run the Wikipedia lookup when the skill is ON, the question is factual, and there is no image attached (vision + wiki together is not supported)
      // Show lookup indicator
      setState(() {
        _messages.add(_Msg(text: '🔍 Searching Wikipedia…', isUser: false)); // Add a temporary "Searching…" bubble so the user knows something is happening
        _isLoading = true; // Mark the AI as busy to prevent duplicate sends
      });
      _scrollToBottom(); // Scroll to show the temporary bubble

      wikiResult = await WikipediaService.search(text); // Fetch a Wikipedia summary for the user's query — this is an async network call

      // Remove the lookup indicator
      if (mounted) {
        setState(() => _messages.removeLast()); // Remove the temporary "Searching…" bubble now that the lookup is complete
      }

      if (wikiResult != null) { // A Wikipedia article was found
        textToSend =
            '$text\n\n[Wikipedia context: ${wikiResult.summary}]'; // Append the Wikipedia summary to the text that will be sent to the AI, so the AI can use it as additional context
      }
    }

    // Add user message
    setState(() {
      _messages.add(_Msg( // Add the user's message bubble to the chat list
        text: text, // Show the original text (not the expanded version with Wikipedia context — the AI's context is hidden from the user)
        isUser: true, // Mark it as a user bubble so it appears on the right side
        imageBytes: imageToSend, // Attach the image bytes if the user included a photo
      ));
      _isLoading = true; // Mark as loading to disable the send button while waiting for the AI
    });
    _scrollToBottom(); // Scroll down to show the user's message

    // Add streaming placeholder for AI reply
    final streamingMsg = _Msg( // Create the AI reply bubble in advance — it starts empty and is filled token by token
      text: '', // No text yet — the "…" placeholder will be shown until the first token arrives
      isUser: false, // This is an AI bubble — appears on the left
      isStreaming: true, // Mark as streaming so the pulsing dot is shown
      wikiResult: wikiResult, // Attach the Wikipedia result so the source card is shown beneath the reply (if applicable)
    );
    setState(() => _messages.add(streamingMsg)); // Add the placeholder bubble to the list and rebuild the UI

    String textBuffer = ''; // Accumulates all the text tokens as they stream in from the AI

    if (_isOnline && _gemini.isReady) { // Tier 1: Use Gemini if we are online and the service was successfully initialised
      // ── Tier 1: Gemini Flash (online, fastest) ─────────────────────────────
      await for (final token in _gemini.sendTextStream(textToSend, imageBytes: imageToSend)) { // Receive the AI's reply one small "token" (word fragment) at a time
        textBuffer += token; // Append the new token to what we have so far
        if (mounted) setState(() => streamingMsg.text = textBuffer); // Update the bubble's text in the UI so the user sees it appear word by word
        _scrollToBottom(); // Keep scrolling down as the reply grows
      }
    } else if (_isOnline && _hf.isConfigured) { // Tier 2: Fall back to HuggingFace if Gemini is unavailable but we are still online
      // ── Tier 2: HuggingFace fine-tuned model (online fallback) ─────────────
      await for (final token in _hf.sendTextStream(textToSend)) { // Stream the reply from HuggingFace the same way
        textBuffer += token; // Build up the reply text token by token
        if (mounted) setState(() => streamingMsg.text = textBuffer); // Update the bubble live
        _scrollToBottom(); // Keep the view scrolled to the latest content
      }
    } else { // No online AI backend is available — inform the user
      textBuffer = 'No internet connection — please connect to use the AI assistant.'; // Fallback error message shown inside the AI bubble
      if (mounted) setState(() => streamingMsg.text = textBuffer); // Display the error message in the bubble immediately
    }

    if (!mounted) return; // Guard: the screen may have been closed while we were waiting for the AI
    setState(() {
      streamingMsg.isStreaming = false; // Turn off the streaming indicator — the reply is now complete
      _isLoading = false; // Re-enable the send button now that the AI has finished responding
    });
    if (textBuffer.isNotEmpty) { // Only speak if there is something to say
      _tts.stop(); // Stop any currently playing speech
      _tts.speak(textBuffer); // Read the complete AI reply out loud
    }
  }

  // ── Voice ──────────────────────────────────────────────────────────────────

  Future<void> _toggleListen() async { // Starts or stops microphone recording when the user taps the mic button
    if (!_sttAvailable) { // The device does not support speech recognition (e.g. no engine installed)
      ScaffoldMessenger.of(context).showSnackBar( // Show a brief informational message at the bottom
        const SnackBar(
          content: Text('Speech recognition unavailable on this device.'),
        ),
      );
      return; // Stop here — there is nothing else to do
    }
    if (_isListening) { // The mic is currently on — the user wants to stop recording
      await _stt.stop(); // Tell the STT engine to stop listening
      setState(() => _isListening = false); // Update the UI so the mic button returns to its idle state
      return; // Done — the onStatus callback will handle auto-sending the transcription
    }
    await _tts.stop(); // Stop any ongoing speech before starting to record, so the mic doesn't pick up the TTS audio
    _inputController.clear(); // Clear the text field so the transcription starts fresh
    setState(() => _isListening = true); // Show the red "recording" state on the mic button
    await _stt.listen( // Start the microphone and begin transcribing
      onResult: (r) =>
          setState(() => _inputController.text = r.recognizedWords), // Update the text field live as the STT engine produces partial results
      listenFor: const Duration(seconds: 30), // Automatically stop if the user speaks for longer than 30 seconds
      pauseFor: const Duration(seconds: 2), // Also stop if the user pauses for 2 seconds — treats it as end of speech
      listenOptions: stt.SpeechListenOptions(
        cancelOnError: true, // Stop listening automatically if an error occurs
        partialResults: true, // Show intermediate (in-progress) results in the text field as the user speaks
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _shortError(Object e) { // Converts a raw exception into a short, human-readable error phrase for display in the chat
    final s = e.toString(); // Turn the exception object into a string so we can search it for known codes
    if (s.contains('429') || s.contains('quota')) return 'rate limit reached'; // HTTP 429 = Too Many Requests; "quota" also signals the daily limit was hit
    if (s.contains('403') || s.contains('401')) return 'invalid API key'; // HTTP 403 = Forbidden, 401 = Unauthorized — both mean the API key is wrong or missing
    if (s.contains('503') || s.contains('unavailable')) return 'service unavailable'; // HTTP 503 = the server is down or overloaded
    return 'network error'; // Catch-all for anything else
  }

  void _scrollToBottom() { // Smoothly scrolls the message list to the very end so the latest message is always visible
    WidgetsBinding.instance.addPostFrameCallback((_) { // addPostFrameCallback runs the code AFTER the current frame is drawn — ensures the layout is settled before we calculate the scroll extent
      if (_scrollController.hasClients) { // Only scroll if the ListView is actually attached and on screen
        _scrollController.animateTo( // Animate the scroll position rather than jumping instantly
          _scrollController.position.maxScrollExtent, // The furthest possible scroll position — i.e. the very bottom of the list
          duration: const Duration(milliseconds: 280), // The animation takes 280 milliseconds — short enough to feel snappy
          curve: Curves.easeOut, // Ease-out makes the scroll decelerate gently at the end
        );
      }
    });
  }

  void _resetChat() { // Clears the entire conversation and starts fresh with a new welcome message
    _tts.stop(); // Stop any ongoing speech immediately
    if (_gemini.isReady) _gemini.reset(systemInstruction: _activePrompt); // Tell Gemini to forget the conversation history and start a new session with the same system prompt
    _hf.reset(systemInstruction: _activePromptLite); // Same reset for the HuggingFace service
    setState(() {
      _messages.clear(); // Empty the messages list — all chat bubbles disappear
      _emergencyMode = false; // Hide the red emergency banner if it was showing
      _pendingImage = null; // Discard any image the user had attached but not yet sent
    });
    _addAiMsg('Chat cleared. How can I help?'); // Show a new greeting so the user knows the reset worked
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) { // Flutter calls this every time the state changes — it returns the complete widget tree for the screen
    final isDark = AppSettings.instance.lowBattery; // Read the low-battery / dark-mode flag from app-wide settings
    final bg = isDark ? Colors.black : const Color(0xFFF4F7FA); // Pick the main background colour based on light/dark mode
    final barBg = isDark ? TogetherTheme.amoledSurface : Colors.white; // The colour used for the AppBar and input bar background
    final titleColor =
        isDark ? TogetherTheme.amoledTextPrimary : TogetherTheme.deepOcean; // Colour for the title text and the text inside the input field
    final subtitleColor =
        isDark ? TogetherTheme.amoledTextSecondary : TogetherTheme.ink; // Colour for the subtitle text below the title and hint text in the input field
    final inputBorder =
        isDark ? TogetherTheme.amoledBorder : const Color(0xFFD3DCE4); // The colour of the thin line separating the input bar from the chat list

    return Scaffold( // Scaffold provides the standard screen structure: AppBar, body, and bottom padding
      backgroundColor: bg, // Apply the theme background colour to the whole screen
      appBar: AppBar( // The top navigation bar
        backgroundColor: barBg, // Match the bar's background to the theme
        foregroundColor: titleColor, // Controls the default icon and text colour inside the AppBar
        elevation: 0, // Remove the shadow beneath the AppBar for a flat modern look
        title: Column( // The title area contains two rows of text stacked vertically
          crossAxisAlignment: CrossAxisAlignment.start, // Align both rows to the left edge
          mainAxisSize: MainAxisSize.min, // Don't take more vertical space than the two text rows need
          children: [
            Row( // First row: the app name + a small status badge
              children: [
                Text(
                  'Together AI', // The name displayed in the title
                  style: TextStyle(
                    fontSize: 18, // Slightly smaller than the default AppBar title to leave room for the badge
                    fontWeight: FontWeight.w700, // Bold text
                    color: titleColor, // Theme-aware colour
                    fontFamily: 'RobotoSlab', // Use the slab-serif font defined in the project's assets
                  ),
                ),
                const SizedBox(width: 8), // Small horizontal gap between the title text and the status badge
                Container( // The coloured pill-shaped badge showing "Connected · Gemini" or "Offline"
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2), // Tight padding inside the badge
                  decoration: BoxDecoration(
                    color: isDark ? _kGreenDark : _kGreenLight, // Dark green background in dark mode, pale green in light mode
                    borderRadius: BorderRadius.circular(6), // Rounded corners make it look like a badge/chip
                  ),
                  child: Text(
                    _isOnline && _gemini.isReady
                        ? 'Connected • Gemini' // Best case: Gemini is up and running
                        : (_isOnline ? 'Connected • Fine-tuned' : 'Offline'), // Fallback labels depending on which backend is active
                    style: const TextStyle(
                      fontSize: 10, // Very small text to fit inside the badge
                      fontWeight: FontWeight.w700, // Bold so it is still readable at small size
                      color: _kGreen, // Always use the main green colour for the badge text
                    ),
                  ),
                ),
              ],
            ),
            Text( // Second row: a longer subtitle describing the current backend in plain language
              _isOnline && _gemini.isReady
                  ? 'Online · Gemini Flash' // Gemini is active
                  : (_isOnline
                      ? 'Online · Fine-tuned Assistant' // HuggingFace fallback is active
                      : 'Offline · No AI available'), // No internet — no AI
              style: TextStyle(fontSize: 12, color: subtitleColor), // Small, muted text beneath the title
            ),
          ],
        ),
        actions: [ // Buttons on the right side of the AppBar
          // Switch to voice call mode
          Tooltip( // Shows a tooltip label when the user long-presses or hovers over the button
            message: 'Voice call mode',
            child: IconButton(
              icon: Icon(
                Icons.call_rounded, // Phone handset icon
                color: isDark
                    ? TogetherTheme.amoledTextSecondary
                    : TogetherTheme.ink, // Theme-aware icon colour
              ),
              onPressed: () => Navigator.of(context).pushReplacement( // Replace the current screen with the CallScreen — uses pushReplacement so the user can't go back to this screen via the back button
                MaterialPageRoute(builder: (_) => const CallScreen()),
              ),
            ),
          ),
          // Wikipedia agent skill toggle
          Tooltip(
            message: 'Agent Skills (Wikipedia)',
            child: IconButton(
              icon: Icon(
                Icons.travel_explore_rounded, // Globe with a magnifying glass — represents web/knowledge search
                color: _agentSkillsEnabled
                    ? _kWikiBlue // Blue when the skill is ON — provides visual feedback that it is active
                    : (isDark
                        ? TogetherTheme.amoledTextSecondary
                        : TogetherTheme.ink), // Default colour when the skill is OFF
              ),
              onPressed: () {
                setState(() => _agentSkillsEnabled = !_agentSkillsEnabled); // Toggle the boolean flag and rebuild the UI with the new icon colour
                ScaffoldMessenger.of(context).showSnackBar( // Show a brief confirmation message so the user knows the toggle worked
                  SnackBar(
                    content: Text(_agentSkillsEnabled
                        ? 'Agent Skills ON — Wikipedia grounding enabled' // Message when turning ON
                        : 'Agent Skills OFF'), // Message when turning OFF
                    duration: const Duration(seconds: 2), // The snackbar disappears after 2 seconds
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded), // Circular arrow — universally understood as "reset" or "refresh"
            tooltip: 'Clear chat', // Tooltip shown on long press
            onPressed: _modelReady ? _resetChat : null, // Disable the button (null onPressed = greyed out) until the AI model is ready
          ),
        ],
      ),
      body: Column( // The main body is a vertical column: emergency banner (conditional) + message list + image preview (conditional) + input bar
        children: [
          // Emergency banner
          if (_emergencyMode) // Only show the banner when _emergencyMode is true (i.e. an emergency keyword was detected)
            _EmergencyBanner(
                onDismiss: () => setState(() => _emergencyMode = false)), // Pass a callback so the banner can dismiss itself when the user taps the X

          // Messages list
          Expanded( // Expanded makes the message list take up all available vertical space between the banner and the input bar
            child: !_contextReady && _messages.isEmpty
                ? _LoadingState(isDark: isDark) // Show a spinner if the model context hasn't loaded yet and there are no messages
                : ListView.builder( // Efficient list that only renders the bubbles currently visible on screen
                    controller: _scrollController, // Connect the scroll controller so we can programmatically scroll to the bottom
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), // Padding around the entire list: 16px on sides and top, 8px at the bottom
                    itemCount: _messages.length, // Total number of message bubbles to render
                    itemBuilder: (context, i) =>
                        _MsgBubble(msg: _messages[i], isDark: isDark), // Build one bubble for each message in the list
                  ),
          ),

          // Pending image preview
          if (_pendingImage != null) // Only show the preview bar when there is an image waiting to be sent
            _ImagePreviewBar(
              bytes: _pendingImage!, // Pass the raw bytes so the bar can display a thumbnail
              onRemove: _clearPendingImage, // Callback wired to the X button inside the preview bar
              isDark: isDark, // Pass the theme flag so the bar can match the rest of the UI
            ),

          // Input bar
          Container( // A container that holds the text field and action buttons at the bottom of the screen
            decoration: BoxDecoration(
              color: barBg, // Background matches the AppBar for a consistent top/bottom bar style
              border: Border(top: BorderSide(color: inputBorder)), // A thin line along the top edge separates the bar from the message list
            ),
            padding: EdgeInsets.fromLTRB(
              12, 8, 12,
              8 + MediaQuery.of(context).viewInsets.bottom, // viewInsets.bottom equals the keyboard height — adding it here pushes the bar above the keyboard when it appears
            ),
            child: SafeArea( // SafeArea adds automatic padding for the device's home indicator and notches
              top: false, // We only need bottom-safe-area padding here; the AppBar handles the top
              child: Row( // Horizontal row: mic button | attach button | text field | send button
                crossAxisAlignment: CrossAxisAlignment.end, // Align all items to the bottom so the mic and send buttons sit flush with the bottom of the multi-line text field
                children: [
                  // Mic
                  _MicButton(
                    isListening: _isListening, // Controls the red "active" state of the mic button
                    enabled: _sttAvailable && !_isLoading && _modelReady, // Mic is disabled while AI is responding, STT is unavailable, or model isn't ready
                    isDark: isDark, // Theme flag for colour adaptation
                    onTap: _toggleListen, // Start or stop microphone recording when tapped
                  ),
                  const SizedBox(width: 4), // Tiny gap between the mic button and the attach button
                  if (_gemini.isReady) // Only show the image attach button when Gemini is available — only Gemini supports vision/image input
                    _AttachButton(
                      hasPending: _pendingImage != null, // Turns the button green when an image is already attached
                      enabled: !_isLoading && _modelReady, // Disabled while the AI is responding
                      isDark: isDark, // Theme flag
                      onTap: _pickImage, // Open the gallery picker when tapped
                    ),
                  const SizedBox(width: 6), // Small gap before the text field
                  // Text field
                  Expanded( // Expanded makes the text field fill all remaining horizontal space between the buttons
                    child: TextField(
                      controller: _inputController, // Connect the controller so we can read and clear the field programmatically
                      maxLines: 4, // Allow the field to grow up to 4 lines before it starts scrolling internally
                      minLines: 1, // Start at a single-line height to keep the bar compact
                      textInputAction: TextInputAction.send, // Shows a "send" key on the soft keyboard so the user can send without tapping the button
                      style: TextStyle(color: titleColor), // Theme-aware text colour
                      decoration: InputDecoration(
                        hintText: _isListening
                            ? 'Listening…' // Show "Listening…" while recording
                            : (_pendingImage != null
                                ? 'Add a message about the image…' // Remind the user they can add context to the attached photo
                                : 'Ask anything…'), // Default placeholder
                        hintStyle: TextStyle(
                            color: subtitleColor.withValues(alpha: 0.6)), // Hint text is semi-transparent so it is visually subordinate to actual input
                        filled: true, // Fill the field background with a colour (required to use fillColor)
                        fillColor: isDark
                            ? TogetherTheme.amoledSurfaceElevated // Slightly lighter than the bar background in AMOLED mode
                            : const Color(0xFFEDF1F5), // Pale grey-blue in light mode
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24), // Pill-shaped border with very rounded corners
                          borderSide: BorderSide.none, // No visible border line — the fill colour defines the shape instead
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10), // Inner padding so the text doesn't touch the edges of the pill shape
                      ),
                      onSubmitted: (v) => _send(v), // Called when the user taps the keyboard's send key — sends the text immediately
                    ),
                  ),
                  const SizedBox(width: 8), // Gap between the text field and the send button
                  // Send
                  _SendButton(
                    enabled: !_isLoading && _modelReady, // Disabled while the AI is working or not yet ready
                    isDark: isDark, // Theme flag
                    onTap: () => _send(_inputController.text), // Read the current text and send it when the button is tapped
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _EmergencyBanner extends StatelessWidget { // A full-width red banner that appears at the top of the screen when an emergency keyword is detected
  const _EmergencyBanner({required this.onDismiss}); // onDismiss is a callback called when the user taps the X to close the banner
  final VoidCallback onDismiss; // VoidCallback is just a function that takes no arguments and returns nothing

  @override
  Widget build(BuildContext context) {
    return Container( // The banner itself — a solid red rectangle spanning the full screen width
      width: double.infinity, // Stretch to fill the entire horizontal space
      color: const Color(0xFFB91C1C), // Dark red background — high-contrast to convey urgency
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), // Comfortable padding inside the banner
      child: Row( // Horizontal layout: warning icon | text | close button
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.white, size: 18), // Amber warning triangle icon for instant visual recognition
          const SizedBox(width: 8), // Gap between the icon and the message text
          const Expanded( // Expanded makes the text fill all space between the icon and the close button
            child: Text(
              'If you are in immediate danger, call 112 now.', // Clear, actionable emergency instruction
              style: TextStyle(
                  color: Colors.white, // White text on red for maximum contrast
                  fontWeight: FontWeight.w600, // Semi-bold for readability
                  fontSize: 13), // Slightly smaller than body text to fit comfortably in the banner
            ),
          ),
          GestureDetector( // Wrap the close icon in a GestureDetector so it is tappable
            onTap: onDismiss, // Call the provided callback to remove the banner from the UI
            child: const Icon(Icons.close, color: Colors.white, size: 18), // Standard "X" close icon in white
          ),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget { // A simple centred loading indicator shown before the first message appears and while the model context is loading
  const _LoadingState({required this.isDark}); // isDark controls whether the text colour is light or dark
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Center( // Centre everything in the available space (the Expanded region where the message list normally lives)
      child: Column(
        mainAxisSize: MainAxisSize.min, // Only take up as much vertical space as the spinner and text need
        children: [
          const CircularProgressIndicator(color: _kGreen), // Spinning green circle indicating loading
          const SizedBox(height: 16), // Vertical gap between the spinner and the label
          Text(
            'Loading on-device model…', // Tells the user what is happening while they wait
            style: TextStyle(
              color: isDark
                  ? TogetherTheme.amoledTextSecondary // Muted grey in dark mode
                  : TogetherTheme.ink, // Dark ink colour in light mode
            ),
          ),
        ],
      ),
    );
  }
}

class _MsgBubble extends StatefulWidget { // A single chat message bubble — StatefulWidget because the thinking section can be expanded/collapsed
  const _MsgBubble({required this.msg, required this.isDark});
  final _Msg msg; // The message data object this bubble should display
  final bool isDark; // Theme flag passed down from the parent screen

  @override
  State<_MsgBubble> createState() => _MsgBubbleState();
}

class _MsgBubbleState extends State<_MsgBubble> {
  @override
  Widget build(BuildContext context) {
    final msg = widget.msg; // Shorthand alias so we don't have to write widget.msg everywhere
    final isDark = widget.isDark; // Shorthand alias for the theme flag
    final isUser = msg.isUser; // Whether this bubble is a user message (right-aligned, green) or AI message (left-aligned, white/dark)

    final userBg = isDark ? _kGreenDark : _kGreen; // User bubble background: dark green in dark mode, bright green in light mode
    final aiBg = isDark ? TogetherTheme.amoledSurface : Colors.white; // AI bubble background: dark surface in dark mode, white in light mode
    final aiBorder =
        isDark ? TogetherTheme.amoledBorder : const Color(0xFFDCE4EA); // Subtle border colour for the AI bubble
    final aiText =
        isDark ? TogetherTheme.amoledTextPrimary : TogetherTheme.deepOcean; // Text colour inside AI bubbles

    return Padding(
      padding: const EdgeInsets.only(bottom: 12), // Vertical space between consecutive message bubbles
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start, // User messages flush right, AI messages flush left
        children: [
          Row(
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start, // Same left/right alignment for the row itself
            crossAxisAlignment: CrossAxisAlignment.end, // Align the avatar and bubble to the bottom of the row
            children: [
              if (!isUser) // Only show the AI avatar on the left for AI messages; user messages have no avatar
                Container(
                  width: 32,
                  height: 32,
                  margin: const EdgeInsets.only(right: 8), // Gap between the avatar circle and the bubble
                  decoration: BoxDecoration(
                    color: isDark ? _kGreenDark : _kGreenLight, // Avatar background: dark green / pale green depending on theme
                    shape: BoxShape.circle, // Make it a perfect circle
                  ),
                  child:
                      const Icon(Icons.memory_rounded, size: 16, color: _kGreen), // Small "chip" icon representing an AI/neural network
                ),
              Flexible( // Flexible lets the bubble shrink or grow without overflowing the row
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.72, // Bubbles can be at most 72% of the screen width — prevents very long messages from touching both edges
                  ),
                  child: Column(
                    crossAxisAlignment: isUser
                        ? CrossAxisAlignment.end // Align content inside the bubble to the right for user messages
                        : CrossAxisAlignment.start, // Align to the left for AI messages
                    children: [
                      // ── Thinking section ──────────────────────────────────
                      if (!isUser && msg.thinkingText.isNotEmpty) // Only show the thinking bubble for AI messages that include reasoning text
                        _ThinkingBubble(
                          text: msg.thinkingText, // The raw reasoning/thinking text to display when expanded
                          expanded: msg.thinkingExpanded, // Whether the section is currently open or collapsed
                          isStreaming: msg.isStreaming, // Shows "Thinking…" instead of "Reasoning" while the AI is still generating
                          isDark: isDark, // Theme flag
                          onToggle: () => setState(
                              () => msg.thinkingExpanded = !msg.thinkingExpanded), // Toggle the expanded state and rebuild
                        ),

                      // ── Image preview (user messages) ─────────────────────
                      if (msg.imageBytes != null) // Only render an image if one was attached to this message
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6), // Small gap below the image before the text bubble
                          child: ClipRRect( // ClipRRect clips its child to a rounded rectangle shape
                            borderRadius: BorderRadius.circular(14), // Nicely rounded image corners to match the bubble style
                            child: Image.memory(
                              msg.imageBytes!, // Decode and display the raw image bytes
                              width: 200, // Fixed display width — keeps image thumbnails a consistent size
                              height: 200, // Fixed display height
                              fit: BoxFit.cover, // Scale and crop the image to fill the 200×200 box without distorting aspect ratio
                            ),
                          ),
                        ),

                      // ── Text bubble ──────────────────────────────────────
                      if (msg.text.isNotEmpty || msg.isStreaming) // Show the bubble if there is text OR if the AI is still streaming (so the "…" placeholder appears)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10), // Inner padding so text doesn't touch the bubble edges
                          decoration: BoxDecoration(
                            color: isUser ? userBg : aiBg, // Green for user, white/dark for AI
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(18), // All corners rounded…
                              topRight: const Radius.circular(18),
                              bottomLeft: Radius.circular(isUser ? 18 : 4), // …except the corner closest to the avatar: flat for AI (left) or rounded for user (right)
                              bottomRight: Radius.circular(isUser ? 4 : 18), // Flat bottom-right for user messages — the "speech bubble tail" effect
                            ),
                            border: isUser
                                ? null // User bubbles have no border (green background is sufficient)
                                : Border.all(color: aiBorder), // AI bubbles get a subtle border to lift them off the background
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min, // The row only takes as much width as its content needs
                            crossAxisAlignment: CrossAxisAlignment.end, // Align text and the streaming dot to the bottom
                            children: [
                              Flexible( // Flexible lets the text wrap naturally without overflowing
                                child: Text(
                                  msg.text.isEmpty && msg.isStreaming
                                      ? '…' // Show an ellipsis placeholder until the first token arrives
                                      : msg.text, // Otherwise display the full current text (which grows token by token)
                                  style: TextStyle(
                                    fontSize: 15, // Comfortable reading size
                                    height: 1.45, // Line height — adds breathing room between lines of text
                                    color: isUser ? Colors.white : aiText, // White text on green; themed colour on AI bubbles
                                  ),
                                ),
                              ),
                              if (msg.isStreaming && msg.text.isNotEmpty) ...[ // Only show the pulsing dot once some text has arrived (not alongside the "…" placeholder)
                                const SizedBox(width: 4), // Tiny gap before the dot
                                Container(
                                  width: 6,
                                  height: 6,
                                  margin: const EdgeInsets.only(bottom: 2), // Nudge the dot slightly up from the baseline
                                  decoration: const BoxDecoration(
                                    color: _kGreen, // Green pulsing dot
                                    shape: BoxShape.circle, // Make it a perfect circle
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                      // ── Wikipedia source card ────────────────────────────
                      if (!isUser && msg.wikiResult != null) // Only show the Wikipedia card on AI messages that have an associated Wikipedia result
                        Padding(
                          padding: const EdgeInsets.only(top: 6), // Small gap between the text bubble and the source card
                          child: _WikiCard(
                            result: msg.wikiResult!, // Pass the title and summary data to the card
                            isDark: isDark, // Theme flag
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (isUser) const SizedBox(width: 40), // Reserve space on the right of user bubbles equivalent to the AI avatar width — keeps alignment consistent
            ],
          ),
        ],
      ),
    );
  }
}

// ── Thinking bubble ───────────────────────────────────────────────────────────

class _ThinkingBubble extends StatelessWidget { // A collapsible purple section shown above the AI's reply when the model produced reasoning/thinking text
  const _ThinkingBubble({
    required this.text, // The full reasoning text from the model
    required this.expanded, // Whether the section is currently open
    required this.isStreaming, // Whether the AI is still generating — changes the header label
    required this.isDark, // Theme flag
    required this.onToggle, // Callback to expand or collapse the section when tapped
  });

  final String text;
  final bool expanded;
  final bool isStreaming;
  final bool isDark;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark ? const Color(0xFF2E1065) : _kThinkPurpleLight; // Dark purple in AMOLED mode; pale purple in light mode
    return GestureDetector( // The entire thinking bubble is tappable to toggle open/closed
      onTap: onToggle, // Call the parent's setState to flip the expanded flag
      child: Container(
        margin: const EdgeInsets.only(bottom: 6), // Gap below the thinking bubble before the text bubble starts
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // Internal padding
        decoration: BoxDecoration(
          color: bgColor, // Purple-tinted background
          borderRadius: BorderRadius.circular(12), // Rounded corners
          border: Border.all(color: _kThinkPurple.withValues(alpha: 0.4)), // Faint purple border — 40% opacity so it is subtle
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, // Left-align content inside the bubble
          children: [
            Row( // Header row: brain icon | label text | spacer | chevron
              mainAxisSize: MainAxisSize.min, // Only take as much width as needed
              children: [
                const Icon(Icons.psychology_rounded,
                    size: 14, color: _kThinkPurple), // Brain icon representing AI reasoning
                const SizedBox(width: 6), // Gap between icon and label
                Text(
                  isStreaming ? 'Thinking…' : 'Reasoning', // Dynamic label: "Thinking…" while generating, "Reasoning" once complete
                  style: const TextStyle(
                    fontSize: 12, // Small, compact header text
                    fontWeight: FontWeight.w700, // Bold so it reads clearly at 12px
                    color: _kThinkPurple, // Purple text matches the bubble's colour scheme
                  ),
                ),
                const Spacer(), // Pushes the chevron icon to the far right
                Icon(
                  expanded
                      ? Icons.expand_less_rounded // Up-arrow when expanded (tapping will collapse)
                      : Icons.expand_more_rounded, // Down-arrow when collapsed (tapping will expand)
                  size: 16,
                  color: _kThinkPurple, // Purple to match
                ),
              ],
            ),
            if (expanded) ...[ // Only render the reasoning text when the section is expanded
              const SizedBox(height: 6), // Gap between the header and the body text
              Text(
                text, // The full reasoning text from the model
                style: TextStyle(
                  fontSize: 12, // Compact — reasoning text is supplementary, not primary
                  height: 1.5, // Generous line height for readability
                  color: isDark
                      ? const Color(0xFFC4B5FD) // Pale lavender for dark mode — high contrast on dark purple background
                      : const Color(0xFF4C1D95), // Deep purple for light mode — readable on pale purple background
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Wikipedia card ────────────────────────────────────────────────────────────

class _WikiCard extends StatelessWidget { // A small attribution card shown beneath an AI reply when Wikipedia was used as a source
  const _WikiCard({required this.result, required this.isDark});
  final WikiResult result; // Holds the Wikipedia article title (and summary used by the AI, though not shown here)
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10), // Uniform padding inside the card
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E3A5F) : _kWikiBlueBg, // Dark navy in AMOLED mode; pale sky-blue in light mode
        borderRadius: BorderRadius.circular(10), // Rounded corners to match the bubble style
        border: Border.all(color: _kWikiBlue.withValues(alpha: 0.3)), // Faint blue border — 30% opacity for subtlety
      ),
      child: Row( // Horizontal layout: globe icon | "Wikipedia · Article Title"
        children: [
          const Icon(Icons.travel_explore_rounded, size: 14, color: _kWikiBlue), // Globe-with-search icon to indicate a web source
          const SizedBox(width: 6), // Gap between icon and text
          Expanded( // Expanded lets the text take all remaining width and truncate if too long
            child: Text(
              'Wikipedia · ${result.title}', // Shows which Wikipedia article was used as context
              style: const TextStyle(
                fontSize: 11, // Very small — this is attribution metadata, not primary content
                fontWeight: FontWeight.w600, // Semi-bold for legibility at small size
                color: _kWikiBlue, // Blue text links the card visually to Wikipedia
              ),
              overflow: TextOverflow.ellipsis, // Truncate with "…" if the title is too long to fit
            ),
          ),
        ],
      ),
    );
  }
}

// ── Image preview bar ─────────────────────────────────────────────────────────

class _ImagePreviewBar extends StatelessWidget { // A horizontal bar above the input row that shows a thumbnail of the attached image
  const _ImagePreviewBar({
    required this.bytes, // Raw image bytes to decode and display as a thumbnail
    required this.onRemove, // Callback for the X button to discard the attachment
    required this.isDark, // Theme flag
  });

  final Uint8List bytes;
  final VoidCallback onRemove;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isDark ? TogetherTheme.amoledSurface : Colors.white, // Bar background matches the input bar for visual continuity
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), // Padding: left 16, top 8, right 16, bottom 4
      child: Row( // Horizontal layout: thumbnail | label text | remove button
        children: [
          ClipRRect( // Clip the thumbnail image to rounded corners
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(bytes, width: 56, height: 56, fit: BoxFit.cover), // Small 56×56 square preview of the attached image
          ),
          const SizedBox(width: 10), // Gap between thumbnail and label
          Expanded( // Label fills all remaining space between thumbnail and button
            child: Text(
              'Image attached — add a message or send now', // Helpful prompt telling the user they can type more or just tap send
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? TogetherTheme.amoledTextSecondary // Muted in dark mode
                    : TogetherTheme.ink, // Dark ink in light mode
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18), // Small X icon to remove the attachment
            onPressed: onRemove, // Calls _clearPendingImage in the parent state
          ),
        ],
      ),
    );
  }
}

// ── Input buttons ─────────────────────────────────────────────────────────────

class _MicButton extends StatelessWidget { // A circular button that starts/stops microphone recording
  const _MicButton({
    required this.isListening, // True when the mic is actively recording — turns the button red
    required this.enabled, // False when STT is unavailable or the AI is busy — disables tap
    required this.isDark, // Theme flag
    required this.onTap, // Callback to _toggleListen
  });

  final bool isListening, enabled, isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null, // Only register taps when the button is enabled; null disables interaction
      child: AnimatedContainer( // AnimatedContainer smoothly transitions between its old and new style when properties change
        duration: const Duration(milliseconds: 200), // The colour transition takes 200ms — fast enough to feel responsive
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isListening
              ? const Color(0xFFDC2626) // Bright red while recording — universal "recording" signal
              : (isDark
                  ? TogetherTheme.amoledSurfaceElevated // Dark elevated surface in AMOLED mode
                  : const Color(0xFFEDF1F5)), // Pale grey-blue in light mode
          shape: BoxShape.circle, // Perfect circle for all states
        ),
        child: Icon(
          isListening ? Icons.mic_rounded : Icons.mic_none_rounded, // Filled mic when recording; outline mic when idle
          size: 18,
          color: isListening
              ? Colors.white // White icon on red background for contrast
              : (isDark ? TogetherTheme.amoledTextSecondary : TogetherTheme.ink), // Theme-aware grey/dark icon when idle
        ),
      ),
    );
  }
}

class _AttachButton extends StatelessWidget { // A circular button that opens the image gallery — only visible when Gemini is ready
  const _AttachButton({
    required this.hasPending, // True when an image is already attached — turns the button green
    required this.enabled, // False while the AI is busy
    required this.isDark, // Theme flag
    required this.onTap, // Callback to _pickImage
  });

  final bool hasPending, enabled, isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null, // Disable when the AI is working
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: hasPending
              ? _kGreen // Green fill when an image is pending — provides confirmation that something is attached
              : (isDark
                  ? TogetherTheme.amoledSurfaceElevated // Matches the mic button style in dark mode
                  : const Color(0xFFEDF1F5)), // Matches the mic button style in light mode
          shape: BoxShape.circle, // Consistent circle shape across all input buttons
        ),
        child: Icon(
          Icons.image_rounded, // Image/photo icon
          size: 18,
          color: hasPending
              ? Colors.white // White icon on green background when an image is attached
              : (isDark ? TogetherTheme.amoledTextSecondary : TogetherTheme.ink), // Greyed out when idle
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget { // A circular send button — green when enabled, greyed out when the AI is busy
  const _SendButton({
    required this.enabled, // False while waiting for an AI response
    required this.isDark, // Theme flag
    required this.onTap, // Callback to _send
  });

  final bool enabled, isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null, // Only register taps when the button is not disabled
      child: Container(
        width: 44, // Slightly larger than the other buttons — makes it the primary action
        height: 44,
        decoration: BoxDecoration(
          color: enabled
              ? _kGreen // Bright green when ready to send — draws the eye as the primary action
              : (isDark
                  ? TogetherTheme.amoledSurfaceElevated // Muted dark surface when disabled
                  : const Color(0xFFD3DCE4)), // Muted pale grey when disabled in light mode
          shape: BoxShape.circle, // Circular shape consistent with the other input buttons
        ),
        child: Icon(
          Icons.send_rounded, 
          size: 18,
          color: enabled
              ? Colors.white 
              : (isDark
                  ? TogetherTheme.amoledTextSecondary 
                  : const Color(0xFFA0B0BE)), 
        ),
      ),
    );
  }
}
