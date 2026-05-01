import 'dart:async'; // Imports async tools like StreamSubscription for listening to data streams over time
import 'dart:math' as math; // Imports math functions (like cos/sin) used when drawing the radar, aliased as 'math'

import 'package:flutter/foundation.dart' show kIsWeb; // Imports kIsWeb, a constant that is true when the app runs in a browser
import 'package:flutter/material.dart'; // Imports the core Flutter UI toolkit (widgets, colors, layouts, etc.)
import 'package:geolocator/geolocator.dart'; // Imports the Geolocator plugin for checking/requesting location services and GPS
import 'package:permission_handler/permission_handler.dart'; // Imports the permission_handler plugin for requesting runtime permissions (location, etc.)

import '../../data/offline_seed_data.dart'; // Imports offline data like the user's medical profile stored locally on device
import '../../services/app_settings_service.dart'; // Imports the app settings service (display name, low-battery mode, etc.)
import '../../services/p2p_service.dart'; // Imports the P2P service that handles Wi-Fi Direct device discovery and messaging
import '../../theme/app_theme.dart'; // Imports the app's shared color and theme constants

// ── Palette ───────────────────────────────────────────────────────────────────
const _kRed = Color(0xFFDC2626); // Bright red color used for SOS and error states
const _kRedLight = Color(0xFFFEE2E2); // Light red background used for SOS message bubbles in light mode
const _kRedDark = Color(0xFF7F1D1D); // Dark red used for SOS backgrounds in dark/AMOLED mode
const _kGreen = Color(0xFF059669); // Green color used for connected devices and the send button
const _kGreenLight = Color(0xFFD1FAE5); // Light green background used for avatar icons in light mode

// ═════════════════════════════════════════════════════════════════════════════
// Main P2P screen — conversations list
// ═════════════════════════════════════════════════════════════════════════════

class P2pScreen extends StatefulWidget { // Declares P2pScreen as a widget that has mutable state (it changes over time)
  const P2pScreen({super.key}); // Constructor — passes a key to the parent class so Flutter can track this widget

  @override
  State<P2pScreen> createState() => _P2pScreenState(); // Tells Flutter which State class manages this widget's data
}

class _P2pScreenState extends State<P2pScreen> with WidgetsBindingObserver { // The state class; WidgetsBindingObserver lets it react to app lifecycle changes (foreground/background)
  P2pService? _service; // The service object that runs Wi-Fi Direct scanning and messaging; null until started
  StreamSubscription? _devSub; // Subscription that listens for updates to the list of nearby devices
  StreamSubscription? _msgSub; // Subscription that listens for incoming messages from peers
  StreamSubscription? _logSub; // Subscription that listens for debug log entries from the P2P service

  final List<P2pDevice> _devices = []; // Holds all nearby devices found by scanning (both connected and not)
  final Map<String, List<P2pMessage>> _conversations = {}; // Stores per-peer message history, keyed by the peer's device ID
  final List<P2pMessage> _broadcasts = []; // Stores SOS broadcast messages received from any peer (not tied to one conversation)
  final Map<String, int> _unread = {}; // Tracks how many unread messages each peer has sent (keyed by device ID)
  String? _openChatId; // The device ID of the peer whose chat screen is currently open (null if no chat is open)

  final List<String> _logs = []; // List of debug log strings shown in the collapsible debug panel
  bool _logsExpanded = false; // Tracks whether the debug panel is expanded or collapsed

  bool _starting = false; // True while the P2P service is in the process of starting up
  bool _started = false; // True once the P2P service has successfully started and is scanning
  String? _permissionError; // Holds an error message string if a permission was denied; null means no error
  bool _permPermanentlyDenied = false; // True if a permission was permanently denied (user must go to Settings)
  bool _locationOff = false; // True if the device's location services are turned off entirely

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() { // Called once when this screen is first inserted into the widget tree
    super.initState(); // Always call super.initState() first
    WidgetsBinding.instance.addObserver(this); // Registers this object to receive app lifecycle events (resume, pause, etc.)
    if (!kIsWeb) { // Only try to start on mobile/desktop — Wi-Fi Direct is not supported on web
      WidgetsBinding.instance.addPostFrameCallback((_) => _start()); // Waits until the first frame is drawn, then starts the P2P service
    }
  }

  @override
  void dispose() { // Called when this screen is removed from the widget tree (user navigates away)
    WidgetsBinding.instance.removeObserver(this); // Stops receiving lifecycle events to avoid memory leaks
    _devSub?.cancel(); // Cancels the device stream subscription if it exists
    _msgSub?.cancel(); // Cancels the message stream subscription if it exists
    _logSub?.cancel(); // Cancels the log stream subscription if it exists
    _service?.dispose(); // Shuts down the P2P service cleanly
    super.dispose(); // Always call super.dispose() last
  }

  Future<void> _disposeService() async { // Helper that tears down all stream subscriptions and the service before restarting
    _devSub?.cancel(); // Cancels the device stream listener
    _msgSub?.cancel(); // Cancels the message stream listener
    _logSub?.cancel(); // Cancels the log stream listener
    _devSub = _msgSub = _logSub = null; // Sets all subscription references to null so they can be garbage collected
    await _service?.dispose(); // Waits for the service to fully shut down
    _service = null; // Clears the service reference
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) { // Called automatically when the app moves between foreground and background
    if (state == AppLifecycleState.resumed && !_started && !_starting) { // If the app just came back to the foreground and P2P hasn't started yet
      // Retry whenever the user returns from Settings or Location settings.
      _start(); // Attempts to start the P2P service again (the user may have granted permissions in Settings)
    }
  }

  // ── Start / stop ───────────────────────────────────────────────────────────

  Future<void> _start() async { // Main function that initializes and starts the Wi-Fi Direct P2P service
    // Always tear down any previous attempt before retrying.
    await _disposeService(); // Cleans up any previous service instance before starting fresh
    if (!mounted) return; // Safety check: stops if the widget has been removed from the tree
    setState(() { // Updates the UI to show the "starting" state and clear any previous errors
      _starting = true; // Shows a loading indicator while setup is in progress
      _permissionError = null; // Clears any previous permission error message
      _locationOff = false; // Clears the "location off" error
      _started = false; // Marks the service as not yet started
      _devices.clear(); // Removes any previously found devices from the list
    });

    // 1. Location services must be on for Wi-Fi Direct peer scanning.
    try {
      final locationEnabled = await Geolocator.isLocationServiceEnabled(); // Checks if the phone's location services (GPS) are turned on
      if (!locationEnabled) { // If location is disabled
        if (mounted) { // Check the widget is still in the tree before calling setState
          setState(() { // Updates the UI to show the location-off error banner
            _starting = false; // No longer "starting" — we stopped due to the error
            _locationOff = true; // Flags that location services are off so the error banner appears
          });
        }
        return; // Exits early — cannot proceed without location
      }
    } catch (_) {} // Silently ignores any error from the location check (avoids crashing)

    // 2. Runtime permissions.
    final (denied, permanent) = await _requestPermissions(); // Requests location permission and gets back which were denied and whether any are permanently denied
    if (denied.isNotEmpty) { // If any permissions were not granted
      if (mounted) { // Check the widget is still in the tree
        setState(() { // Updates the UI to show the appropriate permission error message
          _starting = false; // No longer "starting"
          _permPermanentlyDenied = permanent; // Records if the user permanently denied a permission
          _permissionError = permanent // Picks the right error message based on whether it's permanent
              ? 'Some permissions are permanently blocked. Open Settings and '
                'allow Location and Nearby devices for this app.'
              : 'Missing permissions: ${denied.join(', ')}. Tap Retry.';
        });
      }
      return; // Exits early — cannot scan without permissions
    }

    // 3. Build and wire up a fresh service.
    _service = P2pService(userName: AppSettings.instance.displayName); // Creates a new P2P service using the user's display name from settings

    _devSub = _service!.devicesStream.listen((devices) { // Subscribes to the stream of discovered nearby devices
      if (mounted) setState(() { _devices..clear()..addAll(devices); }); // Replaces the device list with the latest snapshot and rebuilds the UI
    });

    _msgSub = _service!.messagesStream.listen((msg) { // Subscribes to the stream of incoming P2P messages
      if (!mounted) return; // Ignore the message if the widget is no longer in the tree
      setState(() { // Updates state whenever a new message arrives
        if (msg.peerId.isEmpty) { // If the peerId is empty, this is a broadcast SOS message (not from a specific peer)
          _broadcasts.add(msg); // Adds the SOS broadcast to the broadcasts list
        } else { // Otherwise it's a direct message from a specific peer
          _conversations.putIfAbsent(msg.peerId, () => []).add(msg); // Appends the message to that peer's conversation history, creating it if needed
          if (!msg.isMine && msg.peerId != _openChatId) { // If it's from someone else and their chat isn't currently open
            _unread[msg.peerId] = (_unread[msg.peerId] ?? 0) + 1; // Increments the unread count for that peer
          }
        }
      });
    });

    _logSub = _service!.logStream.listen((entry) { // Subscribes to the debug log stream from the service
      if (mounted) setState(() => _logs.add(entry)); // Adds each new log entry to the list and rebuilds the UI
    });

    await _service!.start(); // Actually starts the Wi-Fi Direct scanning and connection logic
    if (mounted) setState(() { _started = true; _starting = false; }); // Marks the service as fully started and stops the loading indicator
  }

