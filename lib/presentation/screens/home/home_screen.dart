import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../../../core/utils/responsive.dart';
import '../../../domain/models/manifest_item.dart';
import '../../providers/manifest_provider.dart';
import '../../providers/search_provider.dart';
import '../../widgets/content_row.dart';
import '../../widgets/stacked_carousel.dart';
import '../../widgets/section_header.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/custom_drawer.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/continue_watching_row.dart';
import '../../providers/auth_provider.dart';
import '../../providers/watch_history_provider.dart';
import '../../providers/delete_mode_provider.dart';
import '../../providers/notification_inbox_provider.dart';

import '../../providers/scroll_provider.dart';
import '../../providers/poster_color_provider.dart';
import '../../../core/services/poster_color_service.dart';


class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final ScrollController _scrollController = ScrollController();
  late final ScrollControllerManager _scrollManager;

  @override
  void initState() {
    super.initState();
    _scrollManager = ref.read(scrollProvider);
    // Register the controller with the global manager
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollManager.register(0, _scrollController);
    });
  }

  @override
  void dispose() {
    _scrollManager.unregister(0);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final homeSectionsAsync = ref.watch(homeSectionsDataProvider);
    final sectionsAsync = ref.watch(homeSectionsProvider);
    final carouselAsync = ref.watch(mergedCarouselProvider);

    return homeSectionsAsync.when(
      loading: () => homeSectionsAsync.hasValue ? _buildHomeContent(homeSectionsAsync.value, sectionsAsync, carouselAsync) : const _LoadingHome(),
      error: (e, _) => homeSectionsAsync.hasValue ? _buildHomeContent(homeSectionsAsync.value, sectionsAsync, carouselAsync) : _ErrorHome(error: e.toString()),
      data: (data) {
        if (data == null || (data.carousel.isEmpty && data.sections.isEmpty)) {
          return const _EmptyHome();
        }
        return _buildHomeContent(data, sectionsAsync, carouselAsync);
      },
    );
  }

  Widget _buildHomeContent(
    dynamic manifest,
    AsyncValue<List<ContentSection>> sectionsAsync,
    AsyncValue<List<ManifestItem>> carouselAsync
  ) {
    final carouselItems = carouselAsync.valueOrNull ?? [];
    final sections = sectionsAsync.valueOrNull ?? [];


    return Scaffold(
      backgroundColor: Colors.transparent,
      drawer: const CustomDrawer(),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // Exit delete mode if user clicks anywhere on the screen
          final isDeleteMode = ref.read(continueWatchingDeleteModeProvider);
          if (isDeleteMode) {
            ref.read(continueWatchingDeleteModeProvider.notifier).state = false;
          }
        },
        child: CustomAppBar(
          child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Hero section: Header + Carousel with gradient emitting from active card
            SliverToBoxAdapter(
              child: _HeroGradientSection(
                carouselItems: carouselItems,
              ),
            ),

            // Content sections with Continue Watching inserted ABOVE Top 10
            ...sections.expand((section) {
              final isTop10 = section.title == 'Top 10 Today';
              
              final sectionWidget = SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(
                      title: section.title,
                      titleWidget: isTop10 ? const TopTenTitle() : null,
                      showSeeAll: !isTop10,
                      onSeeAll: () => _handleSeeAll(section.title),
                    ),
                    ContentRow(
                      items: section.items,
                      isRanked: section.isRanked,
                    ),
                  ],
                ),
              );

              // Insert Continue Watching row right ABOVE Top 10
              if (isTop10) {
                final historyEnabled = ref.watch(continueWatchingSettingsProvider);
                if (historyEnabled) {
                  return [
                    const SliverToBoxAdapter(
                      child: ContinueWatchingRow(),
                    ),
                    sectionWidget,
                  ];
                } else {
                  return [sectionWidget];
                }
              }
              return [sectionWidget];
            }),

            const SliverToBoxAdapter(
              child: SizedBox(height: 80),
            ),
          ],
        ),
        ),
      ),
    );
  }

  void _handleSeeAll(String title) {
    SearchFilters filters = const SearchFilters();

    if (title == 'Top 10 Today' || title == 'Trending Now') {
      filters = filters.copyWith(sortBy: 'Popularity');
    } else if (title == 'Top Rated') {
      filters = filters.copyWith(sortBy: 'Latest Release');
    } else if (title == 'Anime') {
      filters = filters.copyWith(categories: {'Anime'});
    } else if (title == 'Korean') {
      filters = filters.copyWith(categories: {'K-Drama'});
    } else {
      // Possible genre
      filters = filters.copyWith(genres: {title});
    }

    ref.read(searchProvider('explore').notifier).updateFilters(filters);
    context.go('/search');
  }
}

class _LoadingHome extends StatelessWidget {
  const _LoadingHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 60),
            // Hero shimmer
            const ShimmerBox(width: double.infinity, height: 220),
            const SizedBox(height: 24),
            // Section shimmers
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ShimmerBox(width: 120, height: 18),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 180,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: 5,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, __) =>
                          const ShimmerBox(width: 120, height: 180),
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

