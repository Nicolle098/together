import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';

import '../../data/offline_seed_data.dart';
import '../../models/emergency_contact.dart';
import '../../models/medical_profile.dart';
import '../../services/app_settings_service.dart';
import '../../services/emergency_repository.dart';
import '../../theme/app_theme.dart';
import 'add_contact_sheet.dart';
import 'edit_sos_card_sheet.dart';
import 'ghid_viewer_screen.dart';
import '../p2p/p2p_screen.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key, this.firebaseReady = false});

  final bool firebaseReady;

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  // ── Repository & services ─────────────────────────────────────────────────

  final _repo = const EmergencyRepository();
  final _tts = FlutterTts();
  final _stt = stt.SpeechToText();

  // ── State ─────────────────────────────────────────────────────────────────

  MedicalProfile _sosCard = OfflineSeedData.medicalProfile;
  bool _sosExpanded = false;
  bool _savingSos = false;

  List<EmergencyContact> _phoneContacts = [];
  List<EmergencyContact> _manualContacts = [];
  bool _loadingContacts = true;

  final _messageCtrl = TextEditingController();
  bool _sttAvailable = false;
  bool _sttListening = false;
  bool _ttsPlaying = false;

  // ── Helpers ───────────────────────────────────────────────────────────────

  String? get _uid {
    if (!widget.firebaseReady) return null;
    try {
      final user = FirebaseAuth.instance.currentUser;
      return (user != null && user.emailVerified) ? user.uid : null;
    } catch (_) {
      return null;
    }
  }

  bool get _isLoggedIn => _uid != null;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadData();
    _initStt();
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _ttsPlaying = false);
    });
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    _tts.stop();
    _stt.stop();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loadingContacts = true);

    // Load SOS card from Firestore if logged in.
    if (_isLoggedIn) {
      final remote = await _repo.loadSosCard(_uid!);
      if (remote != null && mounted) setState(() => _sosCard = remote);
    }

    // Phone contacts and manual contacts can be loaded in parallel.
    final results = await Future.wait([
      _repo.loadPhoneContacts(),
      _isLoggedIn
          ? _repo.loadManualContacts(_uid!)
          : Future.value(const <EmergencyContact>[]),
    ]);

    if (!mounted) return;
    setState(() {
      _phoneContacts = results[0];
      _manualContacts = results[1];
      _loadingContacts = false;
    });
  }

  Future<void> _initStt() async {
    final available = await _stt.initialize(
      onError: (_) => setState(() => _sttListening = false),
      onStatus: (status) {
        if (mounted && status == 'done') {
          setState(() => _sttListening = false);
        }
      },
    );
    if (mounted) setState(() => _sttAvailable = available);
  }

  // ── SOS card ──────────────────────────────────────────────────────────────

  Future<void> _openEditSos() async {
    final updated = await showModalBottomSheet<MedicalProfile?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditSosCardSheet(profile: _sosCard),
    );
    if (updated == null || !mounted) return;
    setState(() {
      _sosCard = updated;
      _savingSos = true;
    });

    if (_isLoggedIn) {
      try {
        await _repo.saveSosCard(_uid!, updated);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not sync SOS card. Saved locally.')),
          );
        }
      }
    }

    if (mounted) setState(() => _savingSos = false);
  }

  // ── Contacts ──────────────────────────────────────────────────────────────

  Future<void> _openAddContact() async {
    if (!_isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign in to save personal contacts to the cloud.'),
        ),
      );
      return;
    }

    final contact = await showModalBottomSheet<EmergencyContact?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddContactSheet(),
    );
    if (contact == null || !mounted) return;

    try {
      final id = await _repo.saveContact(_uid!, contact);
      setState(() {
        _manualContacts = [
          ..._manualContacts,
          EmergencyContact(
            id: id,
            name: contact.name,
            role: contact.role,
            phoneNumber: contact.phoneNumber,
            priorityLabel: contact.priorityLabel,
          ),
        ];
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save contact: $e')),
        );
      }
    }
  }

  Future<void> _deleteContact(EmergencyContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove contact?'),
        content: Text('${contact.name} will be removed from your trusted contacts.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _manualContacts =
          _manualContacts.where((c) => c.id != contact.id).toList();
    });

    try {
      await _repo.deleteContact(_uid!, contact.id);
    } catch (e) {
      // Re-add if Firestore delete failed.
      if (mounted) {
        setState(() => _manualContacts = [..._manualContacts, contact]);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove contact: $e')),
        );
      }
    }
  }

  Future<void> _callContact(EmergencyContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Make a call?'),
        content: Text('Call ${contact.name} at ${contact.phoneNumber}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Call'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final uri = Uri(scheme: 'tel', path: contact.phoneNumber);
    try {
      await launchUrl(uri);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the phone app.')),
        );
      }
    }
  }

  // ── Quick message / TTS / STT ─────────────────────────────────────────────

  Future<void> _toggleListening() async {
    if (_sttListening) {
      await _stt.stop();
      setState(() => _sttListening = false);
      return;
    }
    setState(() => _sttListening = true);
    await _stt.listen(
      onResult: (result) {
        if (mounted) {
          setState(() => _messageCtrl.text = result.recognizedWords);
          _messageCtrl.selection = TextSelection.fromPosition(
            TextPosition(offset: _messageCtrl.text.length),
          );
        }
      },
      listenOptions: stt.SpeechListenOptions(cancelOnError: true),
    );
  }

  Future<void> _speakMessage() async {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty) return;

    if (_ttsPlaying) {
      await _tts.stop();
      setState(() => _ttsPlaying = false);
      return;
    }

    setState(() => _ttsPlaying = true);
    await _tts.speak(text);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = AppSettings.instance.lowBattery;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency'),
        backgroundColor: Colors.transparent,
        foregroundColor:
            isDark ? TogetherTheme.amoledTextPrimary : TogetherTheme.deepOcean,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Offline mode banner ───────────────────────────────
                  _OfflineBanner(isDark: isDark),

                  const SizedBox(height: 22),

                  // ── SOS card ──────────────────────────────────────────
                  _SectionTitle(
                    'SOS card',
                    isDark: isDark,
                    textTheme: textTheme,
                  ),
                  const SizedBox(height: 12),
                  _SosCard(
                    profile: _sosCard,
                    expanded: _sosExpanded,
                    saving: _savingSos,
                    isLoggedIn: _isLoggedIn,
                    isDark: isDark,
                    onToggle: () =>
                        setState(() => _sosExpanded = !_sosExpanded),
                    onEdit: _openEditSos,
                  ),

                  const SizedBox(height: 24),

                  // ── Trusted contacts ──────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _SectionTitle(
                        'Trusted contacts',
                        isDark: isDark,
                        textTheme: textTheme,
                      ),
                      IconButton(
                        tooltip: 'Add contact',
                        icon: Icon(
                          Icons.person_add_rounded,
                          color: isDark
                              ? TogetherTheme.amoledTextSecondary
                              : TogetherTheme.deepOcean,
                        ),
                        onPressed: _openAddContact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _ContactsSection(
                    phoneContacts: _phoneContacts,
                    manualContacts: _manualContacts,
                    loading: _loadingContacts,
                    isLoggedIn: _isLoggedIn,
                    isDark: isDark,
                    onCall: (c) => _callContact(c),
                    onDelete: _deleteContact,
                    onAdd: _openAddContact,
                  ),

                  const SizedBox(height: 24),

                  // ── Quick message ─────────────────────────────────────
                  _SectionTitle(
                    'Quick message',
                    isDark: isDark,
                    textTheme: textTheme,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Type or speak a message to show or read aloud to others.',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? TogetherTheme.amoledTextSecondary
                          : TogetherTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _QuickMessage(
                    controller: _messageCtrl,
                    isDark: isDark,
                    sttAvailable: _sttAvailable,
                    sttListening: _sttListening,
                    ttsPlaying: _ttsPlaying,
                    onMic: _toggleListening,
                    onSpeak: _speakMessage,
                  ),

                  const SizedBox(height: 24),

                  // ── Offline guides ────────────────────────────────────
                  _SectionTitle(
                    'Offline guides',
                    isDark: isDark,
                    textTheme: textTheme,
                  ),
                  const SizedBox(height: 12),
                  _GhidEntryCard(isDark: isDark),

                  const SizedBox(height: 8),

                  // ── Emergency Comms (P2P) ─────────────────────────────
                  _SectionTitle(
                    'Emergency Comms',
                    isDark: isDark,
                    textTheme: textTheme,
                  ),
                  const SizedBox(height: 12),
                  _P2pEntryCard(isDark: isDark),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Offline banner ────────────────────────────────────────────────────────────

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF1A0A0A) : const Color(0xFFFDE8E8);
    final border = isDark ? const Color(0xFF5A1A1A) : const Color(0xFFF3B4B4);
    final titleColor =
        isDark ? const Color(0xFFFFB4B4) : const Color(0xFF7A271A);
    final bodyColor = isDark ? TogetherTheme.amoledTextSecondary : TogetherTheme.ink;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A0A0A) : Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.warning_amber_rounded,
              color: isDark ? const Color(0xFFFFB4B4) : const Color(0xFFB42318),
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Offline emergency mode',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                    fontFamily: 'RobotoSlab',
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'This screen works without internet, without sign-in, and under stress.',
                  style: TextStyle(fontSize: 14, height: 1.4, color: bodyColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── SOS card ──────────────────────────────────────────────────────────────────

class _SosCard extends StatelessWidget {
  const _SosCard({
    required this.profile,
    required this.expanded,
    required this.saving,
    required this.isLoggedIn,
    required this.isDark,
    required this.onToggle,
    required this.onEdit,
  });

  final MedicalProfile profile;
  final bool expanded;
  final bool saving;
  final bool isLoggedIn;
  final bool isDark;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? TogetherTheme.amoledSurface : Colors.white;
    final border =
        isDark ? TogetherTheme.amoledBorder : const Color(0xFFDCE4EA);
    final titleColor =
        isDark ? TogetherTheme.amoledTextPrimary : TogetherTheme.deepOcean;
    final bodyColor =
        isDark ? TogetherTheme.amoledTextSecondary : TogetherTheme.ink;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          // ── Collapsed header (always visible) ─────────────────────────
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1A0A0A)
                          : const Color(0xFFFDE8E8),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      profile.bloodType.isEmpty ? '—' : profile.bloodType,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: isDark
                            ? const Color(0xFFFFB4B4)
                            : const Color(0xFFB42318),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SOS card',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: titleColor,
                            fontFamily: 'RobotoSlab',
                          ),
                        ),
                        if (!expanded)
                          Text(
                            _collapsedSummary(profile),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(fontSize: 13, color: bodyColor),
                          ),
                      ],
                    ),
                  ),
                  if (saving)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: bodyColor,
                    ),
                ],
              ),
            ),
          ),

          // ── Expanded body ─────────────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Divider(
                        height: 1,
                        color: border,
                        indent: 18,
                        endIndent: 18,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SosRow(
                              'Allergies',
                              _listOrNone(profile.allergies),
                              isDark: isDark,
                            ),
                            _SosRow(
                              'Medications',
                              _listOrNone(profile.medications),
                              isDark: isDark,
                            ),
                            _SosRow(
                              'Mobility',
                              _listOrNone(profile.mobilityNeeds),
                              isDark: isDark,
                            ),
                            _SosRow(
                              'Communication',
                              _listOrNone(profile.communicationNeeds),
                              isDark: isDark,
                            ),
                            if (profile.emergencyNotes.isNotEmpty)
                              _SosRow(
                                'Notes',
                                profile.emergencyNotes,
                                isDark: isDark,
                              ),
                            const SizedBox(height: 10),
                            if (!isLoggedIn)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(
                                  'Sign in to save your SOS card to the cloud.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: bodyColor,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            OutlinedButton.icon(
                              onPressed: onEdit,
                              icon: const Icon(Icons.edit_rounded, size: 18),
                              label: const Text('Edit SOS card'),
                            ),
                            const SizedBox(height: 14),
                          ],
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  String _collapsedSummary(MedicalProfile p) {
    final parts = <String>[];
    if (p.allergies.isNotEmpty) parts.add('Allergy: ${p.allergies.first}');
    if (p.medications.isNotEmpty) parts.add(p.medications.first);
    return parts.isEmpty ? 'Tap to view your card' : parts.join(' · ');
  }

  String _listOrNone(List<String> items) =>
      items.isEmpty ? 'None listed' : items.join(', ');
}

