import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/models/manifest_item.dart';
import '../../../core/utils/search_utils.dart';
import '../../providers/manifest_provider.dart';
import '../../providers/search_provider.dart';
import '../../widgets/movie_card.dart';
import '../../widgets/category_header.dart';
import '../../widgets/empty_results_view.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final currentQuery = ref.read(searchProvider).query;
    if (currentQuery.isNotEmpty) {
      _searchController.text = currentQuery;
    }
    _searchFocus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {});
      // Sync focus state to global provider for AppShell navigation handling
      ref.read(searchFocusProvider.notifier).state = _searchFocus.hasFocus;
    }
  }

  void _dispose() {
    _searchController.dispose();
    _searchFocus.removeListener(_onFocusChange);
    // Ensure focus state is cleared when screen is removed
    ref.read(searchFocusProvider.notifier).state = false;
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    ref.read(searchProvider.notifier).search(query);
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final allItems = ref.watch(allItemsProvider);
    final index = ref.watch(manifestIndexProvider);

    final hasSearch = searchState.query.trim().isNotEmpty;
    final hasFilters = searchState.filters.hasActiveFilters;
    final showResults = hasSearch || hasFilters;
    
    final itemsToDisplay = showResults
        ? FilterUtils.getFilteredItems(
            allItems: allItems, 
            searchState: searchState, 
            index: index,
          )
        : <ManifestItem>[];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => _searchFocus.unfocus(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Title scrolls with content
              const SliverToBoxAdapter(
                child: CategoryTitle(title: 'Explore'),
              ),
              // Search bar floats (hides on scroll down, shows on scroll up)
              SliverPersistentHeader(
                floating: true,
                delegate: FloatingSearchBarDelegate(
                  searchController: _searchController,
                  searchFocus: _searchFocus,
                  onSearchChanged: _onSearchChanged,
                ),
              ),
              // Filter chips
              const SliverToBoxAdapter(
                child: CategoryFilterChips(),
              ),
              // Content
              ..._buildContentSlivers(
                  searchState, hasSearch, showResults, itemsToDisplay, allItems),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContentSlivers(
    SearchState searchState,
    bool hasSearch,
    bool showResults,
    List<ManifestItem> itemsToDisplay,
    List<ManifestItem> allItems,
  ) {
    // Searching shimmer
    if (searchState.isSearching) {
      return [_buildShimmerGrid()];
    }

    // User typed something but no results
    if (hasSearch && itemsToDisplay.isEmpty) {
      return [
        const SliverFillRemaining(
          child: EmptyResultsView(),
        ),
      ];
    }

    // Active search or filter with results
    if (showResults && itemsToDisplay.isNotEmpty) {
      return [_buildResultsGrid(itemsToDisplay)];
    }

    // No search or filter active → grid of all items
    return [_buildResultsGrid(allItems)];
  }

  Widget _buildResultsGrid(List<ManifestItem> items) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
          16, 4, 16, MediaQuery.paddingOf(context).bottom + 100),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.6,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, idx) {
            return MovieCard(
              key: ValueKey('result_${items[idx].id}_$idx'),
              item: items[idx],
              onTap: () => context
                  .push('/details/${items[idx].mediaType}/${items[idx].id}'),
            );
          },
          childCount: items.length,
        ),
      ),
    );
  }

  Widget _buildShimmerGrid() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.6,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => Shimmer.fromColors(
            baseColor: AppColors.surface,
            highlightColor: AppColors.surfaceElevated.withAlpha(100),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          childCount: 9,
        ),
      ),
    );
  }
}
