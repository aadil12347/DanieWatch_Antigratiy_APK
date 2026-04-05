import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:daniewatch_app/core/theme/app_theme.dart';
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
import '../../providers/auth_provider.dart';

import '../../providers/scroll_provider.dart';

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
    final manifestAsync = ref.watch(manifestProvider);
    final sectionsAsync = ref.watch(homeSectionsProvider);
    final trendingAsync = ref.watch(trendingProvider);

    return manifestAsync.when(
      loading: () => manifestAsync.hasValue ? _buildHomeContent(manifestAsync.value!, sectionsAsync, trendingAsync) : const _LoadingHome(),
      error: (e, _) => manifestAsync.hasValue ? _buildHomeContent(manifestAsync.value!, sectionsAsync, trendingAsync) : _ErrorHome(error: e.toString()),
      data: (manifest) {
        if (manifest == null || manifest.items.isEmpty) {
          return const _EmptyHome();
        }
        return _buildHomeContent(manifest, sectionsAsync, trendingAsync);
      },
    );
  }

  Widget _buildHomeContent(
    dynamic manifest,
    AsyncValue<List<ContentSection>> sectionsAsync,
    AsyncValue<List<ManifestItem>> trendingAsync
  ) {
    final trending = trendingAsync.valueOrNull ?? [];
    final sections = sectionsAsync.valueOrNull ?? [];

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const CustomDrawer(),
      body: CustomAppBar(
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Personalized Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 44, 16, 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => context.push('/profile'),
                      child: Row(
                        children: [
                          const Hero(
                            tag: 'profile-avatar',
                            child: UserAvatar(size: 60, canEdit: false),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Hello,',
                                  style: GoogleFonts.inter(
                                      color: AppColors.textMuted,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      height: 1.1)),
                              ref.watch(profileProvider).when(
                                    data: (profile) => Text(
                                      profile?.username ?? 'User',
                                      style: GoogleFonts.lora(
                                          color: AppColors.textPrimary,
                                          fontSize: 24,
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
                                          fontSize: 24,
                                          fontWeight: FontWeight.w500,
                                          height: 1.2),
                                    ),
                                  ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.notifications_none_rounded,
                        size: 28, color: Colors.white),
                  ],
                ),
              ),
            ),

            // Content sections
            if (trending.isNotEmpty)
              SliverToBoxAdapter(
                child: StackedCarousel(items: trending),
              ),

            // Content sections
            ...sections.map((section) {
              final isTop10 = section.title == 'Top 10 Today';
              
              return SliverToBoxAdapter(
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
            }),

            const SliverToBoxAdapter(
              child: SizedBox(height: 80),
            ),
          ],
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

    ref.read(searchProvider.notifier).updateFilters(filters);
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