class _ErrorHome extends StatelessWidget {
  final String error;
  const _ErrorHome({required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 64, color: AppColors.textMuted),
              const SizedBox(height: 16),
              Text(
                'Something went wrong',
                style: GoogleFonts.lora(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyHome extends StatelessWidget {
  const _EmptyHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.movie_outlined,
                size: 64, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              'No content available',
              style: GoogleFonts.lora(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hero section: header + carousel wrapped in a radial gradient that
/// emits from the active carousel card and scrolls with the content.
class _HeroGradientSection extends ConsumerWidget {
  final List<ManifestItem> carouselItems;
  const _HeroGradientSection({required this.carouselItems});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(activeGradientProvider);
    final r = Responsive(context);

    return Stack(
      children: [
        // Radial gradient background emitting from carousel center
        Positioned.fill(
          child: _CarouselGradientBg(palette: palette),
        ),
        // Fade-to-black at the bottom edge
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 120,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black],
              ),
            ),
          ),
        ),
        // Actual content
        Column(
          children: [
            // Personalized Header
            Padding(
              padding: EdgeInsets.fromLTRB(r.w(16), r.h(44), r.w(16), r.h(8)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => context.push('/profile'),
                    child: Row(
                      children: [
                        Hero(
                          tag: 'profile-avatar',
                          child: UserAvatar(
                              size: r.d(48).clamp(40.0, 60.0), canEdit: false),
                        ),
                        SizedBox(width: r.w(16)),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Hello,',
                                style: GoogleFonts.inter(
                                    color: AppColors.textMuted,
                                    fontSize: r.f(13).clamp(11.0, 16.0),
                                    fontWeight: FontWeight.w500,
                                    height: 1.1)),
                            ref.watch(profileProvider).when(
                                  data: (profile) => Text(
                                    profile?.username ?? 'User',
                                    style: GoogleFonts.lora(
                                        color: AppColors.textPrimary,
                                        fontSize: r.f(18).clamp(14.0, 24.0),
                                        fontWeight: FontWeight.w500,
                                        height: 1.2),
                                  ),
                                  loading: () => const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                  error: (_, __) => Text(
                                    'User',
                                    style: GoogleFonts.lora(
                                        color: AppColors.textPrimary,
                                        fontSize: r.f(18).clamp(14.0, 24.0),
                                        fontWeight: FontWeight.w500,
                                        height: 1.2),
                                  ),
                                ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.push('/notifications'),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(Icons.notifications_none_rounded,
                            size: r.d(28).clamp(22.0, 34.0),
                            color: Colors.white),
                        Consumer(
                          builder: (context, ref, _) {
                            final unread = ref.watch(unreadCountProvider);
                            if (unread == 0) return const SizedBox.shrink();
                            return Positioned(
                              right: -4,
                              top: -4,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFE91E63),
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(
                                    minWidth: 18, minHeight: 18),
                                child: Text(
                                  unread > 9 ? '9+' : '$unread',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Carousel
            if (carouselItems.isNotEmpty)
              StackedCarousel(items: carouselItems),
            // Extra padding so gradient extends a bit below carousel
            const SizedBox(height: 12),
          ],
        ),
      ],
    );
  }
}

/// Animated radial gradient that emits from the carousel center.
/// Smoothly transitions colors when the active carousel item changes.
class _CarouselGradientBg extends StatefulWidget {
  final PosterColorPalette palette;
  const _CarouselGradientBg({required this.palette});

  @override
  State<_CarouselGradientBg> createState() => _CarouselGradientBgState();
}

class _CarouselGradientBgState extends State<_CarouselGradientBg>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _curve;
  late ColorTween _colorTween;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _colorTween = ColorTween(
      begin: widget.palette.primary,
      end: widget.palette.primary,
    );
    _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(_CarouselGradientBg old) {
    super.didUpdateWidget(old);
    if (old.palette.primary != widget.palette.primary) {
      _colorTween = ColorTween(
        begin: _colorTween.evaluate(_curve),
        end: widget.palette.primary,
      );
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, _) {
        final color = _colorTween.evaluate(_curve) ?? widget.palette.primary;

        return Stack(
          children: [
            // Layer 1: Full vertical gradient — strong color at top, fading to black
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      color.withValues(alpha: 0.7),
                      color.withValues(alpha: 0.45),
                      color.withValues(alpha: 0.2),
                      color.withValues(alpha: 0.05),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                  ),
                ),
              ),
            ),
            // Layer 2: Radial glow emitting from carousel center
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.0, 0.35),
                    radius: 1.0,
                    colors: [
                      color.withValues(alpha: 0.6),
                      color.withValues(alpha: 0.3),
                      color.withValues(alpha: 0.08),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.3, 0.6, 1.0],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
