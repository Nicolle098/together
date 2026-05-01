import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:nearby_service/nearby_service.dart';

class P2pDevice {
  final String id;
  final String name;
  final bool isConnected;
  final bool isConnecting;

  const P2pDevice({
    required this.id,
    required this.name,
    this.isConnected = false,
    this.isConnecting = false,
  });

  P2pDevice copyWith({bool? isConnected, bool? isConnecting}) => P2pDevice(
        id: id,
        name: name,
        isConnected: isConnected ?? this.isConnected,
        isConnecting: isConnecting ?? this.isConnecting,
      );
}

class P2pMessage {
  final String senderId;
  final String senderName;
  final String text;
  final DateTime time;
  final bool isMine;
  final bool isSos;
  // Empty peerId = broadcast (SOS to all).
  final String peerId;

  const P2pMessage({
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.time,
    required this.peerId,
    this.isMine = false,
    this.isSos = false,
  });
}

class P2pService {
  final String userName;

  late final NearbyService _nearby;

  final _devicesController = StreamController<List<P2pDevice>>.broadcast();
  final _messageController = StreamController<P2pMessage>.broadcast();
  final _logController = StreamController<String>.broadcast();

  Stream<List<P2pDevice>> get devicesStream => _devicesController.stream;
  Stream<P2pMessage> get messagesStream => _messageController.stream;
  Stream<String> get logStream => _logController.stream;

  final List<String> logs = [];

  final Map<String, NearbyDevice> _nearbyDevices = {};
  final Map<String, P2pDevice> _discovered = {};
  final Map<String, P2pDevice> _connected = {};
  final Set<String> _openChannels = {};

  StreamSubscription? _peersSubscription;

  bool _running = false;

  bool needsWifi = false;
  String get transportLabel => 'Wi-Fi Direct';

  bool get isRunning => _running;

  List<P2pDevice> get discoveredDevices => _discovered.values.toList();
  List<P2pDevice> get connectedDevices => _connected.values.toList();

