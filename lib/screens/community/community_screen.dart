import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/app_settings_service.dart';
import '../../theme/app_theme.dart';

// ── Post types ────────────────────────────────────────────────────────────────

enum PostType { announcement, job, course, event, news, tip, sponsored }

extension PostTypeX on PostType {
  String get label => switch (this) {
        PostType.announcement => 'Announcement',
        PostType.job => 'Job',
        PostType.course => 'Course',
        PostType.event => 'Event',
        PostType.news => 'News',
        PostType.tip => 'Tip',
        PostType.sponsored => 'Sponsored',
      };

  IconData get icon => switch (this) {
        PostType.announcement => Icons.campaign_rounded,
        PostType.job => Icons.work_rounded,
        PostType.course => Icons.school_rounded,
        PostType.event => Icons.event_rounded,
        PostType.news => Icons.article_rounded,
        PostType.tip => Icons.tips_and_updates_rounded,
        PostType.sponsored => Icons.verified_rounded,
      };
}

// ── Data model ────────────────────────────────────────────────────────────────

class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.publishedAt,
    this.tag,
    this.sourceName,
    this.actionLabel,
    this.actionUrl,
    this.meta,
  });

  final String id;
  final PostType type;
  final String title;
  final String body;
  final DateTime publishedAt;
  final String? tag;
  final String? sourceName;
  final String? actionLabel;
  final String? actionUrl;
  final String? meta;

  factory CommunityPost.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final rawType = d['type'] as String? ?? 'tip';
    final type = PostType.values.firstWhere(
      (t) => t.name == rawType,
      orElse: () => PostType.tip,
    );
    final ts = d['publishedAt'];
    final publishedAt = ts is Timestamp
        ? ts.toDate()
        : DateTime.now();
    return CommunityPost(
      id: doc.id,
      type: type,
      title: d['title'] as String? ?? '',
      body: d['body'] as String? ?? '',
      publishedAt: publishedAt,
      tag: d['tag'] as String?,
      sourceName: d['sourceName'] as String?,
      actionLabel: d['actionLabel'] as String?,
      actionUrl: d['actionUrl'] as String?,
      meta: d['meta'] as String?,
    );
  }

  static Stream<List<CommunityPost>> stream() =>
      FirebaseFirestore.instanceFor(
              app: Firebase.app(), databaseId: 'users')
          .collection('community_posts')
          .where('active', isEqualTo: true)
          .orderBy('pinned', descending: true)
          .orderBy('publishedAt', descending: true)
          .snapshots()
          .map((s) => s.docs.map(CommunityPost.fromFirestore).toList());

  // Tips are always local — shown regardless of connectivity.
  static final List<CommunityPost> localTips = [
    CommunityPost(
      id: 'tip-1',
      type: PostType.tip,
      title: 'Keep your SOS card updated',
      body: 'First responders rely on your SOS card in emergencies. Review your blood type, allergies, and emergency contacts every three months — it takes under two minutes.',
      publishedAt: DateTime(2026, 4, 12),
      sourceName: 'Together Team',
      tag: 'Safety tip',
    ),
    CommunityPost(
      id: 'tip-2',
      type: PostType.tip,
      title: 'Save 112 in your phone contacts',
      body: 'Store the national emergency number (112) under a name like "ICE — Emergency" so rescuers can find it on your lock screen without needing your PIN.',
      publishedAt: DateTime(2026, 4, 2),
      sourceName: 'Together Team',
      tag: 'Safety tip',
    ),
    CommunityPost(
      id: 'tip-3',
      type: PostType.tip,
      title: 'Enable low-battery mode when charging is unavailable',
      body: 'Together\'s AMOLED low-battery mode reduces screen energy use significantly on OLED displays. Turn it on in Profile → Accessibility when you cannot charge your phone.',
      publishedAt: DateTime(2026, 3, 28),
      sourceName: 'Together Team',
      tag: 'App tip',
    ),
    CommunityPost(
      id: 'tip-4',
      type: PostType.tip,
      title: 'Tell someone your offline meeting point',
      body: 'Before travelling to crowded events or unfamiliar areas, agree on a physical meeting point with your companions — somewhere reachable even without a phone signal.',
      publishedAt: DateTime(2026, 3, 20),
      sourceName: 'Together Team',
      tag: 'Preparedness tip',
    ),
    CommunityPost(
      id: 'tip-5',
      type: PostType.tip,
      title: 'Use Emergency Comms when the internet is down',
      body: 'The Emergency Comms screen connects you to nearby Together users via Bluetooth — no internet, no SIM card needed. Start it before you lose signal, not after.',
      publishedAt: DateTime(2026, 3, 14),
      sourceName: 'Together Team',
      tag: 'App tip',
    ),
  ];
}

