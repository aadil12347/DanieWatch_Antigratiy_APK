import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/models/manifest_item.dart';
import '../../providers/manifest_provider.dart';
import '../../providers/search_provider.dart';
import '../../widgets/movie_card.dart';
import '../../widgets/custom_app_bar.dart';
import 'widgets/filter_bottom_sheet.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with TickerProviderStateMixin {
  late final AnimationController _enterController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    
    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _enterController,
      curve: Curves.easeInOut,
    );

    _enterController.forward();
  }

  @override
  void dispose() {
    _enterController.dispose();
    super.dispose();
  }



  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final allItems = ref.watch(allItemsProvider);
    final index = ref.watch(manifestIndexProvider);
    
    // Using 3 columns as requested
    final crossAxisCount = 3;

    return CustomAppBar(
      isSearchScreen: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
            children: [
                // Glassmorphism background - only blur when searching or showing content
                if (searchState.query.isNotEmpty || searchState.filters.hasActiveFilters)
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _fadeAnimation,
                      builder: (context, child) {
                        return BackdropFilter(
                          filter: ImageFilter.blur(
                            sigmaX: 20 * _fadeAnimation.value,
                            sigmaY: 20 * _fadeAnimation.value,
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  AppColors.background.withValues(alpha: 0.85 * _fadeAnimation.value),
                                  AppColors.background.withValues(alpha: 0.98 * _fadeAnimation.value),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                // Main Content
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 80), // Space for floating CustomAppBar
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Column(
                      children: [
                        // Active filters pushed down below the CustomAppBar
                        _buildActiveFilters(searchState.filters),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 400),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            child: _buildResultsArea(
                              searchState,
                              allItems,
                              index,
                              crossAxisCount,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
    );
  }

  Widget _buildActiveFilters(SearchFilters filters) {
    if (!filters.hasActiveFilters) {
      return const SizedBox.shrink();
    }

    final activeChips = [
      ...filters.categories,
      ...filters.genres,
      ...filters.periods,
    ];

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      child: Container(
        height: 50,
        margin: const EdgeInsets.only(bottom: 8),
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: activeChips.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final label = activeChips[index];
            return TweenAnimationBuilder<double>(
              key: ValueKey(label),
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Opacity(
                    opacity: value,
                    child: child,
                  ),
                );
              },
              child: Chip(
                label: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                backgroundColor: AppColors.primary,
                deleteIcon: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
                onDeleted: () {
                  ref.read(searchProvider.notifier).removeFilterChip(label);
                },
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: Colors.transparent),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildResultsArea(
    SearchState searchState,
    List<ManifestItem> allItems,
    Map<String, ManifestItem> index,
    int crossAxisCount,
  ) {
    if (searchState.query.isEmpty && !searchState.filters.hasActiveFilters) {
      return _buildExploreState();
    }

    if (searchState.isSearching) {
      return _buildShimmerGrid(crossAxisCount);
    }

    if (searchState.results.isEmpty) {
      return _buildEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No results found',
        subtitle: 'Try adjusting your filters or search terms.',
      );
    }

    final resultItems = searchState.results
        .map((r) => index['${r.itemId}-${r.mediaType}'])
        .where((item) => item != null)
        .cast<ManifestItem>()
        .toList();

    return _buildGrid(resultItems, crossAxisCount);
  }

  Widget _buildExploreState() {
    return const SizedBox.shrink();
  }

  Widget _buildGrid(List<ManifestItem> items, int crossAxisCount) {
    return GridView.builder(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      physics: const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 0.65,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return TweenAnimationBuilder<double>(
          key: ValueKey('${items[index].id}_$index'),
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutQuart,
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 40 * (1 - value)),
                child: child,
              ),
            );
          },
          child: MovieCard(
            item: items[index],
            onTap: () => context.push('/search-details/${items[index].mediaType}/${items[index].id}'),
          ),
        );
      },
    );
  }

  Widget _buildShimmerGrid(int crossAxisCount) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 0.65,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: crossAxisCount * 4,
      itemBuilder: (context, index) => _buildShimmerCard(),
    );
  }

  Widget _buildShimmerCard() {
    return Shimmer.fromColors(
      baseColor: AppColors.surface,
      highlightColor: AppColors.surfaceElevated.withValues(alpha: 0.4),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildEmptyState({required IconData icon, required String title, required String subtitle}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 72, color: AppColors.primary.withValues(alpha: 0.5)),
          const SizedBox(height: 24),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
