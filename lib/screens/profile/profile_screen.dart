import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/app_settings_service.dart';
import '../../theme/app_theme.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) => _ProfileView(settings: AppSettings.instance),
    );
  }
}

// ── Main view ─────────────────────────────────────────────────────────────────

class _ProfileView extends StatefulWidget {
  const _ProfileView({required this.settings});

  final AppSettings settings;

  @override
  State<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<_ProfileView> {
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    final saved = widget.settings.displayNameRaw;
    _nameCtrl = TextEditingController(text: saved);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final textTheme = Theme.of(context).textTheme;
    final isDark = settings.lowBattery;

    final sectionHeaderColor =
        isDark ? TogetherTheme.amoledTextSecondary : TogetherTheme.deepOcean;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile & Settings'),
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
                  // ── Identity ──────────────────────────────────────────────
                  _GroupLabel(
                    label: 'Identity',
                    isDark: isDark,
                    icon: Icons.person_rounded,
                  ),
                  const SizedBox(height: 10),
                  _NameField(
                    isDark: isDark,
                    controller: _nameCtrl,
                    onSaved: (name) => settings.setDisplayName(name),
                  ),

                  const SizedBox(height: 20),

                  // ── Intro card ────────────────────────────────────────────
                  _SectionCard(
                    isDark: isDark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Accessibility & display',
                          style: textTheme.headlineMedium?.copyWith(
                            color: sectionHeaderColor,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Settings are saved on this device. '
                          'They take effect immediately and persist across sessions.',
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.45,
                            color: isDark
                                ? TogetherTheme.amoledTextSecondary
                                : TogetherTheme.ink,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Display ───────────────────────────────────────────────
                  _GroupLabel(
                    label: 'Display',
                    isDark: isDark,
                    icon: Icons.palette_outlined,
                  ),
                  const SizedBox(height: 10),

                  _SettingToggle(
                    isDark: isDark,
                    icon: Icons.battery_saver_rounded,
                    iconColor: isDark
                        ? TogetherTheme.amoledAccentPurple
                        : const Color(0xFF594088),
                    title: 'Low battery mode',
                    subtitle:
                        'Switches to a pure-black AMOLED theme. Saves up to '
                        '30 % screen power on OLED devices. No effect on LCD.',
                    value: settings.lowBattery,
                    onChanged: settings.setLowBattery,
                  ),
                  const SizedBox(height: 12),

                  _SettingToggle(
                    isDark: isDark,
                    icon: Icons.contrast_rounded,
                    iconColor: isDark
                        ? TogetherTheme.amoledWarning
                        : TogetherTheme.deepOcean,
                    title: 'High contrast mode',
                    subtitle:
                        'Reinforces borders and deepens text colour for bright '
                        'outdoor environments or low vision. Overridden by low '
                        'battery mode when both are on.',
                    value: settings.highContrast,
                    onChanged: settings.setHighContrast,
                  ),

                  const SizedBox(height: 20),

                  // ── Text ──────────────────────────────────────────────────
                  _GroupLabel(
                    label: 'Text',
                    isDark: isDark,
                    icon: Icons.text_fields_rounded,
                  ),
                  const SizedBox(height: 10),

                  _SettingToggle(
                    isDark: isDark,
                    icon: Icons.text_increase_rounded,
                    iconColor: isDark
                        ? TogetherTheme.amoledTextSecondary
                        : TogetherTheme.forest,
                    title: 'Large text mode',
                    subtitle:
                        'Increases all text to 130 % of its normal size. '
                        'Recommended under stress or for users with low vision.',
                    value: settings.largeText,
                    onChanged: settings.setLargeText,
                  ),

                  const SizedBox(height: 20),

                  // ── Data ──────────────────────────────────────────────────
                  _GroupLabel(
                    label: 'Data',
                    isDark: isDark,
                    icon: Icons.storage_rounded,
                  ),
                  const SizedBox(height: 10),

                  _InfoTile(
                    isDark: isDark,
                    icon: Icons.download_done_rounded,
                    iconColor: isDark
                        ? TogetherTheme.amoledTextSecondary
                        : TogetherTheme.forest,
                    title: 'Offline map packs',
                    subtitle:
                        'City-level safety datasets are included in this '
                        'build. Downloadable regional packs are coming soon.',
                  ),

                  const SizedBox(height: 28),

                  // ── Contact support ───────────────────────────────────────
                  _GroupLabel(
                    label: 'Support',
                    isDark: isDark,
                    icon: Icons.support_agent_rounded,
                  ),
                  const SizedBox(height: 10),
                  _SectionCard(
                    isDark: isDark,
                    child: Column(
                      children: [
                        _SupportTile(
                          isDark: isDark,
                          icon: Icons.mail_rounded,
                          title: 'Email support',
                          subtitle: 'Feedback, bugs, or accessibility concerns.',
                          url: 'mailto:support@together-app.com'
                              '?subject=Together%20App%20Feedback',
                        ),
                        _SupportTile(
                          isDark: isDark,
                          icon: Icons.call_rounded,
                          title: 'Call support',
                          subtitle: 'When speaking is easier than typing.',
                          url: 'tel:+40800000000',
                          isLast: true,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Active settings summary ───────────────────────────────
                  if (_anyActive(settings)) ...[
                    _ActiveSummary(settings: settings, isDark: isDark),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _anyActive(AppSettings s) =>
      s.lowBattery || s.largeText || s.highContrast || s.voiceGuidance;
}

// ── Active settings summary ───────────────────────────────────────────────────

class _ActiveSummary extends StatelessWidget {
  const _ActiveSummary({required this.settings, required this.isDark});

  final AppSettings settings;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final active = <String>[
      if (settings.lowBattery) 'Low battery mode',
      if (settings.highContrast) 'High contrast mode',
      if (settings.largeText) 'Large text (130 %)',
      if (settings.voiceGuidance) 'Voice guidance',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? TogetherTheme.amoledSurface
            : const Color(0xFFEAF6F0),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? TogetherTheme.amoledBorder
              : TogetherTheme.forest.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_rounded,
            color: isDark ? TogetherTheme.amoledTextSecondary : TogetherTheme.forest,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Active: ${active.join(' · ')}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.4,
                color: isDark
                    ? TogetherTheme.amoledTextSecondary
                    : TogetherTheme.forest,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Name field ────────────────────────────────────────────────────────────────

class _NameField extends StatelessWidget {
  const _NameField({
    required this.isDark,
    required this.controller,
    required this.onSaved,
  });

  final bool isDark;
  final TextEditingController controller;
  final void Function(String) onSaved;

  @override
  Widget build(BuildContext context) {
    final tileColor = isDark ? TogetherTheme.amoledSurface : Colors.white;
    final borderColor = isDark ? TogetherTheme.amoledBorder : const Color(0xFFDCE4EA);
    final titleColor = isDark ? TogetherTheme.amoledTextPrimary : TogetherTheme.deepOcean;
    final subtitleColor = isDark ? TogetherTheme.amoledTextSecondary : TogetherTheme.ink;

    return Container(
      decoration: BoxDecoration(
        color: tileColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: isDark
                    ? TogetherTheme.amoledSurfaceElevated
                    : TogetherTheme.mist,
                foregroundColor: isDark
                    ? TogetherTheme.amoledAccentPurple
                    : TogetherTheme.deepOcean,
                child: const Icon(Icons.badge_rounded),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Display name',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                    fontFamily: 'RobotoSlab',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 54),
            child: Text(
              'Shown to nearby Together users in Emergency Comms.',
              style: TextStyle(fontSize: 13, height: 1.45, color: subtitleColor),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            maxLength: 32,
            textInputAction: TextInputAction.done,
            style: TextStyle(color: titleColor, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'e.g. Maria, Rescue Team 3…',
              hintStyle: TextStyle(color: subtitleColor.withValues(alpha: 0.5)),
              counterText: '',
              filled: true,
              fillColor: isDark
                  ? TogetherTheme.amoledSurfaceElevated
                  : const Color(0xFFF1F5F9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              suffixIcon: IconButton(
                icon: const Icon(Icons.check_rounded),
                color: const Color(0xFF059669),
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  onSaved(controller.text);
                },
              ),
            ),
            onSubmitted: onSaved,
          ),
        ],
      ),
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({
    required this.label,
    required this.isDark,
    required this.icon,
  });

  final String label;
  final bool isDark;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final color =
        isDark ? TogetherTheme.amoledTextSecondary : TogetherTheme.ink;
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _SupportTile extends StatelessWidget {
  const _SupportTile({
    required this.isDark,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.url,
    this.isLast = false,
  });

  final bool isDark;
  final IconData icon;
  final String title;
  final String subtitle;
  final String url;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final titleColor =
        isDark ? TogetherTheme.amoledTextPrimary : TogetherTheme.deepOcean;
    final bodyColor =
        isDark ? TogetherTheme.amoledTextSecondary : TogetherTheme.ink;
    final dividerColor =
        isDark ? TogetherTheme.amoledBorder : const Color(0xFFDCE4EA);

    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: TogetherTheme.forest, size: 22),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: titleColor,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(fontSize: 13, color: bodyColor),
          ),
          trailing: Icon(Icons.chevron_right_rounded, color: bodyColor, size: 20),
          onTap: () async {
            final uri = Uri.parse(url);
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          },
        ),
        if (!isLast) Divider(height: 1, color: dividerColor),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.isDark, required this.child});

  final bool isDark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDark ? TogetherTheme.amoledSurface : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark
              ? TogetherTheme.amoledBorder
              : const Color(0xFFDCE4EA),
        ),
      ),
      child: child,
    );
  }
}

class _SettingToggle extends StatelessWidget {
  const _SettingToggle({
    required this.isDark,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final bool isDark;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final Future<void> Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    final tileColor = isDark ? TogetherTheme.amoledSurface : Colors.white;
    final borderColor =
        isDark ? TogetherTheme.amoledBorder : const Color(0xFFDCE4EA);
    final titleColor =
        isDark ? TogetherTheme.amoledTextPrimary : TogetherTheme.deepOcean;
    final subtitleColor =
        isDark ? TogetherTheme.amoledTextSecondary : TogetherTheme.ink;

    return Container(
      decoration: BoxDecoration(
        color: tileColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: isDark
              ? TogetherTheme.amoledSurfaceElevated
              : TogetherTheme.mist,
          foregroundColor: iconColor,
          child: Icon(icon),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: titleColor,
            fontFamily: 'RobotoSlab',
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: subtitleColor,
            ),
          ),
        ),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
        ),
        // Tapping anywhere on the tile also toggles.
        onTap: () => onChanged(!value),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.isDark,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final bool isDark;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final tileColor = isDark ? TogetherTheme.amoledSurface : Colors.white;
    final borderColor =
        isDark ? TogetherTheme.amoledBorder : const Color(0xFFDCE4EA);
    final titleColor =
        isDark ? TogetherTheme.amoledTextPrimary : TogetherTheme.deepOcean;
    final subtitleColor =
        isDark ? TogetherTheme.amoledTextSecondary : TogetherTheme.ink;

    return Container(
      decoration: BoxDecoration(
        color: tileColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: isDark
              ? TogetherTheme.amoledSurfaceElevated
              : TogetherTheme.mist,
          foregroundColor: iconColor,
          child: Icon(icon),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: titleColor,
            fontFamily: 'RobotoSlab',
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: subtitleColor,
            ),
          ),
        ),
        trailing: Icon(
          Icons.info_outline_rounded,
          color: subtitleColor,
          size: 20,
        ),
      ),
    );
  }
}