class _SosRow extends StatelessWidget {
  const _SosRow(this.label, this.value, {required this.isDark});

  final String label;
  final String value;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? TogetherTheme.amoledTextPrimary
                    : TogetherTheme.deepOcean,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                fontSize: 14,
                color: isDark
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

// ── Contacts section ──────────────────────────────────────────────────────────

class _ContactsSection extends StatelessWidget {
  const _ContactsSection({
    required this.phoneContacts,
    required this.manualContacts,
    required this.loading,
    required this.isLoggedIn,
    required this.isDark,
    required this.onCall,
    required this.onDelete,
    required this.onAdd,
  });

  final List<EmergencyContact> phoneContacts;
  final List<EmergencyContact> manualContacts;
  final bool loading;
  final bool isLoggedIn;
  final bool isDark;
  final void Function(EmergencyContact contact) onCall;
  final void Function(EmergencyContact contact) onDelete;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final all = [...phoneContacts, ...manualContacts];

    if (all.isEmpty) {
      return _EmptyContacts(isDark: isDark, isLoggedIn: isLoggedIn, onAdd: onAdd);
    }

    return Column(
      children: all.map((c) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _ContactCard(
            contact: c,
            isDark: isDark,
            onCall: () => onCall(c),
            onDelete: c.isFromPhone ? null : () => onDelete(c),
          ),
        );
      }).toList(),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.contact,
    required this.isDark,
    required this.onCall,
    this.onDelete,
  });

  final EmergencyContact contact;
  final bool isDark;
  final VoidCallback onCall;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? TogetherTheme.amoledSurface : Colors.white;
    final border =
        isDark ? TogetherTheme.amoledBorder : const Color(0xFFDCE4EA);
    final titleColor =
        isDark ? TogetherTheme.amoledTextPrimary : TogetherTheme.deepOcean;
    final bodyColor =
        isDark ? TogetherTheme.amoledTextSecondary : TogetherTheme.ink;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor:
              isDark ? TogetherTheme.amoledSurfaceElevated : TogetherTheme.mist,
          child: Icon(
            contact.isFromPhone
                ? Icons.star_rounded
                : Icons.contact_phone_rounded,
            color: isDark
                ? TogetherTheme.amoledTextSecondary
                : TogetherTheme.deepOcean,
          ),
        ),
        title: Text(
          contact.name,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: titleColor,
            fontFamily: 'RobotoSlab',
          ),
        ),
        subtitle: Text(
          '${contact.role}  ·  ${contact.phoneNumber}  ·  ${contact.priorityLabel}',
          style: TextStyle(fontSize: 13, color: bodyColor),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Call',
              icon: Icon(
                Icons.call_rounded,
                color: isDark
                    ? TogetherTheme.amoledTextSecondary
                    : TogetherTheme.deepOcean,
              ),
              onPressed: onCall,
            ),
            if (onDelete != null)
              IconButton(
                tooltip: 'Remove',
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: isDark
                      ? const Color(0xFFFFB4B4)
                      : const Color(0xFFB42318),
                ),
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyContacts extends StatelessWidget {
  const _EmptyContacts({
    required this.isDark,
    required this.isLoggedIn,
    required this.onAdd,
  });

  final bool isDark;
  final bool isLoggedIn;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final color =
        isDark ? TogetherTheme.amoledTextSecondary : TogetherTheme.ink;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            phoneContactsUnavailable,
            style: TextStyle(fontSize: 13, color: color),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.person_add_rounded, size: 18),
          label: Text(
            isLoggedIn ? 'Add a contact' : 'Sign in to add contacts',
          ),
        ),
      ],
    );
  }

  String get phoneContactsUnavailable =>
      'No starred contacts found in your phone book, and no contacts have been added yet.';
}

