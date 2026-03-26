import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/local/download_manager.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/custom_pull_to_refresh.dart';
import '../video_player/video_player_screen.dart';

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  @override
  void initState() {
    super.initState();
    DownloadManager.instance.onDownloadUpdate = _onDownloadUpdate;
  }

  void _onDownloadUpdate(DownloadItem item) {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final downloads = DownloadManager.instance.downloads;
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
    final completed = downloads
        .where((d) => d.status == DownloadStatus.completed)
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomAppBar(
        extendBehindAppBar: false,
        child: downloads.isEmpty
            ? _buildEmptyState()
            : CustomPullToRefresh(
                onRefresh: () async {
                  await Future.delayed(const Duration(milliseconds: 800));
                  if (mounted) setState(() {});
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // Title header
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          top: 16,
                          left: 16,
                          right: 16,
                          bottom: 8,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Downloads',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (completed.isNotEmpty)
                              GestureDetector(
                                onTap: _showClearDialog,
                                child: const Text(
                                  'Clear All',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // Downloading section
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

                    // Completed section
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

                    // Bottom spacing for nav bar
                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
                  ],
                ),
              ),
      ),
    );
  }

  // ─── Empty State (matching watchlist style) ──────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Download arrow graphic (similar to watchlist clipboard style)
          SizedBox(
            width: 200,
            height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Back card
                Positioned(
                  left: 20,
                  top: 10,
                  child: Transform.rotate(
                    angle: -0.15,
                    child: _buildDownloadCardShape(
                      140,
                      160,
                      AppColors.surfaceElevated.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                // Front card
                Positioned(
                  right: 20,
                  top: 0,
                  child: _buildDownloadCardShape(
                    140,
                    160,
                    AppColors.surfaceElevated,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No Downloads Yet',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Movies and episodes you download\nwill appear here',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
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
          // Red accent strip at top (matching watchlist clipboard clip)
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
          // Download icon in center
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
    return Container(
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
                  textStyle: const TextStyle(color: Colors.white, fontSize: 13),
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
                    value: item.status == DownloadStatus.converting
                        ? null // Indeterminate for conversion
                        : item.progress > 0 ? item.progress : null,
                    backgroundColor: AppColors.surface,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      item.status == DownloadStatus.paused
                          ? Colors.orange
                          : item.status == DownloadStatus.failed
                            ? Colors.red
                            : item.status == DownloadStatus.converting
                              ? Colors.blue
                              : AppColors.primary,
                    ),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        item.status == DownloadStatus.paused
                            ? 'Paused · ${item.formattedDownloadedBytes}'
                            : item.status == DownloadStatus.failed
                               ? item.error ?? 'Failed'
                               : item.status == DownloadStatus.converting
                                 ? 'Converting to MP4…'
                                 : '${item.formattedDownloadedBytes} · ${item.segmentProgressLabel}',
                        style: TextStyle(
                          color: item.status == DownloadStatus.paused
                              ? Colors.orange
                              : item.status == DownloadStatus.converting
                                ? Colors.blue
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
              else if (item.status == DownloadStatus.downloading)
                IconButton(
                  icon: const Icon(Icons.pause, color: Colors.white),
                  onPressed: () {
                    DownloadManager.instance.pauseDownload(item.id);
                    setState(() {});
                  },
                ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red, size: 20),
                onPressed: () => _showCancelDialog(item),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Completed Item ─────────────────────────────────────────────────────
  Widget _buildCompletedItem(DownloadItem item) {
    return Container(
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
                  textStyle: const TextStyle(color: Colors.white, fontSize: 13),
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
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (item.qualityTag.isNotEmpty)
                      Text(
                        '${item.qualityTag} • ',
                        style: TextStyle(
                          color: AppColors.textMuted.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    Text(
                      item.formattedSize,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
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
            onTap: () => _showDeleteDialog(item),
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

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  void _playDownload(DownloadItem item) async {
    if (item.localPath != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => VideoPlayerScreen(
            url: item.localPath!,
            title: item.displayName,
            tmdbId: 0,
            mediaType: item.season > 0 ? 'tv' : 'movie',
            season: item.season,
            episode: item.episode,
            isOffline: true,
          ),
        ),
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File not found'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showDeleteDialog(DownloadItem item) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
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
                          side: BorderSide(color: AppColors.border),
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
                        DownloadManager.instance.deleteDownload(item.id);
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
      ),
    );
  }

  void _showCancelDialog(DownloadItem item) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
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
                  Icons.close_rounded,
                  color: AppColors.primary,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Cancel Download?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Stop downloading "${item.displayName}"?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary.withValues(alpha: 0.8),
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
                          side: BorderSide(color: AppColors.border),
                        ),
                      ),
                      child: const Text(
                        'No',
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
                        DownloadManager.instance.cancelDownload(item.id);
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
                        'Stop',
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
  }

  void _showClearDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
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
                          side: BorderSide(color: AppColors.border),
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
                        for (final item in DownloadManager.instance.completedItems) {
                          DownloadManager.instance.deleteDownload(item.id);
                        }
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
  }
}
