import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/manifest_provider.dart';
import '../../widgets/movie_card.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/custom_drawer.dart';

import '../../../core/utils/search_utils.dart';
import '../../providers/search_provider.dart';
import '../../widgets/category_header.dart';
import '../../widgets/empty_results_view.dart';

class MoviesScreen extends ConsumerStatefulWidget {
  const MoviesScreen({super.key});

  @override
  ConsumerState<MoviesScreen> createState() => _MoviesScreenState();
}

class _MoviesScreenState extends ConsumerState<MoviesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    ref.read(searchProvider.notifier).search(query);
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final allItems = ref.watch(moviesProvider);
    final index = ref.watch(manifestIndexProvider);

    final hasSearch = searchState.query.isNotEmpty;
    final hasFilters = searchState.filters.hasActiveFilters;
    final showResults = hasSearch || hasFilters;

    final itemsToDisplay = FilterUtils.getFilteredItems(
      allItems: allItems,
      searchState: searchState,
      index: index,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const CustomDrawer(),
      body: CustomAppBar(
        extendBehindAppBar: false,
        child: GestureDetector(
          onTap: () => _searchFocus.unfocus(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Title scrolls with content
              const SliverToBoxAdapter(
                child: CategoryTitle(title: 'Movies'),
              ),
              // Search bar floats
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
              if (searchState.isSearching)
                const SliverFillRemaining(
                  child: Center(child: ShimmerGrid()),
                )
              else if (allItems.isEmpty)
                const SliverFillRemaining(
                  child: Center(child: ShimmerGrid()),
                )
              else if (itemsToDisplay.isEmpty)
                const SliverFillRemaining(
                  child: EmptyResultsView(
                    message: 'Try adjusting your filters or search keywords to find the content you want.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.only(
                    top: 16,
                    left: 20,
                    right: 20,
                    bottom: 80,
                  ),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.7,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, idx) => MovieCard(item: itemsToDisplay[idx]),
                      childCount: itemsToDisplay.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
