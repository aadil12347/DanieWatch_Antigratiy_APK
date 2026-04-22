import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../providers/search_provider.dart';
import '../providers/filter_modal_provider.dart';
import 'morphing_search.dart';

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

class _CategorySearchBarState extends ConsumerState<CategorySearchBar>
    with SingleTickerProviderStateMixin {
  bool _isFocused = false;
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _isFocused = widget.searchFocus.hasFocus;
    widget.searchFocus.addListener(_onFocusChange);

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _glowAnim = Tween<double>(begin: 0.15, end: 0.35).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );
    if (_isFocused) _glowCtrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    widget.searchFocus.removeListener(_onFocusChange);
    _glowCtrl.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() => _isFocused = widget.searchFocus.hasFocus);
      if (_isFocused) {
        _glowCtrl.repeat(reverse: true);
      } else {
        _glowCtrl.stop();
        _glowCtrl.value = 0;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = Responsive(context);
    final searchState = ref.watch(searchProvider(widget.contextId));
    final hasSearch = searchState.query.isNotEmpty;
    final barHeight = r.h(48).clamp(42.0, 56.0);
    final filterBtnSize = r.d(48).clamp(42.0, 56.0);

    return Container(
      color: AppColors.background,
      padding: EdgeInsets.fromLTRB(r.w(16), r.h(8), r.w(16), r.h(10)),
      child: Row(
        children: [
          Expanded(
            child: AnimatedBuilder(
              animation: _glowAnim,
              builder: (context, child) {
                return Container(
                  height: barHeight,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF1E1E22),
                        const Color(0xFF1A1A1E),
                        _isFocused
                            ? AppColors.primary.withValues(alpha: 0.06)
                            : const Color(0xFF18181C),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(r.w(14)),
                    border: Border.all(
                      color: _isFocused
                          ? AppColors.primary.withValues(alpha: 0.6)
                          : Colors.white.withValues(alpha: 0.06),
                      width: _isFocused ? 1.2 : 0.8,
                    ),
                    boxShadow: _isFocused
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(
                                  alpha: _glowAnim.value),
                              blurRadius: 20,
                              spreadRadius: -2,
                            ),
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.08),
                              blurRadius: 40,
                              spreadRadius: 2,
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: child,
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(r.w(14)),
                child: TextField(
                  controller: widget.searchController,
                  focusNode: widget.searchFocus,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.center,
                  showCursor: true,
                  cursorColor: AppColors.primary,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: r.f(14).clamp(13.0, 17.0),
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.1,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search movies, shows...',
                    hintStyle: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.25),
                      fontSize: r.f(14).clamp(13.0, 17.0),
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.2,
                    ),
                    prefixIcon: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: EdgeInsets.only(left: r.w(14), right: r.w(8)),
                      child: Icon(
                        Icons.search_rounded,
                        color: _isFocused
                            ? AppColors.primary.withValues(alpha: 0.9)
                            : Colors.white.withValues(alpha: 0.25),
                        size: r.d(20).clamp(18.0, 24.0),
                      ),
                    ),
                    prefixIconConstraints: BoxConstraints(
                      minWidth: r.w(44),
                      minHeight: 0,
                    ),
                    suffixIcon: hasSearch
                        ? GestureDetector(
                            onTap: () {
                              widget.searchController.clear();
                              widget.onSearchChanged('');
                              widget.searchFocus.requestFocus();
                            },
                            child: Container(
                              margin: EdgeInsets.only(right: r.w(8)),
                              padding: const EdgeInsets.all(6),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(2),
                                child: Icon(
                                  Icons.close_rounded,
                                  color: Colors.white.withValues(alpha: 0.5),
                                  size: r.d(14).clamp(12.0, 18.0),
                                ),
                              ),
                            ),
                          )
                        : null,
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 0,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: r.w(4)),
                    isDense: true,
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
          ),
          SizedBox(width: r.w(10)),
          // Premium filter button with gradient
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
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFD42A30),
                    AppColors.primary,
                    Color(0xFF8E1519),
                  ],
                ),
                borderRadius: BorderRadius.circular(r.w(14)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(Icons.tune_rounded,
                  color: Colors.white, size: r.d(20).clamp(18.0, 24.0)),
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
  final bool showFilterButton;

  const PinnedHeaderRow({
    super.key,
    required this.title,
    required this.searchController,
    required this.searchFocus,
    required this.onSearchChanged,
    this.contextId = 'explore',
    this.showFilterButton = true,
  });

  @override
  ConsumerState<PinnedHeaderRow> createState() => _PinnedHeaderRowState();
}

