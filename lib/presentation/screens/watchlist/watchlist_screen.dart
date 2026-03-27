import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/models/manifest_item.dart';
import '../../providers/watchlist_provider.dart';
import '../../providers/search_provider.dart';
import '../../providers/manifest_provider.dart';
import '../../widgets/movie_card.dart';
import '../../widgets/empty_results_view.dart';
import '../../widgets/category_header.dart';
import '../../../core/utils/search_utils.dart';

class WatchlistScreen extends ConsumerStatefulWidget {
  const WatchlistScreen({super.key});

  @override
  ConsumerState<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends ConsumerState<WatchlistScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    final watchlistAsync = ref.watch(watchlistProvider);
    final searchState = ref.watch(searchProvider);
    final index = ref.watch(manifestIndexProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => _searchFocus.unfocus(),
          child: Column(
            children: [
              CategoryHeader(
                title: 'Favourites',
                searchController: _searchController,
                searchFocus: _searchFocus,
                onSearchChanged: _onSearchChanged,
              ),
              Expanded(
                child: watchlistAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                  error: (e, _) => Center(
                    child: Text('Error: $e',
                        style: const TextStyle(color: AppColors.textMuted)),
                  ),
                  data: (items) {
                    if (items.isEmpty) {
                      return _buildEmptyContent(context);
                    }

                    // Map watchlist items to ManifestItems for filtering
                    final manifestItems = items.map((item) => ManifestItem(
                          id: item.tmdbId,
                          mediaType: item.mediaType,
                          title: item.title,
                          posterUrl: item.posterPath,
                          voteAverage: item.voteAverage,
                        )).toList();

                    // Apply filters
                    final filteredItems = FilterUtils.getFilteredItems(
                      allItems: manifestItems,
                      searchState: searchState,
                      index: index,
                    );

                    if (filteredItems.isEmpty && (searchState.query.isNotEmpty || searchState.filters.hasActiveFilters)) {
                      return const EmptyResultsView();
                    }

                    if (filteredItems.isEmpty) {
                      return _buildEmptyContent(context);
                    }

                    return GridView.builder(
                      padding: EdgeInsets.fromLTRB(
                          16, 4, 16, MediaQuery.paddingOf(context).bottom + 100),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 0.65,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: filteredItems.length,
                      itemBuilder: (context, index) {
                        return MovieCard(
                          key: ValueKey('fav_${filteredItems[index].id}'),
                          item: filteredItems[index],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyContent(BuildContext context) {
    return const EmptyResultsView(
      title: 'Your List is Empty',
      message: "It seems that you haven't added any movies or shows to your list yet.",
      icon: Icons.bookmark_border_rounded,
    );
  }
}