// ── Screen ────────────────────────────────────────────────────────────────────

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  PostType? _filter;

  List<CommunityPost> _applyFilter(List<CommunityPost> posts) => _filter == null
      ? posts
      : posts.where((p) => p.type == _filter).toList();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final isDark = AppSettings.instance.lowBattery;
    final bg = isDark ? Colors.black : const Color(0xFFF4F7FA);
    final barBg = isDark ? TogetherTheme.amoledSurface : Colors.white;
    final titleColor =
        isDark ? TogetherTheme.amoledTextPrimary : TogetherTheme.deepOcean;
    final subtitleColor =
        isDark ? TogetherTheme.amoledTextSecondary : TogetherTheme.ink;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: barBg,
        foregroundColor: titleColor,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Community',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                fontFamily: 'RobotoSlab',
                color: titleColor,
              ),
            ),
            Text(
              'Jobs · Courses · Safety news · Tips',
              style: TextStyle(fontSize: 11, color: subtitleColor),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Filter chips ─────────────────────────────────────────────────
          Container(
            color: barBg,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: _filter == null,
                    isDark: isDark,
                    onTap: () => setState(() => _filter = null),
                  ),
                  const SizedBox(width: 8),
                  ...PostType.values
                      .where((t) => t != PostType.sponsored)
                      .map((t) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _FilterChip(
                              label: t.label,
                              selected: _filter == t,
                              isDark: isDark,
                              onTap: () => setState(
                                  () => _filter = _filter == t ? null : t),
                            ),
                          )),
                ],
              ),
            ),
          ),

          // ── Feed ─────────────────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<List<CommunityPost>>(
              stream: CommunityPost.stream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final isOffline = snapshot.hasError;
                final firestorePosts = snapshot.data ?? [];

                // Firestore posts + local tips always appended.
                // Deduplicate by title — the old Node.js seeder may have
                // written the same content with auto-generated IDs before
                // the in-app seeder used explicit IDs, leaving doubles.
                final seen = <String>{};
                final merged = [
                  ...firestorePosts,
                  ...CommunityPost.localTips,
                ].where((p) => seen.add(p.title)).toList();

                final posts = _applyFilter(merged);

                if (posts.isEmpty) {
                  return Center(
                    child: Text(
                      'No posts in this category yet.',
                      style: TextStyle(color: subtitleColor),
                    ),
                  );
                }

                // Banner slot prepended only when Firestore is unreachable.
                final bannerOffset = isOffline ? 1 : 0;
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  itemCount: posts.length + bannerOffset,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    if (isOffline && i == 0) {
                      return _OfflineBanner(
                          isDark: isDark, subtitleColor: subtitleColor);
                    }
                    return _PostCard(
                      post: posts[i - bannerOffset],
                      isDark: isDark,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Offline banner ────────────────────────────────────────────────────────────

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.isDark, required this.subtitleColor});

  final bool isDark;
  final Color subtitleColor;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF1A1A0A) : const Color(0xFFFEF9C3);
    final border = isDark ? const Color(0xFF3A3A00) : const Color(0xFFFDE68A);
    final textColor = isDark ? const Color(0xFFFBBF24) : const Color(0xFF92400E);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 16, color: textColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Showing local content — connect to load live posts.',
              style: TextStyle(fontSize: 12, color: textColor),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Filter chip ───────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeColor = TogetherTheme.forest;
    final bg = selected
        ? (isDark ? const Color(0xFF052E16) : const Color(0xFFD1FAE5))
        : (isDark ? TogetherTheme.amoledSurface : Colors.white);
    final border = selected
        ? activeColor
        : (isDark ? TogetherTheme.amoledBorder : const Color(0xFFD3DCE4));

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected
                ? activeColor
                : (isDark
                    ? TogetherTheme.amoledTextSecondary
                    : TogetherTheme.ink),
          ),
        ),
      ),
    );
  }
}