// ── Quick message ─────────────────────────────────────────────────────────────

class _QuickMessage extends StatelessWidget {
  const _QuickMessage({
    required this.controller,
    required this.isDark,
    required this.sttAvailable,
    required this.sttListening,
    required this.ttsPlaying,
    required this.onMic,
    required this.onSpeak,
  });

  final TextEditingController controller;
  final bool isDark;
  final bool sttAvailable;
  final bool sttListening;
  final bool ttsPlaying;
  final VoidCallback onMic;
  final VoidCallback onSpeak;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? TogetherTheme.amoledSurface : Colors.white;
    final border =
        isDark ? TogetherTheme.amoledBorder : const Color(0xFFDCE4EA);
    final textColor =
        isDark ? TogetherTheme.amoledTextPrimary : TogetherTheme.ink;
    final hintColor =
        isDark ? TogetherTheme.amoledBorder : const Color(0xFF9BA7B0);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: sttListening
              ? (isDark ? TogetherTheme.amoledAccentPurple : TogetherTheme.deepOcean)
              : border,
          width: sttListening ? 2 : 1,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            style: TextStyle(fontSize: 17, color: textColor, height: 1.5),
            maxLines: 4,
            minLines: 2,
            decoration: InputDecoration.collapsed(
              hintText: sttListening
                  ? 'Listening…'
                  : 'Type your emergency message here…',
              hintStyle: TextStyle(color: hintColor),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (sttAvailable)
                _MsgButton(
                  icon: sttListening ? Icons.mic_off_rounded : Icons.mic_rounded,
                  label: sttListening ? 'Stop' : 'Speak',
                  color: sttListening
                      ? (isDark
                          ? TogetherTheme.amoledAccentPurple
                          : TogetherTheme.deepOcean)
                      : (isDark
                          ? TogetherTheme.amoledTextSecondary
                          : TogetherTheme.ink),
                  onTap: onMic,
                ),
              const SizedBox(width: 6),
              _MsgButton(
                icon: ttsPlaying
                    ? Icons.stop_rounded
                    : Icons.volume_up_rounded,
                label: ttsPlaying ? 'Stop' : 'Read aloud',
                color: isDark
                    ? TogetherTheme.amoledTextSecondary
                    : TogetherTheme.deepOcean,
                onTap: onSpeak,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MsgButton extends StatelessWidget {
  const _MsgButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Offline guide entry card ──────────────────────────────────────────────────

class _GhidEntryCard extends StatelessWidget {
  const _GhidEntryCard({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? TogetherTheme.amoledSurface : Colors.white;
    final border =
        isDark ? TogetherTheme.amoledBorder : const Color(0xFFDCE4EA);
    final titleColor =
        isDark ? TogetherTheme.amoledTextPrimary : TogetherTheme.deepOcean;
    final bodyColor =
        isDark ? TogetherTheme.amoledTextSecondary : TogetherTheme.ink;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const GhidViewerScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor:
                  isDark ? TogetherTheme.amoledSurfaceElevated : TogetherTheme.mist,
              foregroundColor:
                  isDark ? TogetherTheme.amoledTextSecondary : TogetherTheme.deepOcean,
              child: const Icon(Icons.menu_book_rounded),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Emergency Guide (Ghid)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                      fontFamily: 'RobotoSlab',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap to open the full offline safety guide — available without internet.',
                    style: TextStyle(fontSize: 13, height: 1.4, color: bodyColor),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: bodyColor),
          ],
        ),
      ),
    );
  }
}

// ── P2P entry card ────────────────────────────────────────────────────────────

class _P2pEntryCard extends StatelessWidget {
  const _P2pEntryCard({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF1A0A0A) : const Color(0xFFFDE8E8);
    final border = isDark ? const Color(0xFF5A1A1A) : const Color(0xFFF3B4B4);
    final titleColor =
        isDark ? const Color(0xFFFFB4B4) : const Color(0xFF7A271A);
    final bodyColor =
        isDark ? TogetherTheme.amoledTextSecondary : TogetherTheme.ink;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const P2pScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2A0A0A) : Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.sensors_rounded,
                color: isDark ? const Color(0xFFFFB4B4) : const Color(0xFFB42318),
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Emergency Comms',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Message nearby Together users via Bluetooth — no internet needed.',
                    style: TextStyle(fontSize: 13, color: bodyColor),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: titleColor),
          ],
        ),
      ),
    );
  }
}

// ── Shared ────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text,
      {required this.isDark, required this.textTheme});

  final String text;
  final bool isDark;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: textTheme.titleLarge?.copyWith(
        color: isDark ? TogetherTheme.amoledTextPrimary : TogetherTheme.deepOcean,
      ),
    );
  }
}
