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
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.removeListener(_onFocusChange);
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    ref.read(searchProvider.notifier).search(query);
  }

  // Filtering logic extracted to FilterUtils.
  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final allItems = ref.watch(allItemsProvider);
    final index = ref.watch(manifestIndexProvider);

    final hasSearch = searchState.query.isNotEmpty;
    final hasFilters = searchState.filters.hasActiveFilters;
    final showResults = hasSearch || hasFilters;
    final itemsToDisplay = showResults
        ? FilterUtils.getFilteredItems(
            allItems: allItems, searchState: searchState, index: index)
        : <ManifestItem>[];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => _searchFocus.unfocus(),
          child: Column(
            children: [
              CategoryHeader(
                title: 'Explore',
                searchController: _searchController,
                searchFocus: _searchFocus,
                onSearchChanged: _onSearchChanged,
              ),

              // ── Main content area ──
              Expanded(
                child: _buildContent(searchState, hasSearch, showResults,
                    itemsToDisplay, allItems),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    SearchState searchState,
    bool hasSearch,
    bool showResults,
    List<ManifestItem> itemsToDisplay,
    List<ManifestItem> allItems,
  ) {
    // Searching shimmer
    if (searchState.isSearching) {
      return _buildShimmerGrid();
    }

    // User typed something but no results → "Not Found"
    if (hasSearch && itemsToDisplay.isEmpty) {
      return const EmptyResultsView();
    }

    // Active search or filter with results → grid
    if (showResults && itemsToDisplay.isNotEmpty) {
      return _buildResultsGrid(itemsToDisplay);
    }

    // No search or filter active → Default to grid of all items
    return _buildResultsGrid(allItems);
  }



  // ── Results grid (search / filter results — 2-column) ──
  Widget _buildResultsGrid(List<ManifestItem> items) {
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
          16, 4, 16, MediaQuery.paddingOf(context).bottom + 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.65,
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (context, idx) {
        return MovieCard(
          key: ValueKey('result_${items[idx].id}_$idx'),
          item: items[idx],
          onTap: () => context
              .push('/search-details/${items[idx].mediaType}/${items[idx].id}'),
        );
      },
    );
  }

  // ── Shimmer grid ──
  Widget _buildShimmerGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.65,
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
      ),
      itemCount: 9,
      itemBuilder: (context, index) => Shimmer.fromColors(
        baseColor: AppColors.surface,
        highlightColor: AppColors.surfaceElevated.withAlpha(100),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