// ── Post card ─────────────────────────────────────────────────────────────────

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post, required this.isDark});

  final CommunityPost post;
  final bool isDark;

  // Per-type accent colours
  static const _colours = {
    PostType.announcement: (Color(0xFF1D4ED8), Color(0xFFEFF6FF), Color(0xFFDBEAFE)),
    PostType.job: (Color(0xFF0369A1), Color(0xFFE0F2FE), Color(0xFFBAE6FD)),
    PostType.course: (Color(0xFF7C3AED), Color(0xFFEDE9FE), Color(0xFFDDD6FE)),
    PostType.event: (Color(0xFFD97706), Color(0xFFFEF3C7), Color(0xFFFDE68A)),
    PostType.news: (Color(0xFF374151), Color(0xFFF9FAFB), Color(0xFFE5E7EB)),
    PostType.tip: (Color(0xFF059669), Color(0xFFD1FAE5), Color(0xFFA7F3D0)),
    PostType.sponsored: (Color(0xFF6B7280), Color(0xFFF9FAFB), Color(0xFFE5E7EB)),
  };

  (Color accent, Color bg, Color border) _palette(PostType type) {
    if (isDark) {
      return switch (type) {
        PostType.announcement => (const Color(0xFF60A5FA), const Color(0xFF0F172A), const Color(0xFF1E3A5F)),
        PostType.job => (const Color(0xFF38BDF8), const Color(0xFF0F172A), const Color(0xFF0C4A6E)),
        PostType.course => (const Color(0xFFA78BFA), const Color(0xFF0F172A), const Color(0xFF2E1065)),
        PostType.event => (const Color(0xFFFBBF24), const Color(0xFF0F172A), const Color(0xFF451A03)),
        PostType.news => (TogetherTheme.amoledTextSecondary, TogetherTheme.amoledSurface, TogetherTheme.amoledBorder),
        PostType.tip => (const Color(0xFF34D399), const Color(0xFF052E16), const Color(0xFF065F46)),
        PostType.sponsored => (TogetherTheme.amoledTextSecondary, TogetherTheme.amoledSurface, TogetherTheme.amoledBorder),
      };
    }
    final c = _colours[type]!;
    return (c.$1, c.$2, c.$3);
  }

  @override
  Widget build(BuildContext context) {
    final (accent, bg, border) = _palette(post.type);
    final textColor =
        isDark ? TogetherTheme.amoledTextPrimary : TogetherTheme.deepOcean;
    final bodyColor =
        isDark ? TogetherTheme.amoledTextSecondary : TogetherTheme.ink;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ──────────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(post.type.icon, size: 18, color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _TypeBadge(label: post.type.label, color: accent),
                          if (post.type == PostType.sponsored) ...[
                            const SizedBox(width: 6),
                            _TypeBadge(
                              label: 'Sponsored',
                              color: bodyColor,
                              subtle: true,
                            ),
                          ],
                        ],
                      ),
                      if (post.sourceName != null)
                        Text(
                          post.sourceName!,
                          style: TextStyle(
                            fontSize: 11,
                            color: bodyColor,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  _formatDate(post.publishedAt),
                  style: TextStyle(fontSize: 11, color: bodyColor),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Title ───────────────────────────────────────────────────
            Text(
              post.title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                fontFamily: 'RobotoSlab',
                color: textColor,
                height: 1.3,
              ),
            ),

            const SizedBox(height: 6),

            // ── Body ────────────────────────────────────────────────────
            Text(
              post.body,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: bodyColor,
              ),
            ),

            // ── Meta (job location, course duration etc.) ────────────────
            if (post.meta != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 13, color: accent),
                  const SizedBox(width: 4),
                  Text(
                    post.meta!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ],

            // ── Tag ─────────────────────────────────────────────────────
            if (post.tag != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.15 : 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  post.tag!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
              ),
            ],

            // ── Action button ────────────────────────────────────────────
            if (post.actionLabel != null && post.actionUrl != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _launch(context, post.actionUrl!),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    side: BorderSide(color: accent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Text(
                    post.actionLabel!,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return '$diff days ago';
    return '${d.day}/${d.month}/${d.year}';
  }

  Future<void> _launch(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the link.')),
        );
      }
    }
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({
    required this.label,
    required this.color,
    this.subtle = false,
  });

  final String label;
  final Color color;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
        color: subtle ? color.withValues(alpha: 0.5) : color,
      ),
    );
  }
}
