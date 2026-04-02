import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../providers/manifest_provider.dart';
import '../../providers/search_provider.dart';
import '../../widgets/content_row.dart';
import '../../widgets/stacked_carousel.dart';
import '../../widgets/section_header.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/custom_drawer.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manifestAsync = ref.watch(manifestProvider);
    final sections = ref.watch(homeSectionsProvider);
    final trending = ref.watch(trendingProvider);

    return manifestAsync.when(
      loading: () => manifestAsync.hasValue ? _buildHomeContent(context, ref, manifestAsync.value!) : const _LoadingHome(),
      error: (e, _) => manifestAsync.hasValue ? _buildHomeContent(context, ref, manifestAsync.value!) : _ErrorHome(error: e.toString()),
      data: (manifest) {
        if (manifest == null || manifest.items.isEmpty) {
          return const _EmptyHome();
        }
        return _buildHomeContent(context, ref, manifest);
      },
    );
  }

  Widget _buildHomeContent(BuildContext context, WidgetRef ref, dynamic manifest) {
    final sections = ref.watch(homeSectionsProvider);
    final trending = ref.watch(trendingProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const CustomDrawer(),
      body: CustomAppBar(
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Personalized Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 44, 16, 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: AppColors.surfaceElevated,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.person_outline_rounded,
                              size: 24, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Hello,',
                                style: GoogleFonts.inter(
                                    color: AppColors.textMuted,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    height: 1.1)),
                            Text('Daniyal',
                                style: GoogleFonts.lora(
                                    color: AppColors.textPrimary,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w500,
                                    height: 1.2)),
                          ],
                        ),
                      ],
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
            ...sections.map((section) => SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionHeader(
                        title: section.title,
                        onSeeAll: () =>
                            _handleSeeAll(ref, context, section.title),
                      ),
                      ContentRow(items: section.items),
                    ],
                  ),
                )),

            const SliverToBoxAdapter(
              child: SizedBox(height: 80),
            ),
          ],
        ),
      ),
    );
  }

  void _handleSeeAll(WidgetRef ref, BuildContext context, String title) {
    SearchFilters filters = const SearchFilters();

    if (title == 'Trending Now') {
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
