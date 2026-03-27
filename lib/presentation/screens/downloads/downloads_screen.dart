import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:open_file/open_file.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/local/download_manager.dart';
import '../video_player/video_player_screen.dart';
import '../../widgets/category_header.dart';
import '../../widgets/empty_results_view.dart';
import '../../providers/search_provider.dart';
import '../../../core/utils/toast_utils.dart';

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  StreamSubscription? _updateSub;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _updateSub =
        DownloadManager.instance.updateStream.listen(_onDownloadUpdate);
    _searchFocus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _updateSub?.cancel();
    _searchController.dispose();
    _searchFocus.removeListener(_onFocusChange);
    _searchFocus.dispose();
    super.dispose();
  }

  void _onDownloadUpdate(DownloadItem item) {
    if (mounted) setState(() {});
  }

  void _onSearchChanged(String query) {
    ref.read(searchProvider.notifier).search(query);
  }

  List<DownloadItem> _getFilteredDownloads(List<DownloadItem> allDownloads, SearchState searchState) {
    var filtered = List<DownloadItem>.from(allDownloads);

    // Search query
    if (searchState.query.isNotEmpty) {
      final q = searchState.query.toLowerCase();
      filtered = filtered.where((d) => d.displayName.toLowerCase().contains(q)).toList();
    }

    // Category filter
    if (searchState.filters.categories.isNotEmpty) {
      final cat = searchState.filters.categories.first.toLowerCase();
      if (cat == 'movie') {
        filtered = filtered.where((d) => d.season == 0).toList();
      } else if (cat == 'season' || cat == 'series') {
        filtered = filtered.where((d) => d.season > 0).toList();
      }
    }

    // Sorting (Latest first by default)
    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final allDownloads = DownloadManager.instance.downloads;
    final downloads = _getFilteredDownloads(allDownloads, searchState);

    final downloading = downloads
        .where(
          (d) =>
              d.status == DownloadStatus.downloading ||
              d.status == DownloadStatus.pending ||
              d.status == DownloadStatus.paused ||
              d.status == DownloadStatus.failed ||
              d.status == DownloadStatus.canceled ||
              d.status == DownloadStatus.converting,
        )
        .toList();
    final completed =
        downloads.where((d) => d.status == DownloadStatus.completed).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => _searchFocus.unfocus(),
          child: Column(
            children: [
              CategoryHeader(
                title: 'Downloads',
                searchController: _searchController,
                searchFocus: _searchFocus,
                onSearchChanged: _onSearchChanged,
                trailing: completed.isNotEmpty
                    ? GestureDetector(
                        onTap: _showClearDialog,
                        child: Text(
                          'Clear All',
                          style: GoogleFonts.inter(
                            color: AppColors.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : null,
              ),
              Expanded(
                child: allDownloads.isEmpty
                    ? _buildEmptyState()
                    : (downloads.isEmpty && (searchState.query.isNotEmpty || searchState.filters.hasActiveFilters))
                        ? const EmptyResultsView()
                        : CustomScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            slivers: [
                              // Sections only show if filtered results have them
                              if (downloading.isNotEmpty) ...[
                                _buildSectionHeader(
                                  'DOWNLOADING (${downloading.length})',
                                ),
                                SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) =>
                                        _buildDownloadingItem(downloading[index]),
                                    childCount: downloading.length,
                                  ),
                                ),
                              ],

                              if (completed.isNotEmpty) ...[
                                _buildSectionHeader('DOWNLOADED (${completed.length})'),
                                SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) =>
                                        _buildCompletedItem(completed[index]),
                                    childCount: completed.length,
                                  ),
                                ),
                              ],

                              const SliverToBoxAdapter(child: SizedBox(height: 100)),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Empty State (matching watchlist style) ──────────────────────────────
  Widget _buildEmptyState() {
    return const EmptyResultsView(
      title: 'No Downloads Yet',
      message: 'Movies and episodes you download will appear here',
      icon: Icons.download_rounded,
    );
  }

  Widget _buildDownloadCardShape(double width, double height, Color color) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Column(
        children: [
          // Red accent strip at top
          Container(
            width: 40,
            height: 10,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(6)),
            ),
            child: Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
          ),
          const Spacer(),
          Icon(
            Icons.download_rounded,
            size: 40,
            color: AppColors.textMuted.withValues(alpha: 0.3),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  // ─── Section Header ─────────────────────────────────────────────────────
  Widget _buildSectionHeader(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
        child: Text(
          title,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  // ─── Downloading Item ───────────────────────────────────────────────────
  Widget _buildDownloadingItem(DownloadItem item) {
    final pct = (item.progress * 100).toInt().clamp(0, 100);

    return GestureDetector(
      onLongPress: () => _showDeleteTooltip(context, item),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: item.posterUrl != null
                  ? CachedNetworkImage(
                      imageUrl: item.posterUrl!,
                      width: 60,
                      height: 80,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _buildPlaceholder(),
                      errorWidget: (_, __, ___) => _buildPlaceholder(),
                    )
                  : _buildPlaceholder(),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Tooltip(
                    message: item.fileName,
                    preferBelow: false,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    textStyle:
                        const TextStyle(color: Colors.white, fontSize: 13),
                    child: Text(
                      item.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Quality & Audio tag
                  if (item.qualityTag.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.qualityTag,
                      style: TextStyle(
                        color: AppColors.textSecondary.withValues(alpha: 0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: item.progress > 0 ? item.progress : null,
                      backgroundColor: AppColors.surface,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        item.status == DownloadStatus.paused
                            ? Colors.orange
                            : item.status == DownloadStatus.failed
                                ? Colors.red
                                : AppColors.primary,
                      ),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _getProgressText(item, pct),
                          style: TextStyle(
                            color: item.status == DownloadStatus.paused
                                ? Colors.orange
                                : item.status == DownloadStatus.failed
                                    ? Colors.red
                                    : AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Actions
            Column(
              children: [
                if (item.status == DownloadStatus.failed)
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.orange),
                    tooltip: 'Retry',
                    onPressed: () {
                      DownloadManager.instance.resumeDownload(item.id);
                      setState(() {});
                    },
                  )
                else if (item.status == DownloadStatus.paused)
                  IconButton(
                    icon: const Icon(Icons.play_arrow, color: Colors.white),
                    onPressed: () {
                      DownloadManager.instance.resumeDownload(item.id);
                      setState(() {});
                    },
                  )
                else if (item.status == DownloadStatus.downloading ||
                    item.status == DownloadStatus.converting)
                  IconButton(
                    icon: const Icon(Icons.pause, color: Colors.white),
                    onPressed: () {
                      DownloadManager.instance.pauseDownload(item.id);
                      setState(() {});
                    },
                  ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red, size: 20),
                  onPressed: () => _showDeleteConfirmation(item),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getProgressText(DownloadItem item, int pct) {
    final mb = item.formattedDownloadedBytes;
    if (item.status == DownloadStatus.paused) {
      return 'Paused · $pct% · $mb';
    }
    if (item.status == DownloadStatus.failed) {
      return item.error ?? 'Failed';
    }
    if (item.status == DownloadStatus.converting) {
      return '$pct% · $mb · Finalizing...';
    }
    // Downloading
    final speedStr = item.formattedSpeed;
    if (speedStr.isNotEmpty) {
      return '$pct% · $mb · $speedStr';
    }
    return '$pct% · $mb';
  }

  // ─── Completed Item ─────────────────────────────────────────────────────
  Widget _buildCompletedItem(DownloadItem item) {
    return GestureDetector(
      onTap: () => _playDownload(item),
      onLongPress: () => _showDeleteTooltip(context, item),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            // Thumbnail with play overlay
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: item.posterUrl != null
                      ? CachedNetworkImage(
                          imageUrl: item.posterUrl!,
                          width: 60,
                          height: 80,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _buildPlaceholder(),
                          errorWidget: (_, __, ___) => _buildPlaceholder(),
                        )
                      : _buildPlaceholder(),
                ),
                // Play icon overlay
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.black.withValues(alpha: 0.3),
                    ),
                    child: const Icon(
                      Icons.play_circle_outline,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (item.qualityTag.isNotEmpty)
                        Flexible(
                          child: Text(
                            '${item.qualityTag} • ',
                            style: TextStyle(
                              color: AppColors.textMuted.withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      Flexible(
                        child: Text(
                          item.formattedSize,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Actions: Play + Delete
            GestureDetector(
              onTap: () => _playDownload(item),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _showDeleteConfirmation(item),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.red.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.delete_outline,
                  color: Colors.red.withValues(alpha: 0.8),
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 60,
      height: 80,
      color: AppColors.surface,
      child: const Icon(Icons.movie, color: AppColors.textMuted, size: 30),
    );
  }

  void _playDownload(DownloadItem item) async {
    if (item.localPath != null) {
      final file = File(item.localPath!);
      if (await file.exists()) {
        final result = await OpenFile.open(item.localPath);
        if (result.type != ResultType.done) {
          if (mounted) {
            CustomToast.show(
              context,
              'Could not open file: ${result.message}',
              type: ToastType.error,
            );
          }
        }
      } else {
        if (mounted) {
          CustomToast.show(
            context,
            'File not found on storage',
            type: ToastType.error,
          );
        }
      }
    } else {
      if (mounted) {
        CustomToast.show(
          context,
          'Local path missing',
          type: ToastType.error,
        );
      }
    }
  }

  // ─── Long-press Delete Tooltip ──────────────────────────────────────────
  void _showDeleteTooltip(BuildContext context, DownloadItem item) {
    HapticFeedback.mediumImpact();

    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final cardPosition = box.localToGlobal(Offset.zero);
    final cardSize = box.size;
    final screenWidth = MediaQuery.of(context).size.width;

    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    // Position tooltip just above the card
    final tooltipTop = cardPosition.dy - 56;

    entry = OverlayEntry(
      builder: (ctx) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => entry.remove(),
        child: Stack(
          children: [
            // Dismiss layer
            Positioned.fill(
              child: Container(color: Colors.transparent),
            ),
            // Tooltip positioned above the held card
            Positioned(
              top: tooltipTop < 60
                  ? cardPosition.dy + cardSize.height + 8
                  : tooltipTop,
              left: 16,
              right: 16,
              child: Center(
                child: Material(
                  color: Colors.transparent,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: Opacity(
                          opacity: value.clamp(0.0, 1.0),
                          child: child,
                        ),
                      );
                    },
                    child: Container(
                      constraints: BoxConstraints(maxWidth: screenWidth - 64),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.red.withValues(alpha: 0.3)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          entry.remove();
                          _showDeleteConfirmation(item);
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Icon(Icons.delete_outline,
                                color: Colors.red.withValues(alpha: 0.9),
                                size: 22),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                'Delete "${item.displayName}"',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    overlay.insert(entry);
  }

  // ─── Delete Confirmation Modal (with smooth animation + storage toggle) ─
  void _showDeleteConfirmation(DownloadItem item) {
    bool deleteFromStorage = true;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Delete Confirmation',
      barrierColor: Colors.black.withValues(alpha: 0.7),
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Material(
                color: Colors.transparent,
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.85,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.border, width: 1),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.red,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Delete Download?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Are you sure you want to delete\n"${item.displayName}"?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary.withValues(alpha: 0.8),
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Storage toggle
                      GestureDetector(
                        onTap: () {
                          setModalState(() {
                            deleteFromStorage = !deleteFromStorage;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: deleteFromStorage
                                  ? Colors.red.withValues(alpha: 0.4)
                                  : AppColors.border,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                deleteFromStorage
                                    ? Icons.check_box_rounded
                                    : Icons.check_box_outline_blank_rounded,
                                color: deleteFromStorage
                                    ? Colors.red
                                    : AppColors.textMuted,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Also delete from device storage',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(context),
                              style: TextButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side:
                                      const BorderSide(color: AppColors.border),
                                ),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                DownloadManager.instance.deleteDownload(
                                  item.id,
                                  deleteFile: deleteFromStorage,
                                );
                                CustomToast.show(
                                  context,
                                  'Deleted "${item.displayName}"',
                                  type: ToastType.info,
                                  icon: Icons.delete_sweep_rounded,
                                );
                                setState(() {});
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Delete',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // _showCancelDialog removed — cancel/X button now uses _showDeleteConfirmation directly

  // ─── Clear All Dialog (with smooth animation) ──────────────────────────
  void _showClearDialog() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Clear All',
      barrierColor: Colors.black.withValues(alpha: 0.7),
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border, width: 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.delete_sweep_rounded,
                      color: AppColors.primary,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Clear All Downloads?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This will delete all completed downloads from your device. This action cannot be undone.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: AppColors.border),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            for (final item
                                in DownloadManager.instance.completedItems) {
                              DownloadManager.instance.deleteDownload(item.id);
                            }
                            CustomToast.show(
                              context,
                              'All downloads cleared',
                              type: ToastType.success,
                              icon: Icons.done_all_rounded,
                            );
                            setState(() {});
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Clear All',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
