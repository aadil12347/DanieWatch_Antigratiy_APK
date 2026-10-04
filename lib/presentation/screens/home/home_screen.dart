import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

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
import '../../../services/extraction/movie_site_scraper_service.dart';


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
      // Deferred from splash — request permissions after home is visible
      _requestPermissionsIfNeeded();
    });
  }

  /// Request Android permissions in background — deferred from splash for instant startup.
  Future<void> _requestPermissionsIfNeeded() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        final sdkInt = androidInfo.version.sdkInt;
        if (sdkInt >= 33) {
          await [Permission.notification, Permission.videos, Permission.photos].request();
        } else {
          await [Permission.notification, Permission.storage].request();
        }
      } catch (e) {
        debugPrint('[Home] Permission request error: $e');
      }
    }
  }

  @override
  void dispose() {
    _scrollManager.unregister(0);
    _scrollController.dispose();
    super.dispose();
  }

  /// All expected section titles in display order — used to show shimmer
  /// placeholders for sections that haven't loaded yet.
  static const _expectedSectionTitles = [
    'Top 10 Indian Today',
    'Top 10 Hindi Dub Today',
    'Korean',
    'Chinese',
    'Anime',
    'Action',
    'Sci-Fi',
    'Comedy',
    'Thriller',
    'Horror',
    'Romance',
  ];

  /// Builds the list of slivers for home sections.
  /// Shows loaded sections as real content, and only up to 2 shimmer
  /// placeholders for not-yet-loaded sections to keep GPU usage low.
  List<Widget> _buildProgressiveSections(
    List<ContentSection> sections,
    Set<String> loadedTitles,
  ) {
    final slivers = <Widget>[];
    int shimmerCount = 0;
    const maxShimmers = 2; // Only show 2 shimmer sections at a time

    for (final title in _expectedSectionTitles) {
      final loadedSection = loadedTitles.contains(title)
          ? sections.firstWhere((s) => s.title == title)
          : null;

      final isTop10Indian = title == 'Top 10 Indian Today';
      final isTop10HindiDub = title == 'Top 10 Hindi Dub Today';
      final isRankedSection = isTop10Indian || isTop10HindiDub;

      if (loadedSection != null) {
        // Real content — section has loaded
        Widget? headerTitleWidget;
        if (isTop10Indian) {
          headerTitleWidget = const TopTenTitle(topText: 'INDIAN', bottomText: 'TODAY');
        } else if (isTop10HindiDub) {
          headerTitleWidget = const TopTenTitle(topText: 'HINDI DUB', bottomText: 'TODAY');
        }

        slivers.add(SliverToBoxAdapter(
          child: RepaintBoundary(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  title: loadedSection.title,
                  titleWidget: headerTitleWidget,
                  showSeeAll: !isRankedSection,
                  onSeeAll: () => _handleSeeAll(loadedSection.title),
                ),
                ContentRow(
                  items: loadedSection.items,
                  isRanked: loadedSection.isRanked,
                  // Don't pass categorySlug on home — avoids triggering
                  // paginatedCategoryProvider which fires eager HTTP requests
                ),
              ],
            ),
          ),
        ));
      } else if (shimmerCount < maxShimmers) {
        // Only show a limited number of shimmer placeholders
        shimmerCount++;
        slivers.add(SliverToBoxAdapter(
          child: _ShimmerSection(
            title: isRankedSection ? null : title,
            isRanked: isRankedSection,
            rankedTopText: isTop10Indian ? 'INDIAN' : (isTop10HindiDub ? 'HINDI DUB' : null),
          ),
        ));
      }
      // Sections beyond maxShimmers that haven't loaded yet are simply not shown
    }

    return slivers;
  }

  @override
  Widget build(BuildContext context) {
    final homeSectionsAsync = ref.watch(homeSectionsProvider);
    final carouselAsync = ref.watch(mergedCarouselProvider);

    // Always render the scaffold — show shimmer placeholders for missing sections.
    // As the StreamProvider yields more data, sections replace shimmers one by one.
    final sections = homeSectionsAsync.valueOrNull ?? [];
    final carouselItems = carouselAsync.valueOrNull ?? [];

    return _buildHomeContent(sections, carouselItems);
  }

  Widget _buildHomeContent(
    List<ContentSection> sections,
    List<ManifestItem> carouselItems
  ) {
    // Build a lookup of loaded section titles for O(1) check
    final loadedTitles = <String>{for (final s in sections) s.title};

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
          child: RefreshIndicator(
            color: AppColors.primary,
            backgroundColor: AppColors.surfaceElevated,
            onRefresh: () async {
              MovieSiteScraperService.instance.clearCache();
              await MovieSiteScraperService.instance.loadDiskCache();
              ref.invalidate(mergedCarouselProvider);
              ref.invalidate(top10IndianProvider);
              ref.invalidate(top10HindiDubProvider);
              ref.invalidate(homeSectionsProvider);
              await ref.read(homeSectionsProvider.future);
            },
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              // PERF: Reduced from 800 to avoid pre-building off-screen shimmers
              cacheExtent: 200,
              slivers: [
                // Hero section: Header + Carousel (shimmer if empty)
                // RepaintBoundary prevents expensive gradient repaints
                // from cascading to the rest of the scroll view
                SliverToBoxAdapter(
                  child: RepaintBoundary(
                    child: _HeroGradientSection(
                      carouselItems: carouselItems,
                    ),
                  ),
                ),

                // Continue Watching row (always above Top 10)
                if (ref.watch(continueWatchingSettingsProvider))
                  const SliverToBoxAdapter(
                    child: ContinueWatchingRow(),
                  ),

                // Progressive sections: show loaded data OR shimmer placeholder
                // Only show shimmer for the first few unloaded sections to avoid
                // overwhelming the GPU with 50+ shimmer widgets at once.
                ..._buildProgressiveSections(sections, loadedTitles),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 80),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleSeeAll(String title) {
    String tabLabel = 'Explore';
    if (title == 'Korean' || title == 'K-Drama') {
      tabLabel = 'Korean';
    } else if (title == 'Chinese') {
      tabLabel = 'Chinese';
    } else if (title == 'Anime') {
      tabLabel = 'Anime';
    } else if (title == 'Action') {
      tabLabel = 'Action';
    } else if (title == 'Comedy') {
      tabLabel = 'Comedy';
    } else if (title == 'Thriller') {
      tabLabel = 'Thriller';
    } else if (title == 'Horror') {
      tabLabel = 'Horror';
    } else if (title == 'Sci-Fi') {
      tabLabel = 'Sci-Fi';
    } else if (title == 'Romance') {
      tabLabel = 'Romance';
    } else if (title == 'Indian' || title == 'Bollywood') {
      tabLabel = 'Indian';
    } else if (title == 'Hollywood') {
      tabLabel = 'Hollywood';
    } else if (title == 'Punjabi') {
      tabLabel = 'Punjabi';
    } else if (title == 'Pakistani') {
      tabLabel = 'Pakistani';
    }

    ref.read(searchProvider('explore').notifier).setNavCategory(tabLabel);
    context.go('/search');
  }
}


// NOTE: _LoadingHome, _ErrorHome, _EmptyHome removed — the progressive
// shimmer layout in _buildHomeContent now handles all loading states
// by showing shimmer placeholders that replace themselves with real content.

/// Shimmer placeholder for a section that hasn't loaded yet.
/// Shows a section header shimmer and a row of card-shaped shimmers.
class _ShimmerSection extends StatelessWidget {
  final String? title;
  final bool isRanked;
  final String? rankedTopText;

  const _ShimmerSection({
    this.title,
    this.isRanked = false,
    this.rankedTopText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header shimmer
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: title != null
                ? ShimmerBox(width: title!.length * 9.0 + 20, height: 18)
                : Row(
                    children: [
                      const ShimmerBox(width: 30, height: 28),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ShimmerBox(width: (rankedTopText?.length ?? 6) * 10.0, height: 11),
                          const SizedBox(height: 3),
                          const ShimmerBox(width: 44, height: 11),
                        ],
                      ),
                    ],
                  ),
          ),
          // Card row shimmer
          SizedBox(
            height: isRanked ? 180 : 170,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 5,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, __) => ShimmerBox(
                width: isRanked ? 130 : 115,
                height: isRanked ? 180 : 170,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shimmer placeholder for the hero carousel area while it loads.
class _CarouselShimmer extends StatelessWidget {
  const _CarouselShimmer();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: AspectRatio(
        aspectRatio: 2 / 2.6,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Background card shimmers (slightly offset)
            Positioned(
              left: 30,
              right: 30,
              top: 20,
              bottom: 10,
              child: ShimmerBox(
                width: double.infinity,
                height: double.infinity,
                borderRadius: 16,
              ),
            ),
            Positioned(
              left: 15,
              right: 15,
              top: 10,
              bottom: 5,
              child: ShimmerBox(
                width: double.infinity,
                height: double.infinity,
                borderRadius: 18,
              ),
            ),
            // Front card shimmer
            ShimmerBox(
              width: double.infinity,
              height: double.infinity,
              borderRadius: 20,
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
            // Carousel (or shimmer placeholder while loading)
            if (carouselItems.isNotEmpty)
              StackedCarousel(items: carouselItems)
            else
              const _CarouselShimmer(),
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

        // Single gradient layer — much cheaper than 2 stacked gradients
        return RepaintBoundary(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.65),
                  color.withValues(alpha: 0.25),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
        );
      },
    );
  }
}