class _PinnedHeaderRowState extends ConsumerState<PinnedHeaderRow>
    with TickerProviderStateMixin {
  late AnimationController _expandCtrl;
  late Animation<double> _expandAnim;
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;
  bool _isSearchOpen = false;

  @override
  void initState() {
    super.initState();
    _expandCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _expandAnim = CurvedAnimation(
      parent: _expandCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    // Pulsing glow animation for focused search field
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _glowAnim = Tween<double>(begin: 0.15, end: 0.4).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );

    // If there's already a query, open the search field immediately
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
    _glowCtrl.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!mounted) return;
    // Sync focus state for AppShell back-button handling
    ref.read(searchFocusProvider.notifier).state = widget.searchFocus.hasFocus;

    // Manage glow animation
    if (widget.searchFocus.hasFocus) {
      _glowCtrl.repeat(reverse: true);
    } else {
      _glowCtrl.stop();
      _glowCtrl.value = 0;
    }

    // When focus is lost (tap outside / back), decide whether to close
    if (!widget.searchFocus.hasFocus && _isSearchOpen) {
      if (widget.searchController.text.isEmpty) {
        _closeSearch();
      }
    }
    if (mounted) setState(() {});
  }

  void _openSearch() {
    setState(() => _isSearchOpen = true);
    _expandCtrl.forward().then((_) {
      if (mounted) widget.searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    widget.searchFocus.unfocus();
    _glowCtrl.stop();
    _glowCtrl.value = 0;
    _expandCtrl.reverse().then((_) {
      if (mounted) setState(() => _isSearchOpen = false);
    });
  }

  void _onCrossTapped() {
    widget.searchController.clear();
    widget.onSearchChanged('');
    widget.searchFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final r = Responsive(context);
    final filterBtnSize = r.d(42).clamp(36.0, 50.0);
    final iconBtnSize = r.d(42).clamp(36.0, 50.0);
    final hPad = r.w(16);

    return Container(
      color: AppColors.background,
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: r.h(6)),
      child: AnimatedBuilder(
        animation: _expandAnim,
        builder: (context, _) {
          final t = _expandAnim.value; // 0 = closed, 1 = open

          return Row(
            children: [
              // ── Main area: title fades/slides out, search slides in ──
              Expanded(
                child: ClipRect(
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // Title row (title + search icon) — visible when collapsed
                      if (t < 1.0)
                        Opacity(
                          opacity: (1.0 - t * 2.5).clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: Offset(-t * 30, 0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.title,
                                    style: GoogleFonts.plusJakartaSans(
                                      color: AppColors.textPrimary,
                                      fontSize: r.f(26).clamp(20.0, 32.0),
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.8,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                SizedBox(width: r.w(10)),
                                // Premium search icon button
                                GestureDetector(
                                  onTap: _openSearch,
                                  child: Container(
                                    height: iconBtnSize,
                                    width: iconBtnSize,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color(0xFF222226),
                                          Color(0xFF1C1C20),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(r.w(12)),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.08),
                                        width: 0.8,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      Icons.search_rounded,
                                      color: AppColors.textSecondary,
                                      size: r.d(20).clamp(18.0, 24.0),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Search field — slides in as t grows
                      if (_isSearchOpen)
                        Opacity(
                          opacity: (t * 2.0).clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: Offset((1.0 - t) * 80, 0),
                            child: _buildPremiumSearchField(r),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              SizedBox(width: r.w(10)),

              // ── Filter button (always visible) ──
              if (widget.showFilterButton)
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
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFD42A30),
                          AppColors.primary,
                          Color(0xFF8E1519),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(r.w(12)),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.tune_rounded,
                      color: Colors.white,
                      size: r.d(20).clamp(18.0, 24.0),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPremiumSearchField(Responsive r) {
    final isFocused = widget.searchFocus.hasFocus;
    final hasText = widget.searchController.text.isNotEmpty;
    final barHeight = r.h(44).clamp(38.0, 52.0);

    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (context, child) {
        return Container(
          height: barHeight,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1E1E22),
                const Color(0xFF1A1A1E),
                isFocused
                    ? AppColors.primary.withValues(alpha: 0.05)
                    : const Color(0xFF18181C),
              ],
            ),
            borderRadius: BorderRadius.circular(r.w(14)),
            border: Border.all(
              color: isFocused
                  ? AppColors.primary.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.06),
              width: isFocused ? 1.2 : 0.8,
            ),
            boxShadow: isFocused
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(
                          alpha: _glowAnim.value),
                      blurRadius: 20,
                      spreadRadius: -2,
                    ),
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      blurRadius: 40,
                      spreadRadius: 2,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: child,
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(r.w(14)),
        child: TextField(
          controller: widget.searchController,
          focusNode: widget.searchFocus,
          expands: true,
          maxLines: null,
          minLines: null,
          textAlignVertical: TextAlignVertical.center,
          showCursor: true,
          cursorColor: AppColors.primary,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: r.f(14).clamp(13.0, 17.0),
            fontWeight: FontWeight.w400,
            letterSpacing: 0.1,
          ),
          decoration: InputDecoration(
            hintText: 'Search movies, shows...',
            hintStyle: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.28),
              fontSize: r.f(14).clamp(12.0, 16.0),
              fontWeight: FontWeight.w400,
              letterSpacing: 0.2,
            ),
            filled: true,
            fillColor: Colors.transparent,
            prefixIcon: Padding(
              padding: EdgeInsets.only(left: r.w(14), right: r.w(8)),
              child: Icon(
                Icons.search_rounded,
                color: isFocused
                    ? AppColors.primary.withValues(alpha: 0.9)
                    : Colors.white.withValues(alpha: 0.3),
                size: r.d(20).clamp(18.0, 24.0),
              ),
            ),
            prefixIconConstraints: BoxConstraints(
              minWidth: r.w(44),
              minHeight: 0,
            ),
            suffixIcon: hasText
                ? GestureDetector(
                    onTap: _onCrossTapped,
                    child: Container(
                      margin: EdgeInsets.only(right: r.w(8)),
                      padding: const EdgeInsets.all(6),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.close_rounded,
                          color: Colors.white.withValues(alpha: 0.55),
                          size: r.d(14).clamp(12.0, 18.0),
                        ),
                      ),
                    ),
                  )
                : null,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 0,
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: r.w(4)),
            isDense: true,
          ),
          onChanged: widget.onSearchChanged,
          onSubmitted: (_) => widget.searchFocus.unfocus(),
        ),
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
  final bool showFilterButton;

  PinnedHeaderDelegate({
    required this.title,
    required this.searchController,
    required this.searchFocus,
    required this.onSearchChanged,
    this.contextId = 'explore',
    this.showFilterButton = true,
  });

  @override
  double get minExtent => 56;

  @override
  double get maxExtent => 56;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    // ExcludeSemantics + RepaintBoundary prevent the
    // "!semantics.parentDataDirty" assertion crash that the
    // AnimatedBuilder/LayoutBuilder/TextField combo triggers inside
    // SliverPersistentHeader.
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: MorphingSearchHeaderRow(
          title: title,
          searchController: searchController,
          searchFocus: searchFocus,
          onSearchChanged: onSearchChanged,
          contextId: contextId,
          showFilterButton: showFilterButton,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant PinnedHeaderDelegate oldDelegate) {
    return title != oldDelegate.title ||
        showFilterButton != oldDelegate.showFilterButton;
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
                    maxLines: 1,
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
