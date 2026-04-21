import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../providers/search_provider.dart';
import '../providers/filter_modal_provider.dart';

/// The page title row — scrolls naturally with content.
class CategoryTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const CategoryTitle({
    super.key,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final r = Responsive(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(r.w(16), r.h(14), r.w(16), r.h(4)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.textPrimary,
              fontSize: r.f(26).clamp(20.0, 32.0),
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// The search bar + filter button — StatefulWidget for proper animated focus tracking.
class CategorySearchBar extends ConsumerStatefulWidget {
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final Function(String) onSearchChanged;
  final String contextId;

  const CategorySearchBar({
    super.key,
    required this.searchController,
    required this.searchFocus,
    required this.onSearchChanged,
    this.contextId = 'explore',
  });

  @override
  ConsumerState<CategorySearchBar> createState() => _CategorySearchBarState();
}

class _CategorySearchBarState extends ConsumerState<CategorySearchBar> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _isFocused = widget.searchFocus.hasFocus;
    widget.searchFocus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.searchFocus.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() => _isFocused = widget.searchFocus.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final r = Responsive(context);
    final searchState = ref.watch(searchProvider(widget.contextId));
    final hasSearch = searchState.query.isNotEmpty;
    final barHeight = r.h(48).clamp(40.0, 56.0);
    final filterBtnSize = r.d(48).clamp(40.0, 56.0);

    return Container(
      color: AppColors.background,
      padding: EdgeInsets.fromLTRB(r.w(16), r.h(8), r.w(16), r.h(10)),
      child: Row(
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              height: barHeight,
              decoration: BoxDecoration(
                color: AppColors.input,
                borderRadius: BorderRadius.circular(r.w(12)),
                border: Border.all(
                  color: _isFocused
                      ? AppColors.primary.withValues(alpha: 0.7)
                      : AppColors.border,
                  width: _isFocused ? 1.4 : 0.8,
                ),
                boxShadow: _isFocused
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 16,
                          spreadRadius: 0,
                        ),
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          blurRadius: 32,
                          spreadRadius: 2,
                        ),
                      ]
                    : [],
              ),
              child: TextField(
                controller: widget.searchController,
                focusNode: widget.searchFocus,
                style: TextStyle(color: Colors.white, fontSize: r.f(15).clamp(13.0, 18.0)),
                decoration: InputDecoration(
                  hintText: 'Search',
                  hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: r.f(15).clamp(13.0, 18.0)),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: _isFocused
                          ? AppColors.primary.withValues(alpha: 0.9)
                          : Colors.white.withValues(alpha: 0.35),
                      size: r.d(22).clamp(18.0, 26.0)),
                  suffixIcon: hasSearch
                      ? IconButton(
                          onPressed: () {
                            widget.searchController.clear();
                            widget.onSearchChanged('');
                            widget.searchFocus.requestFocus();
                          },
                          icon: Icon(Icons.close,
                              color: Colors.white.withValues(alpha: 0.4),
                              size: r.d(20).clamp(16.0, 24.0)),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: r.h(14)),
                ),
                onChanged: (val) {
                  widget.onSearchChanged(val);
                },
                onSubmitted: (val) {
                  widget.searchFocus.unfocus();
                },
              ),
            ),
          ),
          SizedBox(width: r.w(12)),
          GestureDetector(
            onTap: () {
              widget.searchFocus.unfocus();
              final currentState = ref.read(filterModalProvider);
              if (currentState.isOpen) {
                ref.read(filterModalProvider.notifier).state =
                    const FilterModalState(view: FilterView.none);
              } else {
                ref.read(filterModalProvider.notifier).state =
                    FilterModalState(
                  view: FilterView.mainPanel,
                  contextId: widget.contextId,
                );
              }
            },
            child: Container(
              height: filterBtnSize,
              width: filterBtnSize,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(r.w(12)),
              ),
              child: Icon(Icons.tune_rounded,
                  color: Colors.white, size: r.d(22).clamp(18.0, 26.0)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Active filter chips row — scrolls with content.
class CategoryFilterChips extends ConsumerWidget {
  final String contextId;
  const CategoryFilterChips({
    super.key,
    this.contextId = 'explore',
  });

  List<String> _getActiveFilterLabels(SearchState s) {
    final labels = <String>[];
    final f = s.filters;

    labels.addAll(f.categories);
    labels.addAll(f.regions);
    labels.addAll(f.genres);
    labels.addAll(f.years);
    if (f.sortBy != 'Popularity') labels.add(f.sortBy);
    return labels;
  }

  void _removeFilter(String label, SearchState state, WidgetRef ref) {
    final f = state.filters;
    if (f.categories.contains(label)) {
      final newSet = Set<String>.from(f.categories)..remove(label);
      ref.read(searchProvider(contextId).notifier).updateFilters(f.copyWith(categories: newSet));
    } else if (f.regions.contains(label)) {
      final newSet = Set<String>.from(f.regions)..remove(label);
      ref.read(searchProvider(contextId).notifier).updateFilters(f.copyWith(regions: newSet));
    } else if (f.genres.contains(label)) {
      final newSet = Set<String>.from(f.genres)..remove(label);
      ref.read(searchProvider(contextId).notifier).updateFilters(f.copyWith(genres: newSet));
    } else if (f.years.contains(label)) {
      final newSet = Set<String>.from(f.years)..remove(label);
      ref.read(searchProvider(contextId).notifier).updateFilters(f.copyWith(years: newSet));
    } else if (f.sortBy == label) {
      ref.read(searchProvider(contextId).notifier).updateFilters(f.copyWith(sortBy: 'Popularity'));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchState = ref.watch(searchProvider(contextId));
    final activeFilterLabels = _getActiveFilterLabels(searchState);

    if (activeFilterLabels.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 48,
      margin: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: activeFilterLabels.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, idx) {
                return GestureDetector(
                  onTap: () => _removeFilter(
                      activeFilterLabels[idx], searchState, ref),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          activeFilterLabels[idx],
                          style: GoogleFonts.inter(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.close_rounded,
                            color: AppColors.textPrimary.withValues(alpha: 0.7), 
                            size: 14),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (activeFilterLabels.length >= 2) ...[
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: GestureDetector(
                onTap: () {
                  ref.read(searchProvider(contextId).notifier).clearFilters();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.delete_outline_rounded,
                          color: AppColors.textSecondary, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        'Clear',
                        style: GoogleFonts.inter(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// SliverPersistentHeader delegate for the floating search bar.
/// Shows/hides based on scroll direction (floating behavior).
class FloatingSearchBarDelegate extends SliverPersistentHeaderDelegate {
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final Function(String) onSearchChanged;
  final String contextId;

  FloatingSearchBarDelegate({
    required this.searchController,
    required this.searchFocus,
    required this.onSearchChanged,
    this.contextId = 'explore',
  });

  @override
  double get minExtent => 76;

  @override
  double get maxExtent => 76;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return CategorySearchBar(
      searchController: searchController,
      searchFocus: searchFocus,
      onSearchChanged: onSearchChanged,
      contextId: contextId,
    );
  }

  @override
  bool shouldRebuild(covariant FloatingSearchBarDelegate oldDelegate) => false;
}

/// Pinned header row: Title + animated search icon + filter button.
/// The search icon expands into a full search field on tap, hiding the title.
class PinnedHeaderRow extends ConsumerStatefulWidget {
  final String title;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final Function(String) onSearchChanged;
  final String contextId;

  const PinnedHeaderRow({
    super.key,
    required this.title,
    required this.searchController,
    required this.searchFocus,
    required this.onSearchChanged,
    this.contextId = 'explore',
  });

  @override
  ConsumerState<PinnedHeaderRow> createState() => _PinnedHeaderRowState();
}

class _PinnedHeaderRowState extends ConsumerState<PinnedHeaderRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _expandCtrl;
  late Animation<double> _expandAnim;
  bool _isSearchOpen = false;

  @override
  void initState() {
    super.initState();
    _expandCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _expandAnim = CurvedAnimation(
      parent: _expandCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    // If there's already a query, open the search field
    if (widget.searchController.text.isNotEmpty) {
      _isSearchOpen = true;
      _expandCtrl.value = 1.0;
    }

    widget.searchFocus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.searchFocus.removeListener(_onFocusChange);
    _expandCtrl.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!mounted) return;
    // Sync focus state to global provider for AppShell back-button handling
    ref.read(searchFocusProvider.notifier).state = widget.searchFocus.hasFocus;

    // When focus is lost (tap outside / back), decide whether to close
    if (!widget.searchFocus.hasFocus && _isSearchOpen) {
      if (widget.searchController.text.isEmpty) {
        // Empty field + lost focus → collapse
        _closeSearch();
      }
      // If text is present, field stays open (just keyboard dismissed)
    }
    setState(() {});
  }

  void _openSearch() {
    setState(() => _isSearchOpen = true);
    _expandCtrl.forward().then((_) {
      if (mounted) {
        widget.searchFocus.requestFocus();
        ref.read(searchExpandedProvider.notifier).state = true;
      }
    });
  }

  void _closeSearch() {
    widget.searchFocus.unfocus();
    _expandCtrl.reverse().then((_) {
      if (mounted) {
        setState(() => _isSearchOpen = false);
        ref.read(searchExpandedProvider.notifier).state = false;
      }
    });
  }

  void _onCrossTapped() {
    // Clear text only — field stays open and focused
    widget.searchController.clear();
    widget.onSearchChanged('');
    widget.searchFocus.requestFocus();
  }

  /// Called externally (e.g. from scroll listener) to dismiss keyboard
  /// without closing the search field.
  void dismissKeyboard() {
    if (widget.searchFocus.hasFocus) {
      widget.searchFocus.unfocus();
    }
  }

  /// Called externally to attempt closing (e.g. from back button).
  /// Returns true if it handled the event.
  bool tryClose() {
    if (!_isSearchOpen) return false;
    if (widget.searchController.text.isNotEmpty) {
      // Just dismiss keyboard, don't close
      widget.searchFocus.unfocus();
      return true;
    }
    // Empty → close
    _closeSearch();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final r = Responsive(context);
    final hasSearch = widget.searchController.text.isNotEmpty;
    final isFocused = widget.searchFocus.hasFocus;

    final rowHeight = r.h(56).clamp(48.0, 64.0);
    final iconBtnSize = r.d(42).clamp(36.0, 50.0);
    final filterBtnSize = r.d(42).clamp(36.0, 50.0);
    final hPad = r.w(16);

    return Container(
      height: rowHeight,
      color: AppColors.background,
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: Row(
        children: [
          // Title — fades out as search expands
          Expanded(
            child: AnimatedBuilder(
              animation: _expandAnim,
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    // Title text (visible when search is collapsed)
                    Opacity(
                      opacity: (1.0 - _expandAnim.value).clamp(0.0, 1.0),
                      child: _expandAnim.value < 1.0
                          ? Text(
                              widget.title,
                              style: GoogleFonts.plusJakartaSans(
                                color: AppColors.textPrimary,
                                fontSize: r.f(26).clamp(20.0, 32.0),
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.8,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          : const SizedBox.shrink(),
                    ),
                    // Search field (expanding from the right)
                    if (_isSearchOpen)
                      Positioned.fill(
                        child: Opacity(
                          opacity: _expandAnim.value.clamp(0.0, 1.0),
                          child: _buildSearchField(r, hasSearch, isFocused),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),

          SizedBox(width: r.w(10)),

          // Search icon button (visible when search is closed)
          if (!_isSearchOpen)
            GestureDetector(
              onTap: _openSearch,
              child: Container(
                height: iconBtnSize,
                width: iconBtnSize,
                decoration: BoxDecoration(
                  color: AppColors.input,
                  borderRadius: BorderRadius.circular(r.w(10)),
                  border: Border.all(color: AppColors.border, width: 0.8),
                ),
                child: Icon(
                  Icons.search_rounded,
                  color: AppColors.textSecondary,
                  size: r.d(22).clamp(18.0, 26.0),
                ),
              ),
            ),

          SizedBox(width: r.w(8)),

          // Filter button (always visible)
          GestureDetector(
            onTap: () {
              widget.searchFocus.unfocus();
              final currentState = ref.read(filterModalProvider);
              if (currentState.isOpen) {
                ref.read(filterModalProvider.notifier).state =
                    const FilterModalState(view: FilterView.none);
              } else {
                ref.read(filterModalProvider.notifier).state = FilterModalState(
                  view: FilterView.mainPanel,
                  contextId: widget.contextId,
                );
              }
            },
            child: Container(
              height: filterBtnSize,
              width: filterBtnSize,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(r.w(10)),
              ),
              child: Icon(
                Icons.tune_rounded,
                color: Colors.white,
                size: r.d(22).clamp(18.0, 26.0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(Responsive r, bool hasSearch, bool isFocused) {
    final barHeight = r.h(42).clamp(36.0, 50.0);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      height: barHeight,
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(r.w(10)),
        border: Border.all(
          color: isFocused
              ? AppColors.primary.withValues(alpha: 0.7)
              : AppColors.border,
          width: isFocused ? 1.4 : 0.8,
        ),
        boxShadow: isFocused
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 14,
                  spreadRadius: 0,
                ),
              ]
            : [],
      ),
      child: TextField(
        controller: widget.searchController,
        focusNode: widget.searchFocus,
        style: TextStyle(
          color: Colors.white,
          fontSize: r.f(15).clamp(13.0, 18.0),
        ),
        decoration: InputDecoration(
          hintText: 'Search',
          hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: r.f(15).clamp(13.0, 18.0),
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: isFocused
                ? AppColors.primary.withValues(alpha: 0.9)
                : Colors.white.withValues(alpha: 0.35),
            size: r.d(22).clamp(18.0, 26.0),
          ),
          suffixIcon: hasSearch
              ? IconButton(
                  onPressed: _onCrossTapped,
                  icon: Icon(
                    Icons.close_rounded,
                    color: Colors.white.withValues(alpha: 0.5),
                    size: r.d(20).clamp(16.0, 24.0),
                  ),
                )
              : null,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: r.h(12)),
        ),
        onChanged: widget.onSearchChanged,
        onSubmitted: (_) => widget.searchFocus.unfocus(),
      ),
    );
  }
}

/// SliverPersistentHeader delegate for the pinned header row.
/// Always stays at the top of the scroll view.
class PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String title;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final Function(String) onSearchChanged;
  final String contextId;

  PinnedHeaderDelegate({
    required this.title,
    required this.searchController,
    required this.searchFocus,
    required this.onSearchChanged,
    this.contextId = 'explore',
  });

  @override
  double get minExtent => 56;

  @override
  double get maxExtent => 56;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return PinnedHeaderRow(
      title: title,
      searchController: searchController,
      searchFocus: searchFocus,
      onSearchChanged: onSearchChanged,
      contextId: contextId,
    );
  }

  @override
  bool shouldRebuild(covariant PinnedHeaderDelegate oldDelegate) {
    return title != oldDelegate.title;
  }
}

/// Legacy combined CategoryHeader for backward compatibility.
/// @deprecated Use CategoryTitle + FloatingSearchBarDelegate + CategoryFilterChips instead.
class CategoryHeader extends ConsumerWidget {
  final String title;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final Function(String) onSearchChanged;
  final Widget? trailing;
  final String contextId;

  const CategoryHeader({
    super.key,
    required this.title,
    required this.searchController,
    required this.searchFocus,
    required this.onSearchChanged,
    this.trailing,
    this.contextId = 'explore',
  });

  List<String> _getActiveFilterLabels(SearchState s) {
    final labels = <String>[];
    final f = s.filters;

    labels.addAll(f.categories);
    labels.addAll(f.regions);
    labels.addAll(f.genres);
    labels.addAll(f.years);
    if (f.sortBy != 'Popularity') labels.add(f.sortBy);
    return labels;
  }

  void _removeFilter(String label, SearchState state, WidgetRef ref) {
    final f = state.filters;
    if (f.categories.contains(label)) {
      final newSet = Set<String>.from(f.categories)..remove(label);
      ref.read(searchProvider(contextId).notifier).updateFilters(f.copyWith(categories: newSet));
    } else if (f.regions.contains(label)) {
      final newSet = Set<String>.from(f.regions)..remove(label);
      ref.read(searchProvider(contextId).notifier).updateFilters(f.copyWith(regions: newSet));
    } else if (f.genres.contains(label)) {
      final newSet = Set<String>.from(f.genres)..remove(label);
      ref.read(searchProvider(contextId).notifier).updateFilters(f.copyWith(genres: newSet));
    } else if (f.years.contains(label)) {
      final newSet = Set<String>.from(f.years)..remove(label);
      ref.read(searchProvider(contextId).notifier).updateFilters(f.copyWith(years: newSet));
    } else if (f.sortBy == label) {
      ref.read(searchProvider(contextId).notifier).updateFilters(f.copyWith(sortBy: 'Popularity'));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchState = ref.watch(searchProvider(contextId));
    final activeFilterLabels = _getActiveFilterLabels(searchState);
    final hasSearch = searchState.query.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Elegant Heading
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.textPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.0,
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        
        // Search bar + Filter icon
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.input,
                    borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: searchFocus.hasFocus
                        ? AppColors.primary.withValues(alpha: 0.5)
                        : AppColors.border,
                    width: 1,
                  ),
                  ),
                  child: TextField(
                    controller: searchController,
                    focusNode: searchFocus,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Search',
                      hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 15),
                      prefixIcon: Icon(Icons.search,
                          color: Colors.white.withValues(alpha: 0.4), size: 22),
                      suffixIcon: hasSearch
                          ? GestureDetector(
                              onTap: () {
                                searchController.clear();
                                onSearchChanged('');
                              },
                              child: Icon(Icons.close,
                                  color: Colors.white.withValues(alpha: 0.4),
                                  size: 20),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onChanged: onSearchChanged,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  searchFocus.unfocus();
                  final currentState = ref.read(filterModalProvider);
                  if (currentState.isOpen) {
                    ref.read(filterModalProvider.notifier).state =
                        const FilterModalState(view: FilterView.none);
                  } else {
                    ref.read(filterModalProvider.notifier).state =
                        FilterModalState(
                      view: FilterView.mainPanel,
                      contextId: contextId,
                    );
                  }
                },
                child: Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.tune_rounded,
                      color: Colors.white, size: 22),
                ),
              ),
            ],
          ),
        ),

        // Active Filter chips
        if (activeFilterLabels.isNotEmpty)
          SizedBox(
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    itemCount: activeFilterLabels.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, idx) {
                      return GestureDetector(
                        onTap: () => _removeFilter(
                            activeFilterLabels[idx], searchState, ref),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                activeFilterLabels[idx],
                                style: GoogleFonts.inter(
                                  color: AppColors.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.close,
                                  color: AppColors.textPrimary.withValues(alpha: 0.7), size: 14),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (activeFilterLabels.length >= 2) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 16.0, top: 8),
                    child: GestureDetector(
                      onTap: () {
                        ref.read(searchProvider(contextId).notifier).clearFilters();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.delete_outline_rounded,
                                color: AppColors.textSecondary, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              'Clear',
                              style: GoogleFonts.inter(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
