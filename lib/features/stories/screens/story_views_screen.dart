import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rojava/data/model/story_model.dart';
import 'package:video_player/video_player.dart';
import '../../../core/config/supabase_config.dart';
import '../controllers/story_controller.dart';

class StoryViewerScreen extends ConsumerStatefulWidget {
  final List<StoryModel> stories;
  final int initialIndex;

  const StoryViewerScreen({
    Key? key,
    required this.stories,
    this.initialIndex = 0,
  }) : super(key: key);

  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends ConsumerState<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _animationController;
  int _currentIndex = 0;
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _animationController = AnimationController(vsync: this);
    _loadStory(_currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animationController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _loadStory(int index) {
    final story = widget.stories[index];
    ref.read(storyControllerProvider.notifier).markAsViewed(story.id);

    if (story.mediaType == 'video') {
      _videoController?.dispose();
      _videoController = VideoPlayerController.network(story.mediaUrl)
        ..initialize().then((_) {
          if (mounted) setState(() {});
          _videoController!.play();
          _startTimer(_videoController!.value.duration);
        });
    } else {
      _startTimer(const Duration(seconds: 5));
    }
  }

  void _startTimer(Duration duration) {
    _animationController.duration = duration;
    _animationController.forward(from: 0).then((_) {
      if (mounted) _nextStory();
    });
  }

  void _nextStory() {
    if (_currentIndex < widget.stories.length - 1) {
      setState(() => _currentIndex++);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      _loadStory(_currentIndex);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _previousStory() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      _loadStory(_currentIndex);
    }
  }

  void _pauseStory() {
    _animationController.stop();
    _videoController?.pause();
  }

  void _resumeStory() {
    _animationController.forward();
    _videoController?.play();
  }

  bool _isMyStory(String userId) =>
      SupabaseConfig.auth.currentUser?.id == userId;

  void _showViewersSheet(String storyId) {
    _pauseStory();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ViewersSheet(storyId: storyId),
    ).then((_) => _resumeStory());
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.stories[_currentIndex];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTapDown: (details) {
            final w = MediaQuery.of(context).size.width;
            if (details.globalPosition.dx < w / 2) {
              _previousStory();
            } else {
              _nextStory();
            }
          },
          onLongPressStart: (_) => _pauseStory(),
          onLongPressEnd: (_) => _resumeStory(),
          child: Stack(
            children: [
              // ── Story media ──────────────────────────────────────────────
              PageView.builder(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: widget.stories.length,
                itemBuilder: (_, index) {
                  final s = widget.stories[index];
                  return Center(
                    child: s.mediaType == 'video'
                        ? (_videoController != null &&
                                  _videoController!.value.isInitialized
                              ? AspectRatio(
                                  aspectRatio:
                                      _videoController!.value.aspectRatio,
                                  child: VideoPlayer(_videoController!),
                                )
                              : const CircularProgressIndicator(
                                  color: Colors.white,
                                ))
                        : Image.network(
                            s.mediaUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            loadingBuilder: (_, child, progress) =>
                                progress == null
                                ? child
                                : const Center(
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                  );
                },
              ),

              // ── Top gradient ─────────────────────────────────────────────
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 120,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.55),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // ── Bottom gradient ──────────────────────────────────────────
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 160,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.6),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // ── Top bar: progress + user info + close ────────────────────
              SafeArea(
                child: Column(
                  children: [
                    // Progress bars
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: Row(
                        children: List.generate(widget.stories.length, (i) {
                          return Expanded(
                            child: Container(
                              height: 2.5,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              child: AnimatedBuilder(
                                animation: _animationController,
                                builder: (_, __) => LinearProgressIndicator(
                                  value: i == _currentIndex
                                      ? _animationController.value
                                      : i < _currentIndex
                                      ? 1.0
                                      : 0.0,
                                  backgroundColor: Colors.white.withOpacity(
                                    0.3,
                                  ),
                                  valueColor: const AlwaysStoppedAnimation(
                                    Colors.white,
                                  ),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // User row
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          // Avatar
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                            ),
                            child: ClipOval(
                              child: story.userAvatar != null
                                  ? Image.network(
                                      story.userAvatar!,
                                      fit: BoxFit.cover,
                                    )
                                  : Container(
                                      color: Colors.white24,
                                      child: const Icon(
                                        Icons.person,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  story.userName ?? 'Unknown',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                Text(
                                  _getTimeAgo(story.createdAt),
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.65),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Close
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Caption ──────────────────────────────────────────────────
              if (story.caption != null && story.caption!.isNotEmpty)
                Positioned(
                  bottom: _isMyStory(story.userId) ? 90 : 40,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.45),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      story.caption!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),

              // ── Snapchat-style viewers button at bottom ──────────────────
              if (_isMyStory(story.userId))
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    top: false,
                    child: GestureDetector(
                      onTap: () => _showViewersSheet(story.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.keyboard_arrow_up_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                            const SizedBox(width: 6),
                            _ViewCountBadge(storyId: story.id),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ── View count badge (live) ────────────────────────────────────────────────────

class _ViewCountBadge extends StatefulWidget {
  final String storyId;
  const _ViewCountBadge({required this.storyId});

  @override
  State<_ViewCountBadge> createState() => _ViewCountBadgeState();
}

class _ViewCountBadgeState extends State<_ViewCountBadge> {
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await SupabaseConfig.client
          .from('story_views')
          .select('viewer_id')
          .eq('story_id', widget.storyId);
      final ids = <String>{};
      for (final r in (res as List)) {
        ids.add(r['viewer_id'] as String);
      }
      if (mounted) setState(() => _count = ids.length);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.remove_red_eye_rounded, color: Colors.white, size: 17),
        const SizedBox(width: 6),
        Text(
          '$_count viewer${_count == 1 ? '' : 's'}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}

// ── Viewers Bottom Sheet ───────────────────────────────────────────────────────

class _ViewersSheet extends StatefulWidget {
  final String storyId;
  const _ViewersSheet({required this.storyId});

  @override
  State<_ViewersSheet> createState() => _ViewersSheetState();
}

class _ViewersSheetState extends State<_ViewersSheet>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _viewers = [];
  bool _isLoading = true;
  late AnimationController _stagger;

  @override
  void initState() {
    super.initState();
    _stagger = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _loadViewers();
  }

  @override
  void dispose() {
    _stagger.dispose();
    super.dispose();
  }

  Future<void> _loadViewers() async {
    try {
      // Fetch views
      final viewsRes = await SupabaseConfig.client
          .from('story_views')
          .select('viewer_id, viewed_at')
          .eq('story_id', widget.storyId)
          .order('viewed_at', ascending: false);

      final list = List<Map<String, dynamic>>.from(viewsRes as List);

      // Deduplicate
      final seen = <String>{};
      final deduped = <Map<String, dynamic>>[];
      for (final v in list) {
        if (seen.add(v['viewer_id'] as String? ?? '')) deduped.add(v);
      }

      // Enrich with profiles
      final enriched = <Map<String, dynamic>>[];
      for (final v in deduped) {
        final vid = v['viewer_id'] as String? ?? '';
        Map<String, dynamic>? profile;
        try {
          profile = await SupabaseConfig.client
              .from('profiles')
              .select('full_name, avatar_url')
              .eq('id', vid)
              .maybeSingle();
        } catch (_) {}
        enriched.add({
          'viewer_id': vid,
          'viewed_at': v['viewed_at'],
          'full_name': profile?['full_name'] ?? 'Unknown',
          'avatar_url': profile?['avatar_url'],
        });
      }

      if (mounted) {
        setState(() {
          _viewers = enriched;
          _isLoading = false;
        });
        _stagger.forward();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _timeAgo(String str) {
    try {
      final diff = DateTime.now().difference(DateTime.parse(str).toLocal());
      if (diff.inSeconds < 60) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }

  Color _color(String name) {
    const p = [
      Color(0xFF3B82F6),
      Color(0xFFEC4899),
      Color(0xFF10B981),
      Color(0xFFF59E0B),
      Color(0xFF8B5CF6),
      Color(0xFFEF4444),
      Color(0xFF06B6D4),
    ];
    return name.isNotEmpty ? p[name.codeUnitAt(0) % p.length] : p[0];
  }

  String _initials(String name) {
    final parts = name.trim().split(' ').where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.72;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: const BoxDecoration(
        color: Color(0xFF111118),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),

          // Title row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text(
                  'Viewed by',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                const Spacer(),
                if (!_isLoading)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.remove_red_eye_rounded,
                          size: 13,
                          color: Colors.white54,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${_viewers.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Content
          Flexible(
            child: _isLoading
                ? const _SheetShimmer()
                : _viewers.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(48),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.visibility_off_outlined,
                          size: 40,
                          color: Colors.white.withOpacity(0.2),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'No views yet',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
                    shrinkWrap: true,
                    itemCount: _viewers.length,
                    itemBuilder: (_, i) {
                      final v = _viewers[i];
                      final name = v['full_name'] as String? ?? 'Unknown';
                      final avatarUrl = v['avatar_url'] as String?;
                      final viewedAt = v['viewed_at'] as String? ?? '';
                      final c = _color(name);

                      final start = (i * 0.1).clamp(0.0, 0.8);
                      final end = (start + 0.4).clamp(0.0, 1.0);
                      final anim = CurvedAnimation(
                        parent: _stagger,
                        curve: Interval(start, end, curve: Curves.easeOutCubic),
                      );

                      return AnimatedBuilder(
                        animation: anim,
                        builder: (_, child) => Opacity(
                          opacity: anim.value,
                          child: Transform.translate(
                            offset: Offset(0, 12 * (1 - anim.value)),
                            child: child,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              // Avatar
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: c.withOpacity(0.18),
                                ),
                                child: avatarUrl != null
                                    ? ClipOval(
                                        child: Image.network(
                                          avatarUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Center(
                                            child: Text(
                                              _initials(name),
                                              style: TextStyle(
                                                color: c,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15,
                                              ),
                                            ),
                                          ),
                                        ),
                                      )
                                    : Center(
                                        child: Text(
                                          _initials(name),
                                          style: TextStyle(
                                            color: c,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 14),
                              // Name + time
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      viewedAt.isNotEmpty
                                          ? _timeAgo(viewedAt)
                                          : '',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.38),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Eye icon
                              Icon(
                                Icons.remove_red_eye_outlined,
                                size: 16,
                                color: Colors.white.withOpacity(0.25),
                              ),
                            ],
                          ),
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

// ── Sheet shimmer ──────────────────────────────────────────────────────────────

class _SheetShimmer extends StatefulWidget {
  const _SheetShimmer();

  @override
  State<_SheetShimmer> createState() => _SheetShimmerState();
}

class _SheetShimmerState extends State<_SheetShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _a = CurvedAnimation(parent: _c, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (_, __) {
        final s = Color.lerp(
          const Color(0xFF1E1E2A),
          const Color(0xFF28283A),
          _a.value,
        )!;
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          itemCount: 5,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: s),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 13,
                        width: 100.0 + i * 18,
                        decoration: BoxDecoration(
                          color: s,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 11,
                        width: 55,
                        decoration: BoxDecoration(
                          color: s.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
