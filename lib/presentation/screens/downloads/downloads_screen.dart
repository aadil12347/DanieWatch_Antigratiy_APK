import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:open_file/open_file.dart';

import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../../../data/local/download_manager.dart';
import '../../widgets/category_header.dart';
import '../../widgets/empty_results_view.dart';
import '../../providers/search_provider.dart';
import '../../../core/utils/toast_utils.dart';
import '../../providers/downloads_selection_provider.dart';
import '../../providers/confirmation_modal_provider.dart';
import '../../providers/scroll_provider.dart';

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  StreamSubscription? _updateSub;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _updateSub =
        DownloadManager.instance.updateStream.listen(_onDownloadUpdate);
    _searchFocus.addListener(_onFocusChange);

    // Register the controller for Downloads tab (index 3)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(scrollProvider).register(3, _scrollController);
    });
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ref.read(scrollProvider).unregister(3);
    _scrollController.dispose();
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

    final selectionState = ref.watch(downloadsSelectionProvider);
    final isSelectionMode = selectionState.isSelectionMode;

    return PopScope(
      canPop: !isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        ref.read(downloadsSelectionProvider.notifier).clear();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: GestureDetector(
            onTap: () => _searchFocus.unfocus(),
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // Title scrolls with content
                const SliverToBoxAdapter(
                  child: CategoryTitle(title: 'Downloads'),
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
                if (allDownloads.isEmpty)
                  const SliverFillRemaining(
                    child: EmptyResultsView(
                      title: 'No Downloads Yet',
                      message: 'Movies and episodes you download will appear here',
                      icon: Icons.download_rounded,
                    ),
                  )
                else if (downloads.isEmpty && (searchState.query.isNotEmpty || searchState.filters.hasActiveFilters))
                  const SliverFillRemaining(
                    child: EmptyResultsView(),
                  )
                else ...[
                  if (downloading.isNotEmpty) ...[
                    _buildSectionHeader(
                      'DOWNLOADING (${downloading.length})',
                      trailing: isSelectionMode
                          ? _buildBulkDeleteButton(selectionState.selectedIds)
                          : null,
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _buildDownloadingItem(downloading[index]),
                        childCount: downloading.length,
                      ),
                    ),
                  ],
                  if (completed.isNotEmpty) ...[
                    _buildSectionHeader(
                      'DOWNLOADED (${completed.length})',
                      trailing: isSelectionMode
                          ? _buildBulkDeleteButton(selectionState.selectedIds)
                          : GestureDetector(
                              onTap: _showClearDialog,
                              child: Text(
                                'Clear All',
                                style: GoogleFonts.inter(
                                  color: AppColors.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _buildCompletedItem(completed[index]),
                        childCount: completed.length,
                      ),
                    ),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }


  // ─── Section Header ─────────────────────────────────────────────────────
  Widget _buildSectionHeader(String title, {Widget? trailing}) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildBulkDeleteButton(Set<String> ids) {
    if (ids.isEmpty) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => _showBulkDeleteConfirmation(ids),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 16),
          const SizedBox(width: 4),
          Text(
            'Delete (${ids.length})',
            style: GoogleFonts.inter(
              color: Colors.redAccent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Downloading Item ───────────────────────────────────────────────────
  Widget _buildDownloadingItem(DownloadItem item) {
    final pct = (item.progress * 100).toInt().clamp(0, 100);
    final selectionState = ref.watch(downloadsSelectionProvider);
    final isSelected = selectionState.selectedIds.contains(item.id);
    final isSelectionMode = selectionState.isSelectionMode;

    return GestureDetector(
      onTap: isSelectionMode
          ? () => ref.read(downloadsSelectionProvider.notifier).toggleItem(item.id)
          : null,
      onLongPress: () {
        HapticFeedback.mediumImpact();
        ref.read(downloadsSelectionProvider.notifier).activate(item.id);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.red.withValues(alpha: 0.1)
              : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Colors.red.withValues(alpha: 0.8)
                : AppColors.border,
            width: 1.0,
          ),
        ),
        child: Row(
          children: [
            // Selection Indicator (Reserved Space to prevent glitch/shift)
            SizedBox(
              width: isSelectionMode ? 32 : 0,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: isSelectionMode
                    ? Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_off_rounded,
                        color: isSelected ? Colors.red : Colors.white24,
                        size: 20,
                        key: const ValueKey('selected'),
                      )
                    : const SizedBox.shrink(key: ValueKey('empty')),
              ),
            ),
            if (isSelectionMode) const SizedBox(width: 4),
            // Thumbnail with Delete Overlay
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
                  // Size (Hide if unknown)
                  if (item.totalBytes > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.formattedSize,
                      style: TextStyle(
                        color: AppColors.textSecondary.withValues(alpha: 0.7),
                        fontSize: 12,
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
                  Text(
                    _getProgressText(item, pct),
                    style: TextStyle(
                      color: item.status == DownloadStatus.paused
                          ? Colors.orange
                          : item.status == DownloadStatus.failed
                              ? Colors.red
                              : AppColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            // Controls Column (at the end)
            if (!isSelectionMode) ...[
              const SizedBox(width: 12),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Pause/Resume (Top)
                  GestureDetector(
                    onTap: () {
                      if (item.status == DownloadStatus.paused) {
                        DownloadManager.instance.resumeDownload(item.id);
                      } else {
                        DownloadManager.instance.pauseDownload(item.id);
                      }
                      setState(() {});
                    },
                    child: Icon(
                      item.status == DownloadStatus.paused
                          ? Icons.play_circle_outline_rounded
                          : Icons.pause_circle_outline_rounded,
                      color: item.status == DownloadStatus.paused
                          ? Colors.orange
                          : AppColors.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Delete (Bottom)
                  GestureDetector(
                    onTap: () => _showDeleteConfirmation(item),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.redAccent,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ],
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
    final selectionState = ref.watch(downloadsSelectionProvider);
    final isSelected = selectionState.selectedIds.contains(item.id);
    final isSelectionMode = selectionState.isSelectionMode;

    return GestureDetector(
      onTap: isSelectionMode
          ? () => ref.read(downloadsSelectionProvider.notifier).toggleItem(item.id)
          : () => _playDownload(item),
      onLongPress: () {
        HapticFeedback.mediumImpact();
        ref.read(downloadsSelectionProvider.notifier).activate(item.id);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.red.withValues(alpha: 0.1)
              : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Colors.red.withValues(alpha: 0.8)
                : AppColors.border,
            width: 1.0,
          ),
        ),
        child: Row(
          children: [
            if (isSelectionMode) ...[
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
                color: isSelected ? Colors.red : Colors.white24,
                size: 20,
              ),
              const SizedBox(width: 12),
            ],
            // Thumbnail with Delete Overlay
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
                  // Size (Hide if unknown)
                  if (item.totalBytes > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.formattedSize,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Controls Column (at the end)
            if (!isSelectionMode) ...[
              const SizedBox(width: 12),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => _showDeleteConfirmation(item),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.redAccent,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ],
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

  // ─── Delete Confirmation Modal (with smooth animation + storage toggle) ─
  void _showDeleteConfirmation(DownloadItem item) {
    ref.read(confirmationModalProvider.notifier).state =
        ConfirmationModalState(
      isOpen: true,
      title: 'Delete Download?',
      message: 'Are you sure you want to delete "${item.displayName}"?',
      showDeviceDeleteToggle: item.status == DownloadStatus.completed,
      onConfirm: (alsoDeleteFile) {
        DownloadManager.instance.deleteDownload(item.id, deleteFile: alsoDeleteFile);
        CustomToast.show(
          context,
          'Deleted "${item.displayName}"',
          type: ToastType.info,
          icon: Icons.delete_sweep_rounded,
        );
        setState(() {});
      },
    );
  }

  void _showBulkDeleteConfirmation(Set<String> ids) {
    ref.read(confirmationModalProvider.notifier).state =
        ConfirmationModalState(
      isOpen: true,
      title: 'Delete ${ids.length} Downloads?',
      message: 'Are you sure you want to delete these ${ids.length} items?',
      showDeviceDeleteToggle: true,
      onConfirm: (alsoDeleteFile) {
        for (final id in ids) {
          DownloadManager.instance.deleteDownload(id, deleteFile: alsoDeleteFile);
        }
        ref.read(downloadsSelectionProvider.notifier).clear();
        CustomToast.show(
          context,
          'Deleted ${ids.length} items',
          type: ToastType.info,
          icon: Icons.delete_sweep_rounded,
        );
        setState(() {});
      },
    );
  }

  void _showClearDialog() {
    ref.read(confirmationModalProvider.notifier).state =
        ConfirmationModalState(
      isOpen: true,
      title: 'Clear All Downloads?',
      message: 'This will remove all completed downloads from your list.',
      showDeviceDeleteToggle: true,
      onConfirm: (alsoDeleteFile) {
        final completed = DownloadManager.instance.downloads
            .where((d) => d.status == DownloadStatus.completed)
            .toList();
        for (final item in completed) {
          DownloadManager.instance.deleteDownload(item.id, deleteFile: alsoDeleteFile);
        }
        CustomToast.show(
          context,
          'Cleared all downloads',
          type: ToastType.info,
          icon: Icons.delete_sweep_rounded,
        );
        setState(() {});
      },
    );
  }
}
