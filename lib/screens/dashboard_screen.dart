import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/hazard_notification_service.dart';
import '../theme/app_theme.dart';
import 'assistant/audio_scribe_screen.dart';
import 'assistant/gemma_assistant_screen.dart';
import 'emergency/emergency_screen.dart';
import 'community/community_screen.dart';
import 'map/safety_map_screen.dart';
import 'profile/profile_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.firebaseReady = false});

  final bool firebaseReady;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    if (widget.firebaseReady) {
      _registerFcmToken();
    }
  }

  /// Registers the device FCM token under `users/{uid}` in Firestore so the
  /// server can send targeted out-of-app push notifications for nearby hazards.
  /// Best-effort — any failure is swallowed so the UI is never disrupted.
  Future<void> _registerFcmToken() async {
    if (kIsWeb) return; // FCM service worker not configured for web
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && user.emailVerified) {
        await HazardNotificationService.registerFcmToken(uid: user.uid);
      }
    } catch (_) {}
  }

  void _openTab(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      _HomeTab(
        onOpenMap: () => _openTab(1),
        onOpenEmergency: () => _openTab(2),
        onOpenHelp: () => _openTab(3),
        onOpenProfile: () => _openTab(4),
        onOpenFreeAI: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const GemmaAssistantScreen(),
          ),
        ),
        onOpenAudioScribe: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AudioScribeScreen()),
        ),
      ),
      SafetyMapScreen(firebaseReady: widget.firebaseReady),
      EmergencyScreen(firebaseReady: widget.firebaseReady),
      const CommunityScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        indicatorColor: TogetherTheme.mist,
        onDestinationSelected: _openTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map_rounded),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.sos_outlined),
            selectedIcon: Icon(Icons.sos_rounded),
            label: 'Emergency',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups_rounded),
            label: 'Community',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const GemmaAssistantScreen(),
          ),
        ),
        backgroundColor: TogetherTheme.deepOcean,
        foregroundColor: Colors.white,
        tooltip: 'AI Assistant',
        child: const Icon(Icons.memory_rounded),
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.onOpenMap,
    required this.onOpenEmergency,
    required this.onOpenHelp,
    required this.onOpenProfile,
    required this.onOpenFreeAI,
    required this.onOpenAudioScribe,
  });

  final VoidCallback onOpenMap;
  final VoidCallback onOpenEmergency;
  final VoidCallback onOpenHelp;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenFreeAI;
  final VoidCallback onOpenAudioScribe;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth < 380 ? 16.0 : 20.0;

            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  16,
                  horizontalPadding,
                  24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              TogetherTheme.deepOcean,
                              TogetherTheme.forest,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: Color(0x26FFFFFF),
                                  child: Icon(
                                    Icons.health_and_safety_rounded,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    'Together Safety Hub',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'RobotoSlab',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Offline-first support for accessible travel, emergency readiness, and calmer daily use.',
                              style: textTheme.bodyLarge?.copyWith(
                                color: Colors.white.withValues(alpha: 0.92),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.cloud_off_rounded,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Emergency tools should keep working without internet, sign-in, or live sync.',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Core modules',
                        style: textTheme.titleLarge?.copyWith(
                          color: TogetherTheme.deepOcean,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _ModuleGrid(
                        onMapTap: onOpenMap,
                        onEmergencyTap: onOpenEmergency,
                        onHelpTap: onOpenHelp,
                        onProfileTap: onOpenProfile,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Quick actions',
                        style: textTheme.titleLarge?.copyWith(
                          color: TogetherTheme.deepOcean,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _QuickActionTile(
                        icon: Icons.sos_rounded,
                        title: 'Open emergency mode',
                        subtitle:
                            'Reach SOS, contacts, medical info, and offline guides.',
                        tint: const Color(0xFFFDE8E8),
                        onTap: onOpenEmergency,
                      ),
                      const SizedBox(height: 12),
                      _QuickActionTile(
                        icon: Icons.place_rounded,
                        title: 'Check nearest safe place',
                        subtitle:
                            'Review shelter, hospital, and pharmacy data from the offline pack.',
                        tint: const Color(0xFFE7F4EF),
                        onTap: onOpenMap,
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'AI Assistants',
                        style: textTheme.titleLarge?.copyWith(
                          color: TogetherTheme.deepOcean,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _AiCard(
                        icon: Icons.memory_rounded,
                        label: 'On-device AI',
                        badge: 'Free • Offline',
                        description:
                            'Powered by Gemma. Works without internet, no subscription needed.',
                        accentColor: const Color(0xFF059669),
                        bgColor: const Color(0xFFD1FAE5),
                        onTap: onOpenFreeAI,
                      ),
                      const SizedBox(height: 12),
                      _QuickActionTile(
                        icon: Icons.mic_rounded,
                        title: 'Audio Scribe',
                        subtitle:
                            'Record speech, transcribe live, then enhance or translate with on-device Gemma.',
                        tint: const Color(0xFFCCFBF1),
                        onTap: onOpenAudioScribe,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ModuleGrid extends StatelessWidget {
  const _ModuleGrid({
    required this.onMapTap,
    required this.onEmergencyTap,
    required this.onHelpTap,
    required this.onProfileTap,
  });

  final VoidCallback onMapTap;
  final VoidCallback onEmergencyTap;
  final VoidCallback onHelpTap;
  final VoidCallback onProfileTap;

  @override
  Widget build(BuildContext context) {
    final modules = [
      (
        Icons.sos_rounded,
        'Emergency Mode',
        'SOS actions, guides, and contacts built for offline use.',
        onEmergencyTap,
      ),
      (
        Icons.map_rounded,
        'Safety Map',
        'Shelters, hospitals, and safe points from the offline pack.',
        onMapTap,
      ),
      (
        Icons.record_voice_over_rounded,
        'Accessibility Profile',
        'Text size, contrast, voice guidance, and map pack preferences.',
        onProfileTap,
      ),
      (
        Icons.groups_rounded,
        'Community',
        'Jobs, courses, safety news, and local announcements.',
        onHelpTap,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 430;

        if (!twoColumns) {
          return Column(
            children: modules
                .map((m) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _ModuleCard(module: m),
                    ))
                .toList(),
          );
        }

        // Two-column layout: pair cards in IntrinsicHeight rows so both
        // cards in each row grow to match the taller one.
        final rows = <Widget>[];
        for (int i = 0; i < modules.length; i += 2) {
          final right = i + 1 < modules.length ? modules[i + 1] : null;
          rows.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _ModuleCard(module: modules[i])),
                    const SizedBox(width: 14),
                    Expanded(
                      child: right != null
                          ? _ModuleCard(module: right)
                          : const SizedBox(),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return Column(children: rows);
      },
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module});

  final (IconData, String, String, VoidCallback) module;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: module.$4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFDCE4EA)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: TogetherTheme.mist,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(module.$1, color: TogetherTheme.forest),
              ),
              const SizedBox(height: 16),
              Text(
                module.$2,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: TogetherTheme.deepOcean,
                  fontFamily: 'RobotoSlab',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                module.$3,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: TogetherTheme.ink,
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiCard extends StatelessWidget {
  const _AiCard({
    required this.icon,
    required this.label,
    required this.badge,
    required this.description,
    required this.accentColor,
    required this.bgColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String badge;
  final String description;
  final Color accentColor;
  final Color bgColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFDCE4EA)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accentColor, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: accentColor,
                fontFamily: 'RobotoSlab',
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 2, bottom: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: accentColor,
                ),
              ),
            ),
            Text(
              description,
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: TogetherTheme.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tint,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFDCE4EA)),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                color: TogetherTheme.deepOcean,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: TogetherTheme.deepOcean,
                      fontFamily: 'RobotoSlab',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 15,
                      color: TogetherTheme.ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