  Future<(List<String>, bool)> _requestPermissions() async { // Requests runtime permissions and returns which were denied and whether any are permanent
    // nearby_service (Wi-Fi Direct) only needs ACCESS_FINE_LOCATION here.
    // NEARBY_WIFI_DEVICES (Android 13+) is requested by the plugin itself
    // via _nearby.android!.requestPermissions() — requesting it through
    // permission_handler on API < 33 returns 'denied' instantly and causes
    // an unbreakable retry loop.
    final statuses = await [Permission.locationWhenInUse].request(); // Shows the "allow location while using the app" permission dialog to the user

    final denied = statuses.entries // Goes through each permission that was requested
        .where((e) => e.value.isDenied || e.value.isPermanentlyDenied) // Keeps only the ones that were denied or permanently blocked
        .map((_) => 'Location') // Maps each denied permission to a human-readable label
        .toList(); // Converts the result to a plain list
    final permanent =
        statuses.entries.any((e) => e.value.isPermanentlyDenied); // True if at least one permission was permanently denied
    return (denied, permanent); // Returns the list of denied permission names and the permanent-denial flag
  }

  // ── SOS broadcast ──────────────────────────────────────────────────────────

  Future<void> _broadcastSos() async { // Sends an SOS broadcast to all connected peers, including the user's medical info and GPS location
    if (_service == null) return; // Does nothing if the P2P service hasn't started yet

    String? locationLabel; // Will hold a "lat, lon" string if GPS is available; stays null if not
    try {
      final perm = await Geolocator.checkPermission(); // Checks the current location permission status without prompting the user
      if (perm == LocationPermission.whileInUse || // If permission is "while in use" OR "always"
          perm == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition() // Gets the device's current GPS coordinates
            .timeout(const Duration(seconds: 3)); // Gives up after 3 seconds if GPS is slow
        locationLabel = '${pos.latitude.toStringAsFixed(5)}, ' // Formats the latitude to 5 decimal places
            '${pos.longitude.toStringAsFixed(5)}'; // Formats the longitude to 5 decimal places and appends it
      }
    } catch (_) {} // Silently ignores GPS failures so the SOS still sends without location

    final profile = OfflineSeedData.medicalProfile; // Loads the user's offline medical profile (blood type, allergies, etc.)
    final sosText = [ // Builds a multi-line SOS message from the medical profile fields
      if (profile.bloodType.isNotEmpty) 'Blood type: ${profile.bloodType}', // Adds blood type line only if it has a value
      if (profile.allergies.isNotEmpty)
        'Allergies: ${profile.allergies.join(', ')}', // Adds allergies as a comma-separated list only if not empty
      if (profile.medications.isNotEmpty)
        'Medications: ${profile.medications.join(', ')}', // Adds medications as a comma-separated list only if not empty
      if (profile.emergencyNotes.isNotEmpty) 'Notes: ${profile.emergencyNotes}', // Adds any free-text emergency notes only if not empty
    ].join('\n'); // Joins all the lines together with line breaks

    await _service!.broadcastSos(sosText: sosText, locationLabel: locationLabel); // Sends the SOS message text and location (if available) to all connected peers
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _openChat(P2pDevice device) { // Opens the chat screen for the given peer device
    setState(() { // Updates state before navigating
      _unread.remove(device.id); // Clears the unread badge for this peer since the user is opening their chat
      _openChatId = device.id; // Records which peer's chat is open so new messages from them won't increment the unread count
    });
    Navigator.push( // Navigates to the chat screen, pushing it on top of the current screen
      context,
      MaterialPageRoute( // Uses a standard page route with a slide-in animation
        builder: (_) => _ChatScreen( // Builds the chat screen widget
          service: _service!, // Passes the running P2P service so the chat can send/receive messages
          device: device, // Passes the peer device info (name, ID, etc.)
          isDark: AppSettings.instance.lowBattery, // Passes the dark-mode flag from settings
          initialMessages: List.of(_conversations[device.id] ?? []), // Passes a copy of the existing conversation history for this peer
        ),
      ),
    ).then((_) { // Called when the user navigates back from the chat screen
      if (mounted) setState(() => _openChatId = null); // Clears the open chat ID so unread counting resumes for this peer
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) { // Describes the full UI for this screen; called every time setState is called
    final isDark = AppSettings.instance.lowBattery; // Reads whether the user has enabled low-battery (dark/AMOLED) mode
    final bg = isDark ? Colors.black : const Color(0xFFF4F7FA); // Chooses a black or soft-grey background depending on the mode
    final barBg = isDark ? TogetherTheme.amoledSurface : Colors.white; // Chooses the app bar background color for dark or light mode
    final titleColor =
        isDark ? TogetherTheme.amoledTextPrimary : TogetherTheme.deepOcean; // Chooses the app bar title color for dark or light mode

    return Scaffold( // The main screen layout widget — provides background, app bar, and body slots
      backgroundColor: bg, // Sets the screen background color
      appBar: AppBar( // The top navigation bar
        backgroundColor: barBg, // Sets the app bar's background color
        foregroundColor: titleColor, // Sets the default color for icons and text in the app bar
        elevation: 0, // Removes the shadow below the app bar for a flat look
        title: Column( // The title area contains two lines of text stacked vertically
          crossAxisAlignment: CrossAxisAlignment.start, // Aligns both text lines to the left
          mainAxisSize: MainAxisSize.min, // The column only takes as much height as its children need
          children: [
            Text(
              'Emergency Comms', // The main title of the screen
              style: TextStyle(
                fontSize: 18, // Sets the font size to 18 logical pixels
                fontWeight: FontWeight.w700, // Bold weight for the title
                color: titleColor, // Uses the chosen title color (dark or light mode)
                fontFamily: 'RobotoSlab', // Uses the serif RobotoSlab font for headings
              ),
            ),
            Text(
              _statusLabel, // Shows a dynamic status string (e.g., "Scanning…", "Connected to 2 devices")
              style: TextStyle(
                fontSize: 12, // Smaller font for the subtitle
                color: isDark // Picks a dimmer secondary color for the subtitle
                    ? TogetherTheme.amoledTextSecondary
                    : TogetherTheme.ink,
              ),
            ),
          ],
        ),
        actions: [ // Widgets placed on the right side of the app bar
          if (_started) // Only shows the scan dot if the service is running
            Padding(
              padding: const EdgeInsets.only(right: 12), // Adds 12px of space to the right of the dot
              child: _ScanDot(isDark: isDark), // The animated green blinking dot that indicates active scanning
            ),
        ],
      ),
      body: kIsWeb // Chooses the body based on whether the app is running on web
          ? _UnsupportedCard(isDark: isDark) // Shows a "not available on web" message when running in a browser
          : _body(isDark), // Shows the actual P2P UI on mobile/desktop
    );
  }

  String get _statusLabel { // A computed property that returns the right status string for the app bar subtitle
    if (kIsWeb) return 'Not available on web'; // Web doesn't support Wi-Fi Direct
    if (_starting) return 'Starting…'; // Service is still initializing
    if (!_started) return 'Offline · tap Start to scan'; // Service hasn't started (waiting for user action or permission)
    final connected = _devices.where((d) => d.isConnected).length; // Counts how many devices are fully connected
    final found = _devices.where((d) => !d.isConnected).length; // Counts how many devices are discovered but not yet connected
    if (connected > 0) { // If at least one device is connected
      return 'Connected to $connected device${connected > 1 ? 's' : ''}'; // Returns a singular or plural connected-device message
    }
    if (found > 0) return 'Found $found nearby device${found > 1 ? 's' : ''}'; // At least one device is discovered but not connected
    return 'Scanning for nearby Together users…'; // No devices found yet
  }

  Widget _body(bool isDark) { // Builds the main scrollable content area for mobile/desktop
    final connected = _devices.where((d) => d.isConnected).toList(); // Filters the device list to only fully connected devices
    final discovered = _devices.where((d) => !d.isConnected).toList(); // Filters the device list to devices found but not yet connected

    return Column( // A vertical column that stacks banners on top and the scrollable list below
      children: [
        // ── Banners ──────────────────────────────────────────────────────────
        if (_locationOff) // Shows a banner if location services are off
          _ErrorBanner(
            message: 'Location is off. Wi-Fi Direct needs it to scan for peers.',
            isDark: isDark,
            onAction: () async => Geolocator.openLocationSettings(), // Button opens the device's location settings
            actionLabel: 'Open Location', // Text on the action button
          ),
        if (_permissionError != null) // Shows a banner if a permission was denied
          _ErrorBanner(
            message: _permissionError!, // Shows the specific error message describing what was denied
            isDark: isDark,
            onAction:
                _permPermanentlyDenied ? () => openAppSettings() : _start, // Opens app settings if permanently denied, otherwise retries
            actionLabel: _permPermanentlyDenied ? 'Open Settings' : 'Retry', // Button label depends on whether the denial is permanent
          ),
        if (_service?.needsWifi == true) // Shows a banner if the P2P service detected that Wi-Fi is off
          _ErrorBanner(
            message: 'Wi-Fi is off — enable it to connect to nearby devices.',
            isDark: isDark,
            onAction: () => _service?.openServicesSettings(), // Button opens Wi-Fi/network settings
            actionLabel: 'Enable Wi-Fi', // Text on the action button
          ),

        // ── Main content ──────────────────────────────────────────────────
        Expanded( // Takes up all remaining vertical space below the banners
          child: !_started // If the service hasn't started, show the start prompt; otherwise show the device/chat list
              ? _StartPrompt(
                  isDark: isDark,
                  starting: _starting, // Passes whether the start is in progress (shows spinner)
                  onStart: _start, // The function to call when the user taps "Start scanning"
                )
              : ListView( // A scrollable list of all the content sections
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), // Padding around the list content
                  children: [
                    // SOS broadcasts received
                    if (_broadcasts.isNotEmpty) ...[ // Shows this section only if there are any broadcast SOS messages
                      _SectionLabel('SOS Broadcasts', isDark: isDark), // Section header label
                      const SizedBox(height: 8), // Vertical spacing between the label and the messages
                      ..._broadcasts.reversed.take(5).map( // Shows the 5 most recent broadcasts, newest first
                            (m) => _MessageBubble(msg: m, isDark: isDark), // Renders each SOS broadcast as a message bubble
                          ),
                      const SizedBox(height: 16), // Spacing after this section
                    ],

                    // Nearby users not yet connected
                    if (discovered.isNotEmpty) ...[ // Shows this section only if there are discovered-but-not-connected devices
                      _SectionLabel('Nearby — tap to connect', isDark: isDark), // Section header label
                      const SizedBox(height: 8), // Spacing below the label
                      ...discovered.map( // Renders a card for each discovered device
                        (d) => _DeviceCard(
                          device: d, // The discovered device data
                          isDark: isDark,
                          onConnect: () => _service!.connect(d.id), // Tapping "Connect" tells the service to connect to this device
                        ),
                      ),
                      const SizedBox(height: 16), // Spacing after this section
                    ],

                    // Conversations with connected peers
                    if (connected.isNotEmpty) ...[ // Shows this section only if at least one device is connected
                      _SectionLabel('Conversations', isDark: isDark), // Section header label
                      const SizedBox(height: 8), // Spacing below the label
                      ...connected.map((d) { // Renders a conversation tile for each connected device
                        final msgs = _conversations[d.id]; // Gets the message history for this peer
                        final last =
                            (msgs != null && msgs.isNotEmpty) ? msgs.last : null; // Gets the most recent message, or null if no messages yet
                        return _ConversationTile(
                          device: d, // The connected device data
                          lastMessage: last, // The last message (shown as a preview)
                          unread: _unread[d.id] ?? 0, // The number of unread messages from this peer (0 if none)
                          isDark: isDark,
                          onTap: () => _openChat(d), // Opens the chat screen for this peer when tapped
                        );
                      }),
                      const SizedBox(height: 16), // Spacing after this section
                    ],

                    // Empty state
                    if (connected.isEmpty && discovered.isEmpty) // Shows an empty state message if no devices are found or connected
                      _EmptyState(isDark: isDark),

                    // Radar
                    _RadarView(devices: _devices, isDark: isDark), // Animated radar visualization showing all detected devices around the user
                    const SizedBox(height: 8), // Spacing below the radar

                    // Debug log
                    _DebugPanel(
                      logs: _logs, // The list of debug log strings to display
                      expanded: _logsExpanded, // Whether the panel is currently expanded
                      isDark: isDark,
                      onToggle: () => // Callback to toggle the panel open/closed
                          setState(() => _logsExpanded = !_logsExpanded),
                    ),
                    const SizedBox(height: 16), // Bottom spacing at the end of the list
                  ],
                ),
        ),

        // ── SOS broadcast button ──────────────────────────────────────────
        if (_started) // Only shows the SOS button once the service is running
          _SosBroadcastButton(
            enabled: connected.isNotEmpty, // The button is only active if at least one peer is connected
            onTap: _broadcastSos, // Calls the SOS broadcast function when tapped
          ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Chat screen — per-peer conversation
// ═════════════════════════════════════════════════════════════════════════════

class _ChatScreen extends StatefulWidget { // The private chat screen widget for a one-on-one conversation with a peer
  const _ChatScreen({
    required this.service, // The running P2P service — required to send messages
    required this.device, // The peer device this chat belongs to
    required this.isDark, // Whether dark mode is active
    required this.initialMessages, // The message history to show when the chat opens
  });

  final P2pService service; // Stores the P2P service reference
  final P2pDevice device; // Stores the peer device data (name, ID, connection status)
  final bool isDark; // Stores the dark mode flag
  final List<P2pMessage> initialMessages; // Stores the pre-existing messages to display on open

  @override
  State<_ChatScreen> createState() => _ChatScreenState(); // Points to the state class that manages this widget's data
}

class _ChatScreenState extends State<_ChatScreen> { // Manages the mutable state of the chat screen
  final _inputCtrl = TextEditingController(); // Controls the text input field — reads its value and clears it after sending
  final _scrollCtrl = ScrollController(); // Controls the message list's scroll position — used to auto-scroll to the latest message
  late final List<P2pMessage> _messages = List.of(widget.initialMessages); // Starts with a copy of the initial messages; 'late final' means it's set once on first access
  StreamSubscription<P2pMessage>? _sub; // Subscription to the message stream so new messages appear in real time

  @override
  void initState() { // Called once when the chat screen is first displayed
    super.initState(); // Always call super first
    _sub = widget.service.messagesStream.listen((msg) { // Subscribes to all incoming messages from the service
      if (msg.peerId == widget.device.id && mounted) { // Only processes messages from THIS peer; ignores messages from others
        setState(() => _messages.add(msg)); // Adds the new message to the list and rebuilds the UI
        _scrollToBottom(); // Scrolls the list down to show the new message
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom()); // After the first frame draws, scroll to the bottom to show the newest message
  }

  @override
  void dispose() { // Cleans up resources when the chat screen is closed
    _sub?.cancel(); // Stops listening to new messages
    _inputCtrl.dispose(); // Releases the text input controller's memory
    _scrollCtrl.dispose(); // Releases the scroll controller's memory
    super.dispose(); // Always call super last
  }

  Future<void> _send() async { // Reads the typed message, sends it, and clears the input field
    final text = _inputCtrl.text.trim(); // Gets the typed text and removes leading/trailing whitespace
    if (text.isEmpty) return; // Does nothing if the user typed only spaces or nothing
    _inputCtrl.clear(); // Clears the text input field immediately so it looks snappy
    await widget.service.sendMessageTo(widget.device.id, text); // Sends the message to the peer via the P2P service
    _scrollToBottom(); // Scrolls down to show the message that was just sent
  }

  void _scrollToBottom() { // Smoothly scrolls the message list to the very bottom
    WidgetsBinding.instance.addPostFrameCallback((_) { // Waits until after the next frame so the new message is laid out before scrolling
      if (_scrollCtrl.hasClients) { // Only scrolls if the scroll controller is attached to a scrollable widget
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent, // Scrolls to the very end of the list
          duration: const Duration(milliseconds: 260), // The scroll animation takes 260 milliseconds
          curve: Curves.easeOut, // Uses a smooth ease-out curve (starts fast, slows at the end)
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) { // Builds the chat screen UI
    final isDark = widget.isDark; // Reads the dark mode flag from the parent widget
    final bg = isDark ? Colors.black : const Color(0xFFF4F7FA); // Screen background: black in dark mode, light grey otherwise
    final barBg = isDark ? TogetherTheme.amoledSurface : Colors.white; // App bar background
    final titleColor =
        isDark ? TogetherTheme.amoledTextPrimary : TogetherTheme.deepOcean; // App bar title text color
    final subtitleColor =
        isDark ? TogetherTheme.amoledTextSecondary : TogetherTheme.ink; // Subtitle and secondary text color
    final inputBorder =
        isDark ? TogetherTheme.amoledBorder : const Color(0xFFD3DCE4); // Border color for the input area separator

    return Scaffold( // The root layout for the chat screen
      backgroundColor: bg, // Sets the background color
      appBar: AppBar( // The top bar showing the peer's name and connection info
        backgroundColor: barBg, // App bar background color
        foregroundColor: titleColor, // Color for the back button and other icons
        elevation: 0, // No shadow under the app bar
        titleSpacing: 0, // Removes the default left spacing before the title so the avatar can sit flush
        title: Row( // The title is a row: avatar icon on the left, name and subtitle on the right
          children: [
            Container( // The circular-ish avatar background for the peer icon
              width: 36, // Avatar width
              height: 36, // Avatar height
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF052E16) : _kGreenLight, // Dark green in dark mode, light green in light mode
                borderRadius: BorderRadius.circular(10), // Slightly rounded corners
              ),
              child: const Icon(Icons.person_rounded, size: 18, color: _kGreen), // Person icon inside the avatar container
            ),
            const SizedBox(width: 10), // Horizontal gap between the avatar and the text
            Column( // Stacks the peer's name on top and the connection info below
              crossAxisAlignment: CrossAxisAlignment.start, // Left-aligns both text lines
              mainAxisSize: MainAxisSize.min, // Takes only as much height as needed
              children: [
                Text(
                  widget.device.name, // The peer's display name
                  style: TextStyle(
                    fontSize: 16, // Font size for the name
                    fontWeight: FontWeight.w700, // Bold
                    color: titleColor, // Uses the chosen title color
                    fontFamily: 'RobotoSlab', // Serif font for the name
                  ),
                ),
                Text(
                  'Connected via Wi-Fi Direct', // Static subtitle showing the connection type
                  style: TextStyle(fontSize: 11, color: subtitleColor), // Small, secondary-colored text
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column( // The body is a column: messages fill the top, input bar sits at the bottom
        children: [
          // ── Messages ───────────────────────────────────────────────────────
          Expanded( // The message list expands to fill all space above the input bar
            child: _messages.isEmpty // If there are no messages yet, show a placeholder
                ? Center(
                    child: Text(
                      'No messages yet.\nSay hello!', // Friendly empty-state message
                      textAlign: TextAlign.center, // Centers the text horizontally
                      style: TextStyle(
                        fontSize: 14, // Font size
                        height: 1.6, // Line height for readability
                        color: subtitleColor.withValues(alpha: 0.5), // Semi-transparent secondary color
                      ),
                    ),
                  )
                : ListView.builder( // Builds the list of message bubbles efficiently
                    controller: _scrollCtrl, // Attaches the scroll controller so we can auto-scroll
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), // Padding around the message list
                    itemCount: _messages.length, // How many messages to render
                    itemBuilder: (_, i) =>
                        _MessageBubble(msg: _messages[i], isDark: isDark), // Renders each message as a bubble
                  ),
          ),

          // ── Input bar ──────────────────────────────────────────────────────
          Container( // The container that holds the text field and send button
            decoration: BoxDecoration(
              color: barBg, // Background matches the app bar color
              border: Border(top: BorderSide(color: inputBorder)), // A thin top border separates the input from the messages
            ),
            padding: EdgeInsets.fromLTRB(
              12, 8, 12,
              8 + MediaQuery.of(context).viewInsets.bottom, // Adds extra bottom padding equal to the keyboard height so the input is never hidden
            ),
            child: SafeArea( // Respects the device's safe area (e.g., home indicator on iPhones) at the bottom
              top: false, // Only applies safe area to the bottom, not the top
              child: Row( // The row contains the text field and the send button side by side
                crossAxisAlignment: CrossAxisAlignment.end, // Aligns the send button to the bottom of the row
                children: [
                  Expanded( // The text field stretches to fill all available width
                    child: TextField(
                      controller: _inputCtrl, // Links the controller so we can read and clear the typed text
                      maxLines: 4, // Allows up to 4 lines before scrolling within the field
                      minLines: 1, // Starts at a single line and grows as the user types
                      textInputAction: TextInputAction.send, // Shows a "Send" button on the keyboard's action key
                      style: TextStyle(color: titleColor), // Sets the typed text color
                      decoration: InputDecoration(
                        hintText: 'Message ${widget.device.name}…', // Placeholder text showing who you're messaging
                        hintStyle: TextStyle(
                            color: subtitleColor.withValues(alpha: 0.6)), // Dimmed hint text
                        filled: true, // Fills the text field with a background color
                        fillColor: isDark // Background of the text field
                            ? TogetherTheme.amoledSurfaceElevated
                            : const Color(0xFFEDF1F5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24), // Pill-shaped rounded corners
                          borderSide: BorderSide.none, // No visible border line — the fill color defines the shape
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10), // Inner padding so text doesn't touch the edges
                      ),
                      onSubmitted: (_) => _send(), // Sends the message when the keyboard's "Send" action key is tapped
                    ),
                  ),
                  const SizedBox(width: 8), // Gap between the text field and the send button
                  GestureDetector( // Makes the send button circle tappable
                    onTap: _send, // Calls the send function when tapped
                    child: Container( // The circular green send button
                      width: 44, // Button width
                      height: 44, // Button height
                      decoration: const BoxDecoration(
                        color: _kGreen, // Green background color
                        shape: BoxShape.circle, // Makes it a perfect circle
                      ),
                      child: const Icon(Icons.send_rounded,
                          size: 18, color: Colors.white), // White send arrow icon inside the circle
                    ),
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

// ═════════════════════════════════════════════════════════════════════════════
// Sub-widgets
// ═════════════════════════════════════════════════════════════════════════════

class _ScanDot extends StatefulWidget { // A small animated dot shown in the app bar to indicate active scanning
  const _ScanDot({required this.isDark}); // Constructor — requires knowing the current color mode
  final bool isDark; // Stores the dark mode flag

  @override
  State<_ScanDot> createState() => _ScanDotState(); // Points to the state class that drives the animation
}

class _ScanDotState extends State<_ScanDot>
    with SingleTickerProviderStateMixin { // SingleTickerProviderStateMixin provides the vsync needed by the AnimationController
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 1)) // Creates an animation that lasts 1 second
        ..repeat(reverse: true); // Makes it loop: fades in, fades out, fades in, fades out...
  late final Animation<double> _opacity =
      Tween(begin: 0.3, end: 1.0).animate(_ctrl); // An animation that interpolates opacity between 30% and 100%

  @override
  void dispose() { // Cleans up the animation controller to avoid memory leaks
    _ctrl.dispose(); // Stops and frees the animation controller
    super.dispose(); // Always call super last
  }

  @override
  Widget build(BuildContext context) { // Builds the animated blinking dot
    return FadeTransition( // Automatically changes the widget's opacity based on the animation value
      opacity: _opacity, // The opacity animation (0.3 to 1.0, looping)
      child: Container( // A small circle that pulses in opacity
        width: 8, // Dot width in logical pixels
        height: 8, // Dot height
        decoration:
            const BoxDecoration(color: _kGreen, shape: BoxShape.circle), // Solid green circle shape
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget { // A simple uppercased section header label used above each group of items
  const _SectionLabel(this.text, {required this.isDark}); // Constructor takes the label text and the dark mode flag
  final String text; // The label text (e.g., "Conversations")
  final bool isDark; // Whether dark mode is on

  @override
  Widget build(BuildContext context) { // Builds the section label text widget
    return Text(
      text.toUpperCase(), // Converts the text to uppercase for a clean section-header style
      style: TextStyle(
        fontSize: 11, // Small font size for section headers
        fontWeight: FontWeight.w700, // Bold
        letterSpacing: 0.8, // Slightly wider letter spacing for a label look
        color: isDark ? TogetherTheme.amoledTextSecondary : TogetherTheme.ink, // Secondary color in dark mode, dark ink in light mode
      ),
    );
  }
}

// ── Conversation tile (connected peer) ────────────────────────────────────────

class _ConversationTile extends StatelessWidget { // A list tile showing a connected peer's avatar, name, last message preview, and unread count
  const _ConversationTile({
    required this.device, // The connected peer's device info
    required this.lastMessage, // The most recent message in the conversation (null if none yet)
    required this.unread, // How many unread messages from this peer
    required this.isDark, // Whether dark mode is active
    required this.onTap, // Callback invoked when the user taps this tile to open the chat
  });

  final P2pDevice device; // Stores the peer device
  final P2pMessage? lastMessage; // Stores the last message (nullable)
  final int unread; // Stores the unread count
  final bool isDark; // Stores the dark mode flag
  final VoidCallback onTap; // Stores the tap callback

  @override
  Widget build(BuildContext context) { // Builds the conversation tile
    final bg = isDark ? TogetherTheme.amoledSurface : Colors.white; // Card background color
    final border = isDark ? TogetherTheme.amoledBorder : const Color(0xFFDCE4EA); // Card border color
    final nameColor =
        isDark ? TogetherTheme.amoledTextPrimary : TogetherTheme.deepOcean; // Peer name text color
    final subColor =
        isDark ? TogetherTheme.amoledTextSecondary : TogetherTheme.ink; // Secondary/preview text color

    return GestureDetector( // Wraps the entire tile in a tap detector
      onTap: onTap, // Opens the chat screen when tapped
      child: Container( // The card container with rounded corners and a border
        margin: const EdgeInsets.only(bottom: 8), // Space below each tile in the list
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), // Inner padding
        decoration: BoxDecoration(
          color: bg, // Card background
          borderRadius: BorderRadius.circular(14), // Rounded corners
          border: Border.all(color: border), // Thin border around the card
        ),
        child: Row( // Horizontal layout: avatar | name+preview | badge or chevron
          children: [
            // Avatar
            Container( // The peer's avatar — a rounded square with a person icon
              width: 44, // Avatar size
              height: 44, // Avatar size
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF052E16) : _kGreenLight, // Avatar background color
                borderRadius: BorderRadius.circular(12), // Rounded corners for the avatar
              ),
              child:
                  const Icon(Icons.person_rounded, size: 22, color: _kGreen), // Person icon inside the avatar
            ),
            const SizedBox(width: 12), // Gap between avatar and text
            // Name + preview
            Expanded( // The text column expands to fill the remaining space
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, // Left-aligns the name and preview text
                children: [
                  Text(
                    device.name, // The peer's name
                    style: TextStyle(
                      fontSize: 15, // Font size for the name
                      fontWeight: FontWeight.w600, // Semi-bold
                      color: nameColor, // Name text color
                    ),
                  ),
                  if (lastMessage != null) ...[ // If there's at least one message, show a preview
                    const SizedBox(height: 2), // Tiny gap between name and preview
                    Text(
                      '${lastMessage!.isMine ? 'You: ' : ''}${lastMessage!.text}', // Prefixes "You: " for sent messages, plain text for received
                      maxLines: 1, // Only show one line of preview
                      overflow: TextOverflow.ellipsis, // Adds "…" if the text is too long
                      style: TextStyle(
                        fontSize: 13, // Smaller font for the preview
                        color: unread > 0 // Bolder and darker if there are unread messages
                            ? nameColor
                            : subColor.withValues(alpha: 0.8),
                        fontWeight: unread > 0 // Bold if unread, normal weight otherwise
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ] else
                    Text(
                      'Connected — tap to chat', // Shown when there are no messages yet
                      style: TextStyle(
                        fontSize: 13, // Font size for the placeholder
                        color: subColor.withValues(alpha: 0.6), // Dimmed secondary color
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8), // Gap before the badge or chevron
            // Unread badge or chevron
            if (unread > 0) // Shows a green badge with the unread count if there are unread messages
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3), // Inner padding for the badge pill
                decoration: BoxDecoration(
                  color: _kGreen, // Green badge background
                  borderRadius: BorderRadius.circular(12), // Pill-shaped badge
                ),
                child: Text(
                  '$unread', // The number of unread messages
                  style: const TextStyle(
                    fontSize: 12, // Small font inside the badge
                    fontWeight: FontWeight.w700, // Bold count number
                    color: Colors.white, // White text on green background
                  ),
                ),
              )
            else // If no unread messages, show a right-pointing chevron instead
              Icon(
                Icons.chevron_right_rounded, // Right arrow icon indicating the tile is tappable
                size: 20, // Icon size
                color: subColor.withValues(alpha: 0.4), // Dimmed secondary color for the chevron
              ),
          ],
        ),
      ),
    );
  }
}

// ── Device card (discovered, not yet connected) ───────────────────────────────

class _DeviceCard extends StatelessWidget { // A card representing a nearby device that has been discovered but not yet connected
  const _DeviceCard({
    required this.device, // The discovered device's data
    required this.isDark, // Whether dark mode is active
    required this.onConnect, // Callback invoked when the user taps "Connect"
  });

  final P2pDevice device; // Stores the discovered device
  final bool isDark; // Stores the dark mode flag
  final VoidCallback onConnect; // Stores the connect callback

  @override
  Widget build(BuildContext context) { // Builds the device card
    final bg = isDark ? TogetherTheme.amoledSurface : Colors.white; // Card background color
    final border = isDark ? TogetherTheme.amoledBorder : const Color(0xFFDCE4EA); // Card border color
    final connecting = device.isConnecting; // True if a connection attempt to this device is currently in progress

    return Container( // The card container
      margin: const EdgeInsets.only(bottom: 8), // Space below each card
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), // Inner padding
      decoration: BoxDecoration(
        color: bg, // Card background
        borderRadius: BorderRadius.circular(14), // Rounded corners
        border: Border.all(color: border), // Thin border
      ),
      child: Row( // Horizontal layout: avatar | name (+connecting status) | connect button or spinner
        children: [
          Container( // Avatar for the discovered device
            width: 36, // Avatar width
            height: 36, // Avatar height
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A2A3A) : _kGreenLight, // Avatar background color
              borderRadius: BorderRadius.circular(10), // Slightly rounded corners
            ),
            child: const Icon(Icons.person_rounded, size: 18, color: _kGreen), // Person icon
          ),
          const SizedBox(width: 12), // Gap between avatar and name
          Expanded( // The name column expands to fill available space
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, // Left-aligns the text
              children: [
                Text(
                  device.name, // The discovered device's name
                  style: TextStyle(
                    fontSize: 15, // Font size for the device name
                    fontWeight: FontWeight.w600, // Semi-bold
                    color: isDark // Name color depends on dark mode
                        ? TogetherTheme.amoledTextPrimary
                        : TogetherTheme.deepOcean,
                  ),
                ),
                if (connecting) // Shows "Connecting…" below the name while a connection is in progress
                  Text(
                    'Connecting…',
                    style: TextStyle(
                      fontSize: 12, // Smaller font for the status text
                      color: isDark // Secondary color for dark or light mode
                          ? TogetherTheme.amoledTextSecondary
                          : TogetherTheme.ink,
                    ),
                  ),
              ],
            ),
          ),
          if (connecting) // If connecting, show a circular loading spinner instead of the button
            const SizedBox(
              width: 20, // Spinner size
              height: 20, // Spinner size
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: _kGreen), // Thin green spinner
            )
          else // If not connecting, show the "Connect" text button
            TextButton(
              onPressed: onConnect, // Initiates connection when tapped
              style: TextButton.styleFrom(
                foregroundColor: _kGreen, // Green text for the button
                textStyle: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13), // Bold button text
              ),
              child: const Text('Connect'), // Button label
            ),
        ],
      ),
    );
  }
}

// ── Message bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget { // A single chat message bubble — styled differently for sent, received, and SOS messages
  const _MessageBubble({required this.msg, required this.isDark}); // Constructor takes the message and dark mode flag
  final P2pMessage msg; // The message data (text, sender, time, whether it's SOS, whether it's mine)
  final bool isDark; // Whether dark mode is active

  @override
  Widget build(BuildContext context) { // Builds the message bubble
    final isSos = msg.isSos; // True if this is a broadcast SOS message
    final isMe = msg.isMine; // True if I sent this message

    Color bg; // The bubble background color, determined below
    Color textColor; // The text color inside the bubble, determined below
    if (isSos) { // SOS messages get a red background
      bg = isDark ? _kRedDark : _kRedLight; // Dark red in dark mode, light red in light mode
      textColor = isDark ? const Color(0xFFFFCDD2) : _kRed; // Light pink in dark mode, red in light mode
    } else if (isMe) { // My own messages get a green background (like iMessage style)
      bg = _kGreen; // Solid green bubble
      textColor = Colors.white; // White text on green
    } else { // Received messages from others get a neutral card background
      bg = isDark ? TogetherTheme.amoledSurface : Colors.white; // Dark card or white
      textColor = isDark // Dark-mode or light-mode text color
          ? TogetherTheme.amoledTextPrimary
          : TogetherTheme.deepOcean;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10), // Space below each bubble
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start, // My messages are right-aligned; others are left-aligned
        children: [
          if (!isMe) // Only shows the sender's name above received messages (not my own)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 3), // Small offset from the bubble
              child: Text(
                msg.senderName, // The sender's display name
                style: TextStyle(
                  fontSize: 11, // Small font for the sender name
                  fontWeight: FontWeight.w600, // Semi-bold
                  color: isDark // Secondary color in dark/light mode
                      ? TogetherTheme.amoledTextSecondary
                      : TogetherTheme.ink,
                ),
              ),
            ),
          Container( // The bubble itself
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75, // The bubble can be at most 75% of the screen width
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10), // Inner padding for the text inside the bubble
            decoration: BoxDecoration(
              color: bg, // The background color chosen above
              borderRadius: BorderRadius.only( // Creates a "tail" effect by making one corner sharper
                topLeft: const Radius.circular(18), // Top-left is always rounded
                topRight: const Radius.circular(18), // Top-right is always rounded
                bottomLeft: Radius.circular(isMe ? 18 : 4), // Bottom-left: sharp if it's my message, rounded if received
                bottomRight: Radius.circular(isMe ? 4 : 18), // Bottom-right: sharp if it's my message, rounded if received (creates the "tail")
              ),
              border: (!isMe && !isSos) // Adds a border only to received non-SOS messages (sent and SOS have colored backgrounds)
                  ? Border.all(
                      color: isDark
                          ? TogetherTheme.amoledBorder
                          : const Color(0xFFDCE4EA)) // Border color for dark/light mode
                  : null, // No border for my messages or SOS messages
            ),
            child: Text(
              msg.text, // The actual message content
              style: TextStyle(fontSize: 14, height: 1.4, color: textColor), // Text style inside the bubble
            ),
          ),
          Padding(
            padding: EdgeInsets.only( // Small offset padding for the timestamp
                top: 3, left: isMe ? 0 : 4, right: isMe ? 4 : 0),
            child: Text(
              _formatTime(msg.time), // The formatted "HH:MM" timestamp for this message
              style: TextStyle(
                fontSize: 10, // Very small font for timestamps
                color: (isDark // Semi-transparent secondary color for the timestamp
                        ? TogetherTheme.amoledTextSecondary
                        : TogetherTheme.ink)
                    .withValues(alpha: 0.5), // 50% transparent so it's subtle
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime t) { // Formats a DateTime to a "HH:MM" string (e.g., "09:05")
    final h = t.hour.toString().padLeft(2, '0'); // Pads the hour with a leading zero if needed (e.g., 9 → "09")
    final m = t.minute.toString().padLeft(2, '0'); // Pads the minute with a leading zero if needed
    return '$h:$m'; // Returns the formatted time string
  }
}

// ── SOS broadcast button ──────────────────────────────────────────────────────

class _SosBroadcastButton extends StatelessWidget { // The large red "BROADCAST SOS" button at the bottom of the P2P screen
  const _SosBroadcastButton({required this.enabled, required this.onTap}); // Constructor takes an enabled flag and the tap callback
  final bool enabled; // True only when at least one peer is connected; false means the button is greyed out
  final VoidCallback onTap; // The function to call when the user taps the button

  @override
  Widget build(BuildContext context) { // Builds the SOS button
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10), // Horizontal and vertical padding around the button
      child: SizedBox(
        width: double.infinity, // Button stretches to fill the full screen width
        height: 52, // Fixed button height
        child: ElevatedButton.icon(
          onPressed: enabled ? onTap : null, // Null disables the button (Flutter automatically greys it out)
          icon: const Icon(Icons.crisis_alert_rounded), // Alert icon on the left of the button label
          label: Text(
            enabled
                ? 'BROADCAST SOS TO ALL' // Full active label when connected
                : 'BROADCAST SOS (connect first)', // Descriptive disabled label when not connected
            style:
                const TextStyle(fontWeight: FontWeight.w800, fontSize: 14), // Extra-bold text
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: enabled ? _kRed : const Color(0xFF9CA3AF), // Red when active, grey when disabled
            foregroundColor: Colors.white, // White text and icon
            disabledBackgroundColor: const Color(0xFF9CA3AF), // Grey background when disabled
            disabledForegroundColor: Colors.white70, // Slightly transparent white text when disabled
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)), // Rounded corners for the button
          ),
        ),
      ),
    );
  }
}

// ── Start prompt ──────────────────────────────────────────────────────────────

class _StartPrompt extends StatelessWidget { // The full-screen prompt shown before the P2P service is started
  const _StartPrompt({
    required this.isDark, // Whether dark mode is on
    required this.starting, // Whether the start sequence is currently in progress
    required this.onStart, // Callback for the "Start scanning" button
  });
  final bool isDark; // Stores the dark mode flag
  final bool starting; // Stores whether startup is in progress (shows a spinner)
  final VoidCallback onStart; // Stores the start callback

  @override
  Widget build(BuildContext context) { // Builds the start prompt UI
    return Center( // Centers the content vertically and horizontally
      child: Padding(
        padding: const EdgeInsets.all(32), // Generous padding around the content
        child: Column(
          mainAxisSize: MainAxisSize.min, // Column only takes as much height as its children
          children: [
            Container( // Circular icon container at the top of the prompt
              width: 80, // Container size
              height: 80, // Container size
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A0A0A) : _kRedLight, // Dark in dark mode, light red in light mode
                shape: BoxShape.circle, // Perfect circle shape
              ),
              child: const Icon(Icons.sensors_rounded, size: 40, color: _kRed), // Sensor/radar icon in red
            ),
            const SizedBox(height: 20), // Vertical spacing
            Text(
              'Emergency Comms', // Main heading of the prompt
              style: TextStyle(
                fontSize: 20, // Large font for the heading
                fontWeight: FontWeight.w800, // Extra bold
                fontFamily: 'RobotoSlab', // Serif font
                color: isDark // Heading color for dark/light mode
                    ? TogetherTheme.amoledTextPrimary
                    : TogetherTheme.deepOcean,
              ),
            ),
            const SizedBox(height: 10), // Spacing between heading and description
            Text(
              'Connect to nearby Together users via Wi-Fi Direct — '
              'no internet required. Send direct messages or broadcast your SOS card.',
              textAlign: TextAlign.center, // Centers the description text
              style: TextStyle(
                fontSize: 14, // Body text size
                height: 1.5, // Line height for readability
                color: isDark // Secondary text color
                    ? TogetherTheme.amoledTextSecondary
                    : TogetherTheme.ink,
              ),
            ),
            const SizedBox(height: 28), // Spacing before the button
            SizedBox(
              width: double.infinity, // Button fills the full width
              height: 52, // Fixed button height
              child: ElevatedButton.icon(
                onPressed: starting ? null : onStart, // Disabled while starting to prevent double-taps
                icon: starting // Shows a spinner while starting, otherwise the sensor icon
                    ? const SizedBox(
                        width: 18, // Spinner size
                        height: 18, // Spinner size
                        child: CircularProgressIndicator(
                          strokeWidth: 2, // Thin spinner stroke
                          color: Colors.white, // White spinner on the red button
                        ),
                      )
                    : const Icon(Icons.sensors_rounded), // Sensor icon when not loading
                label: Text(starting ? 'Starting…' : 'Start scanning'), // Button label changes based on state
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kRed, // Red button background
                  foregroundColor: Colors.white, // White text and icon
                  textStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700), // Bold button text
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)), // Rounded corners
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget { // The empty state widget shown when the service is running but no devices are found
  const _EmptyState({required this.isDark}); // Constructor takes the dark mode flag
  final bool isDark; // Stores the dark mode flag

  @override
  Widget build(BuildContext context) { // Builds the empty state UI
    final color = (isDark // Chooses a very transparent secondary color for the icon and text
            ? TogetherTheme.amoledTextSecondary
            : TogetherTheme.ink)
        .withValues(alpha: 0.35); // 35% opacity makes it look subtle and non-intrusive
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32), // Vertical padding to give the empty state breathing room
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min, // Column only takes as much space as needed
          children: [
            Icon(Icons.person_search_rounded, size: 48, color: color), // Large "searching for person" icon
            const SizedBox(height: 12), // Gap between icon and text
            Text(
              'Searching for nearby Together users…', // Descriptive empty state message
              style: TextStyle(fontSize: 14, color: color), // Same subtle color as the icon
            ),
          ],
        ),
      ),
    );
  }
}

// ── Radar view ────────────────────────────────────────────────────────────────

class _RadarView extends StatefulWidget { // A widget that shows an animated radar sweep with device blips
  const _RadarView({required this.devices, required this.isDark}); // Constructor takes the device list and dark mode flag
  final List<P2pDevice> devices; // The list of all nearby devices to plot on the radar
  final bool isDark; // Whether dark mode is active

  @override
  State<_RadarView> createState() => _RadarViewState(); // Points to the state class that drives the animation
}

class _RadarViewState extends State<_RadarView>
    with SingleTickerProviderStateMixin { // Provides vsync for the AnimationController
  late final AnimationController _ctrl = AnimationController(
    vsync: this, // Uses this state object as the vsync source (synced with screen refresh)
    duration: const Duration(seconds: 2), // One full radar sweep takes 2 seconds
  )..repeat(); // Loops the animation forever

  @override
  void dispose() { // Cleans up the animation controller when the widget is removed
    _ctrl.dispose(); // Stops and frees the animation controller
    super.dispose(); // Always call super last
  }

  @override
  Widget build(BuildContext context) { // Builds the radar visualization
    return Center( // Centers the radar and its label
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _ctrl, // Rebuilds whenever the animation value changes (every frame)
            builder: (_, _) => CustomPaint( // CustomPaint lets us draw freely on a canvas
              size: const Size(220, 220), // The radar canvas is a 220x220 logical pixel square
              painter: _RadarPainter( // The custom painter that draws the rings, sweep, and device blips
                devices: widget.devices, // Passes the list of devices to paint as blips
                sweepAngle: _ctrl.value * 2 * 3.14159, // Converts the animation value (0.0–1.0) to a full 2π radian angle
                isDark: widget.isDark, // Passes the dark mode flag for color selection
              ),
            ),
          ),
          const SizedBox(height: 8), // Gap between the radar and the label below it
          Text(
            widget.devices.isEmpty // Shows different text depending on whether any devices are found
                ? 'Scanning for nearby Together users…' // No devices yet
                : '${widget.devices.length} device${widget.devices.length == 1 ? '' : 's'} detected', // Shows count, singular or plural
            style: TextStyle(
              fontSize: 13, // Font size for the radar label
              color: widget.isDark // Secondary text color
                  ? TogetherTheme.amoledTextSecondary
                  : TogetherTheme.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _RadarPainter extends CustomPainter { // Custom painter that draws the full radar: rings, sweep, center dot, and device blips
  _RadarPainter({
    required this.devices, // The devices to show as blips on the radar
    required this.sweepAngle, // The current angle of the rotating sweep line
    required this.isDark, // Whether dark mode is active (affects colors)
  });

  final List<P2pDevice> devices; // Stores the device list
  final double sweepAngle; // Stores the current sweep angle in radians
  final bool isDark; // Stores the dark mode flag

  @override
  void paint(Canvas canvas, Size size) { // The actual drawing code — called every animation frame
    final cx = size.width / 2; // X coordinate of the radar center
    final cy = size.height / 2; // Y coordinate of the radar center
    final maxR = cx - 4; // Maximum radius of the radar, with a small margin from the edge

    final ringPaint = Paint() // Paint used to draw the three concentric range rings
      ..style = PaintingStyle.stroke // Draw only the outline (not filled)
      ..strokeWidth = 1 // Thin ring lines
      ..color =
          (isDark ? Colors.tealAccent : _kGreen).withValues(alpha: 0.2); // Very transparent green rings

    for (final factor in [0.33, 0.66, 1.0]) { // Draws three rings at 33%, 66%, and 100% of the maximum radius
      canvas.drawCircle(Offset(cx, cy), maxR * factor, ringPaint); // Draws each ring centered on the radar center
    }

    final sweepPaint = Paint() // Paint for the radar sweep wedge
      ..shader = RadialGradient( // Uses a radial gradient so the sweep fades out from the center
        colors: [
          (isDark ? Colors.tealAccent : _kGreen).withValues(alpha: 0.6), // Bright near the center
          (isDark ? Colors.tealAccent : _kGreen).withValues(alpha: 0.0), // Fully transparent at the edge
        ],
      ).createShader(
          Rect.fromCircle(center: Offset(cx, cy), radius: maxR)) // Applies the gradient within the radar circle
      ..style = PaintingStyle.fill; // Fill the wedge shape

    final sweepPath = Path() // Defines the wedge path for the sweep
      ..moveTo(cx, cy) // Start at the center of the radar
      ..arcTo(
        Rect.fromCircle(center: Offset(cx, cy), radius: maxR), // The arc stays on the full radar circle
        sweepAngle - 0.6, // Start angle is 0.6 radians before the current sweep angle
        0.6, // Arc spans 0.6 radians (about 34 degrees) — the width of the sweep wedge
        false, // Don't move to the arc start — connect from the center
      )
      ..close(); // Close the path back to the center, completing the wedge triangle
    canvas.drawPath(sweepPath, sweepPaint); // Draws the sweep wedge on the canvas

    canvas.drawCircle(Offset(cx, cy), 6, Paint()..color = _kGreen); // Draws the solid green dot at the radar center representing "You"
    final tp = TextPainter( // A TextPainter for drawing "You" label text onto the canvas
      text: TextSpan(
        text: 'You', // The label text
        style: TextStyle(
          fontSize: 10, // Small font
          color: isDark ? Colors.white : _kGreen, // White in dark mode, green in light mode
          fontWeight: FontWeight.w700, // Bold
        ),
      ),
      textDirection: TextDirection.ltr, // Left-to-right text direction
    )..layout(); // Measures the text so we can center it
    tp.paint(canvas, Offset(cx - tp.width / 2, cy + 9)); // Draws "You" centered below the center dot

    if (devices.isEmpty) return; // No devices to plot — stop here
    final angleStep = (2 * 3.14159) / devices.length; // Divides the full circle equally among all devices
    for (int i = 0; i < devices.length; i++) { // Loops through each device to draw its blip
      final device = devices[i]; // Gets the current device
      final angle = angleStep * i - 3.14159 / 2; // Calculates the angle for this device, starting from the top (−π/2)
      final r = device.isConnected ? maxR * 0.45 : maxR * 0.78; // Connected devices are shown closer to the center; discovered ones are farther out
      final dx = cx + r * math.cos(angle); // X coordinate of the device blip using trigonometry
      final dy = cy + r * math.sin(angle); // Y coordinate of the device blip using trigonometry

      canvas.drawCircle( // Draws the device blip dot
        Offset(dx, dy), // Position of the blip
        device.isConnected ? 8 : 6, // Connected devices get a slightly larger dot
        Paint()
          ..color = device.isConnected // Green for connected, slightly transparent for discovered
              ? _kGreen
              : (isDark ? Colors.tealAccent : _kGreen)
                  .withValues(alpha: 0.7),
      );

      if (device.isConnected) { // Draws a line from the center to each connected device's blip
        canvas.drawLine(
          Offset(cx, cy), // Start at the radar center
          Offset(dx, dy), // End at the device blip
          Paint()
            ..color = _kGreen.withValues(alpha: 0.4) // Semi-transparent green line
            ..strokeWidth = 1, // Thin line
        );
      }

      final label = TextPainter( // Draws the device name below its blip
        text: TextSpan(
          text: device.name.length > 10 // Truncates long names to 9 characters + ellipsis
              ? '${device.name.substring(0, 9)}…'
              : device.name, // Uses the full name if it's 10 characters or fewer
          style: TextStyle(
            fontSize: 9, // Very small font for the radar labels
            color: isDark ? Colors.white70 : TogetherTheme.deepOcean, // Label color for dark/light mode
          ),
        ),
        textDirection: TextDirection.ltr, // Left-to-right text
      )..layout(); // Measures the text for centering
      label.paint(
        canvas,
        Offset(dx - label.width / 2, // Centers the label horizontally under the blip
            dy + (device.isConnected ? 11 : 9)), // Offsets the label below the blip (connected dots are bigger so more offset)
      );
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) => // Tells Flutter whether it needs to repaint the canvas
      old.sweepAngle != sweepAngle || old.devices.length != devices.length; // Repaints only when the sweep angle or device count changes
}

// ── Debug log panel ───────────────────────────────────────────────────────────

class _DebugPanel extends StatelessWidget { // A collapsible panel at the bottom of the screen showing raw debug log entries
  const _DebugPanel({
    required this.logs, // The list of log strings to display
    required this.expanded, // Whether the panel is currently open
    required this.isDark, // Whether dark mode is on
    required this.onToggle, // Callback to toggle the panel open/closed
  });

  final List<String> logs; // Stores the log list
  final bool expanded, isDark; // Stores the expanded and dark mode flags in one line
  final VoidCallback onToggle; // Stores the toggle callback

  @override
  Widget build(BuildContext context) { // Builds the debug panel
    final bg = isDark ? TogetherTheme.amoledSurface : Colors.white; // Panel background color
    final border = isDark ? TogetherTheme.amoledBorder : const Color(0xFFDCE4EA); // Panel border color
    final textColor =
        isDark ? TogetherTheme.amoledTextSecondary : TogetherTheme.ink; // Text color for the log entries

    return Container( // The outer container with rounded corners and a border
      decoration: BoxDecoration(
        color: bg, // Panel background
        borderRadius: BorderRadius.circular(12), // Rounded corners
        border: Border.all(color: border), // Thin border
      ),
      child: Column(
        children: [
          InkWell( // The tappable header row that expands or collapses the panel
            onTap: onToggle, // Toggles the expanded state when tapped
            borderRadius: BorderRadius.circular(12), // Ripple effect matches the panel's rounded corners
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10), // Inner padding for the header row
              child: Row(
                children: [
                  Icon(Icons.bug_report_rounded, size: 16, color: textColor), // Bug icon on the left
                  const SizedBox(width: 8), // Gap between icon and label
                  Text(
                    'Debug log (${logs.length})', // Label shows how many log entries exist
                    style: TextStyle(
                      fontSize: 13, // Font size
                      fontWeight: FontWeight.w600, // Semi-bold
                      color: textColor, // Text color
                    ),
                  ),
                  const Spacer(), // Pushes the expand/collapse icon to the right
                  Icon(
                    expanded // Shows an up arrow when expanded, down arrow when collapsed
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18, // Icon size
                    color: textColor, // Icon color
                  ),
                ],
              ),
            ),
          ),
          if (expanded) // Only shows the log list when the panel is expanded
            Container(
              height: 180, // Fixed height for the scrollable log area
              decoration:
                  BoxDecoration(border: Border(top: BorderSide(color: border))), // Thin line separating the header from the logs
              child: logs.isEmpty // Shows a placeholder if there are no logs yet
                  ? Center(
                      child: Text('No logs yet',
                          style: TextStyle(fontSize: 12, color: textColor)),
                    )
                  : ListView.builder( // Efficiently builds the log entry list
                      padding: const EdgeInsets.all(10), // Inner padding for the log list
                      reverse: true, // Newest entries appear at the top
                      itemCount: logs.length, // Total number of log entries
                      itemBuilder: (_, i) {
                        final entry = logs[logs.length - 1 - i]; // Gets the log entry in reverse order (newest first)
                        final isError = entry.contains('error') || // Checks if this log entry describes an error
                            entry.contains('Error') ||
                            entry.contains('failed') ||
                            entry.contains('timed out');
                        return Text(
                          entry, // The raw log string
                          style: TextStyle(
                            fontSize: 11, // Small monospace-style font for logs
                            fontFamily: 'monospace', // Uses a monospaced font for log readability
                            height: 1.5, // Line height
                            color: isError ? _kRed : textColor, // Red for errors, normal text color otherwise
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }
}

// ── Error banner ──────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget { // A full-width red banner shown at the top of the screen to communicate errors (location off, permission denied, Wi-Fi off)
  const _ErrorBanner({
    required this.message, // The error message to display
    required this.isDark, // Whether dark mode is active
    this.onAction, // Optional callback for the action button (e.g., "Open Settings")
    this.actionLabel, // Optional label for the action button
  });
  final String message; // Stores the error message
  final bool isDark; // Stores the dark mode flag
  final VoidCallback? onAction; // Stores the optional action callback
  final String? actionLabel; // Stores the optional action button label

  @override
  Widget build(BuildContext context) { // Builds the error banner
    final textColor = isDark ? const Color(0xFFFFCDD2) : _kRed; // Light pink in dark mode, red in light mode
    return Container( // The full-width banner container
      width: double.infinity, // Stretches across the full screen width
      color: isDark ? _kRedDark : _kRedLight, // Dark red background in dark mode, light red in light mode
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10), // Inner padding (more on the left where text sits)
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: _kRed, size: 18), // Error icon on the left
          const SizedBox(width: 8), // Gap between icon and message text
          Expanded(
            child: Text(message, // The error message text
                style: TextStyle(fontSize: 13, color: textColor)), // Styled in the appropriate error text color
          ),
          if (onAction != null && actionLabel != null) // Only shows the action button if both the callback and label are provided
            TextButton(
              onPressed: onAction, // Calls the action callback when tapped
              style: TextButton.styleFrom(
                foregroundColor: textColor, // Button text matches the error text color
                textStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700), // Bold button text
                padding: const EdgeInsets.symmetric(horizontal: 8), // Compact horizontal padding
              ),
              child: Text(actionLabel!), // The action button label (e.g., "Retry", "Open Settings")
            ),
        ],
      ),
    );
  }
}

// ── Web unsupported ───────────────────────────────────────────────────────────

class _UnsupportedCard extends StatelessWidget { // A centered message shown when the app is running on the web (where Wi-Fi Direct is unavailable)
  const _UnsupportedCard({required this.isDark}); // Constructor takes the dark mode flag
  final bool isDark; // Stores the dark mode flag

  @override
  Widget build(BuildContext context) { // Builds the unsupported-on-web message
    return Center( // Centers the content on the screen
      child: Padding(
        padding: const EdgeInsets.all(32), // Generous padding around the content
        child: Column(
          mainAxisSize: MainAxisSize.min, // Column takes only as much space as needed
          children: [
            Icon(
              Icons.wifi_off_rounded, // Wi-Fi off icon to visually communicate no connectivity
              size: 56, // Large icon
              color: (isDark // Transparent secondary color for the icon
                      ? TogetherTheme.amoledTextSecondary
                      : TogetherTheme.ink)
                  .withValues(alpha: 0.4), // 40% opacity — subtle
            ),
            const SizedBox(height: 16), // Space between icon and heading
            Text(
              'Not available on web', // Heading explaining the feature is unavailable
              style: TextStyle(
                fontSize: 18, // Large heading font
                fontWeight: FontWeight.w700, // Bold
                color: isDark // Heading color for dark/light mode
                    ? TogetherTheme.amoledTextPrimary
                    : TogetherTheme.deepOcean,
              ),
            ),
            const SizedBox(height: 8), // Space between heading and explanation
            Text(
              'Emergency Comms uses Wi-Fi Direct, '
              'which requires the Android or iOS app.', // Explains why the feature is unavailable on web
              textAlign: TextAlign.center, // Centers the explanation text
              style: TextStyle(
                fontSize: 14, // Body text size
                height: 1.5, // Line height for readability
                color: isDark // Secondary text color
                    ? TogetherTheme.amoledTextSecondary
                    : TogetherTheme.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