  P2pService({required this.userName}) {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      _nearby = NearbyService.getInstance(
        logLevel: kDebugMode
            ? NearbyServiceLogLevel.debug
            : NearbyServiceLogLevel.error,
      );
    }
  }

  void _log(String message) {
    debugPrint('P2pService: $message');
    final stamped =
        '[${DateTime.now().toIso8601String().substring(11, 19)}] $message';
    logs.add(stamped);
    if (!_logController.isClosed) _logController.add(stamped);
  }

  // ── Start discovery ────────────────────────────────────────────────────────

  Future<void> start() async {
    if (kIsWeb || _running) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _running = true;
    _log('Starting — user "$userName"');

    try {
      await _nearby.initialize();
      _log('Service initialized');
    } catch (e) {
      _log('Init error — $e');
      _running = false;
      return;
    }

    if (Platform.isAndroid) {
      try {
        final granted = await _nearby.android!.requestPermissions();
        if (!granted) {
          _log('Permissions not granted — cannot start P2P');
          _running = false;
          return;
        }
      } catch (e) {
        _log('Permission request error — $e');
      }
    }

    if (Platform.isAndroid) {
      try {
        final wifiOn = await _nearby.android!.checkWifiService();
        needsWifi = !wifiOn;
        if (!wifiOn) _log('Wi-Fi is off — enable it for P2P connections');
      } catch (_) {}
    }

    try {
      final ok = await _nearby.discover();
      _log(ok ? 'Discovery started' : 'Discovery failed to start');
    } catch (e) {
      _log('Discovery error — $e');
      return;
    }

    // Subscribe to the live stream of nearby peers and route updates to our handler
    _peersSubscription = _nearby.getPeersStream().listen(
      _onPeersUpdate,
      onError: (e) => _log('Peers stream error — $e'),
    );
  }

  // ── Peers stream handler ───────────────────────────────────────────────────

  void _onPeersUpdate(List<NearbyDevice> peers) {
    final previouslyConnected = Set.of(_connected.keys);

    _nearbyDevices.clear();
    _discovered.clear();
    final newConnected = <String, P2pDevice>{};

    for (final p in peers) {
      _nearbyDevices[p.info.id] = p;

      if (p.status.isConnected) {
        newConnected[p.info.id] = P2pDevice(
          id: p.info.id,
          name: p.info.displayName,
          isConnected: true,
        );
        if (!previouslyConnected.contains(p.info.id)) {
          _log('Connected to ${p.info.displayName}');
          _openChannel(p.info.id);
        }
      } else if (p.status.isAvailable) {
        _discovered[p.info.id] = P2pDevice(
          id: p.info.id,
          name: p.info.displayName,
        );
      } else if (p.status.isConnecting) {
        _discovered[p.info.id] = P2pDevice(
          id: p.info.id,
          name: p.info.displayName,
          isConnecting: true,
        );
      } else if (p.status.isFailed) {
        _log('Device ${p.info.displayName} — connection failed');
      }
    }

    for (final id in previouslyConnected) {
      if (!newConnected.containsKey(id)) {
        _log('Disconnected: $id');
        _openChannels.remove(id);
      }
    }

    _connected
      ..clear()
      ..addAll(newConnected);
    _emitDevices();
  }

  Future<void> _openChannel(String id) async {
    if (_openChannels.contains(id)) return;
    try {
      await _nearby.startCommunicationChannel(
        NearbyCommunicationChannelData(
          id,
          messagesListener: NearbyServiceMessagesListener(
            onData: _onMessage,
            onError: (e, [st = StackTrace.empty]) =>
                _log('Channel error — $e'),
          ),
        ),
      );
      _openChannels.add(id);
      _log('Communication channel open with $id');
    } catch (e) {
      _log('Channel open error — $e');
    }
  }

  void _onMessage(ReceivedNearbyMessage msg) {
    msg.content.byType(
      onTextRequest: (t) {
        final text = t.value;
        _messageController.add(P2pMessage(
          senderId: msg.sender.id,
          senderName: msg.sender.displayName,
          text: text,
          time: DateTime.now(),
          isMine: false,
          isSos: text.startsWith('🆘'), // mesaj SOS dacă începe cu emoji-ul standard
          peerId: msg.sender.id,
        ));
      },
    );
  }

  // ── Connect to a specific device ───────────────────────────────────────────

  Future<void> connect(String id) async {
    _log('Requesting connection to $id');
    try {
      final ok = await _nearby.connectById(id);
      if (!ok) _log('Connection request to $id returned false');
    } catch (e) {
      _log('Connect error — $e');
    }
  }

  // ── Direct message to one peer ─────────────────────────────────────────────

  Future<void> sendMessageTo(String deviceId, String text) async {
    final device = _nearbyDevices[deviceId];
    if (device == null) return;
    try {
      await _nearby.send(OutgoingNearbyMessage(
        receiver: device.info,
        content: NearbyMessageTextRequest.create(value: text),
      ));
    } catch (e) {
      _log('Send to $deviceId error — $e');
      return;
    }
    _messageController.add(P2pMessage(
      senderId: 'me',
      senderName: userName,
      text: text,
      time: DateTime.now(),
      isMine: true,
      isSos: false,
      peerId: deviceId,
    ));
  }

  // ── Broadcast to all connected peers ──────────────────────────────────────

  Future<void> sendMessage(String text) async {
    if (_connected.isEmpty) return;
    for (final id in List.of(_connected.keys)) {
      final device = _nearbyDevices[id];
      if (device == null) continue;
      try {
        await _nearby.send(OutgoingNearbyMessage(
          receiver: device.info,
          content: NearbyMessageTextRequest.create(value: text),
        ));
      } catch (e) {
        _log('Send to $id error — $e');
      }
    }
    _messageController.add(P2pMessage(
      senderId: 'me',
      senderName: userName,
      text: text,
      time: DateTime.now(),
      isMine: true,
      isSos: text.startsWith('🆘'),
      peerId: '', // string gol = broadcast, nu mesaj direct
    ));
  }

  Future<void> broadcastSos({
    required String sosText,
    String? locationLabel,
  }) async {
    final loc = locationLabel != null ? '\nLocation: $locationLabel' : '';
    await sendMessage('🆘 SOS BROADCAST\n$sosText$loc');
  }

  Future<void> openServicesSettings() => _nearby.openServicesSettings();

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _emitDevices() {
    if (!_devicesController.isClosed) {
      _devicesController.add([...discoveredDevices, ...connectedDevices]);
    }
  }

  Future<void> dispose() async {
    _running = false;
    _peersSubscription?.cancel();
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try { await _nearby.disconnectById(); } catch (_) {}
      try { await _nearby.endCommunicationChannel(); } catch (_) {}
      try { await _nearby.stopDiscovery(); } catch (_) {}
    }
    _openChannels.clear();
    await _devicesController.close();
    await _messageController.close();
    await _logController.close();
  }
}
