import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../../domain/models/manifest_item.dart';
import '../../core/utils/responsive.dart';
import '../providers/manifest_provider.dart';
import 'movie_card.dart';

/// Horizontal scrolling content row used on home screen.
/// Supports infinite horizontal pagination as user swipes towards the end.
class ContentRow extends ConsumerStatefulWidget {
  final List<ManifestItem> items;
  final bool isRanked;
  final String? categorySlug;

  const ContentRow({
    super.key,
    required this.items,
    this.isRanked = false,
    this.categorySlug,
  });

  @override
  ConsumerState<ContentRow> createState() => _ContentRowState();
}

class _ContentRowState extends ConsumerState<ContentRow> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (widget.categorySlug == null) return;
    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;

    // Trigger loading more when within 350px of the right end
    if (currentScroll >= maxScroll - 350) {
      ref.read(paginatedCategoryProvider(widget.categorySlug!).notifier).loadNextPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = Responsive(context);
    final rowHeight = r.h(265).clamp(200.0, 340.0);
    final cardWidth = r.w(145).clamp(110.0, 190.0);
    final leftPad = widget.isRanked ? r.w(48).clamp(36.0, 64.0) : r.w(16).clamp(12.0, 24.0);
    final rightPad = r.w(16).clamp(12.0, 24.0);
    final spacing = widget.isRanked ? r.w(42).clamp(30.0, 56.0) : r.w(12).clamp(8.0, 18.0);

    List<ManifestItem> displayItems = widget.items;
    bool isLoadingMore = false;

    if (widget.categorySlug != null) {
      final pagState = ref.watch(paginatedCategoryProvider(widget.categorySlug!)).valueOrNull;
      if (pagState != null && pagState.items.isNotEmpty) {
        displayItems = pagState.items;
        isLoadingMore = pagState.isLoadingMore;
      }
    }

    final totalCount = displayItems.length + (isLoadingMore ? 1 : 0);

    return SizedBox(
      height: rowHeight,
      child: ListView.separated(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        physics: const AlwaysScrollableScrollPhysics(),
        // PERF: Pre-build cards 500px offscreen so fast swipes don't cause jank
        cacheExtent: 500,
        addRepaintBoundaries: true,
        padding: EdgeInsets.only(
          left: leftPad,
          right: rightPad,
        ),
        itemCount: totalCount,
        separatorBuilder: (_, __) => SizedBox(width: spacing),
        itemBuilder: (context, index) {
          if (index >= displayItems.length) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.primary,
                  ),
                ),
              ),
            );
          }

          // PERF: RepaintBoundary isolates each card's paint
          return RepaintBoundary(
            child: MovieCard(
              item: displayItems[index],
              width: cardWidth,
              height: rowHeight,
              rank: widget.isRanked ? index + 1 : null,
            ),
          );
        },
      ),
    );
  }
}
