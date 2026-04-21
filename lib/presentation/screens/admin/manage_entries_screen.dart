import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../../../core/utils/toast_utils.dart';
import '../../../domain/models/manifest_item.dart';
import '../../providers/admin_provider.dart';
import '../../providers/manifest_provider.dart';
import '../../../domain/models/notification_entry.dart';
import '../../../domain/models/app_notification.dart';

/// Unified screen for managing entries AND sending notifications.
/// Supports both "Latest Released" (manual) and "Recently Added" (auto-add).
class ManageEntriesScreen extends ConsumerStatefulWidget {
  final String category;
  const ManageEntriesScreen({super.key, required this.category});

  @override
  ConsumerState<ManageEntriesScreen> createState() => _ManageEntriesScreenState();
}

class _ManageEntriesScreenState extends ConsumerState<ManageEntriesScreen> {
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;
  bool _isSending = false;
  bool _isAutoAdding = false;

  bool get _isRecentlyAdded => widget.category == 'recently_released';
  String get _title => _isRecentlyAdded ? 'Recently Added' : 'Latest Released';
  Color get _accentColor => _isRecentlyAdded ? const Color(0xFF0891B2) : const Color(0xFF7C3AED);

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _activateSelection(String id) {
    HapticFeedback.mediumImpact();
    setState(() {
      _isSelectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _selectAll(List<NotificationEntry> entries) {
    setState(() {
      _isSelectionMode = true;
      _selectedIds.addAll(entries.map((e) => e.id));
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
      _isSelectionMode = false;
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete ${_selectedIds.length} entries?',
          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: const Text('This action cannot be undone.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final notifier = ref.read(notificationEntriesProvider(widget.category).notifier);
      final success = await notifier.removeEntries(_selectedIds.toList());
      _clearSelection();
      if (mounted) {
        CustomToast.show(context, success ? 'Entries deleted' : 'Failed to delete', type: success ? ToastType.success : ToastType.error);
      }
    }
  }

  /// Auto-add items by comparing old vs new index
  Future<void> _autoAddItems() async {
    setState(() => _isAutoAdding = true);
    final count = await AdminService.instance.autoAddRecentlyAdded();
    setState(() => _isAutoAdding = false);

    if (mounted) {
      if (count > 0) {
        CustomToast.show(context, '$count new items added!', type: ToastType.success);
        ref.invalidate(notificationEntriesProvider(widget.category));
      } else {
        CustomToast.show(context, 'No new items found', type: ToastType.info);
      }
    }
  }

  /// Send notifications for all entries in this category
  Future<void> _sendNotifications() async {
    final entriesAsync = ref.read(notificationEntriesProvider(widget.category));
    final entries = entriesAsync.valueOrNull ?? [];
    if (entries.isEmpty) {
      if (mounted) CustomToast.show(context, 'No entries to send', type: ToastType.error);
      return;
    }

    final uiLabel = AdminService.getCategoryLabel(widget.category);
    final isCombined = widget.category == 'recently_released';
    final description = isCombined
        ? 'Send ${entries.length} entries as 1 combined notification?'
        : 'Send ${entries.length} entries as ${entries.length} individual notifications?';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Send $uiLabel',
          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(description, style: GoogleFonts.inter(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Send', style: GoogleFonts.inter(color: _accentColor, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSending = true);
    final count = await AdminService.instance.sendCategoryNotifications(widget.category);
    setState(() => _isSending = false);

    if (mounted) {
      if (count > 0) {
        CustomToast.show(context, '$count notifications sent!', type: ToastType.success);
      } else {
        CustomToast.show(context, 'Failed to send', type: ToastType.error);
      }
    }
  }

  Future<void> _showAddEntryDialog() async {
    final searchController = TextEditingController();
    List<ManifestItem> searchResults = [];
    final addedTmdbIds = <int>{};
    int addedCount = 0;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Container(
            height: MediaQuery.of(ctx).size.height * 0.85,
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 24,
              right: 24,
              top: 24,
            ),
            decoration: const BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header with drag handle and Done button
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add Entry',
                            style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            addedCount > 0
                                ? '$addedCount added · Search by title, TMDB ID, or IMDB ID'
                                : 'Search by title, TMDB ID, or IMDB ID',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: addedCount > 0 ? const Color(0xFF22C55E) : AppColors.textSecondary,
                              fontWeight: addedCount > 0 ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.check_circle_rounded, size: 18),
                      label: const Text('Done'),
                      style: TextButton.styleFrom(
                        foregroundColor: _accentColor,
                        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: searchController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Search title, TMDB ID, or IMDB ID...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: AppColors.surface,
                    prefixIcon: Icon(Icons.search_rounded, color: _accentColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    suffixIcon: searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, color: Colors.white38),
                            onPressed: () {
                              searchController.clear();
                              setSheetState(() => searchResults = []);
                            },
                          )
                        : null,
                  ),
                  onChanged: (query) {
                    final q = query.trim().toLowerCase();
                    if (q.isEmpty) {
                      setSheetState(() => searchResults = []);
                      return;
                    }
                    final allItems = ref.read(allItemsProvider);
                    // Check if query looks like a TMDB ID (all digits) or IMDB ID (starts with tt)
                    final isIdQuery = RegExp(r'^\d+$').hasMatch(q) || q.startsWith('tt');
                    final results = allItems.where((item) {
                      if (isIdQuery) {
                        // Exact match only for TMDB ID or IMDB ID
                        if (item.id.toString() == q) return true;
                        if (item.imdbId != null && item.imdbId!.toLowerCase() == q) return true;
                        return false;
                      }
                      // Title search: contains match
                      return item.title.toLowerCase().contains(q);
                    }).take(20).toList();
                    setSheetState(() => searchResults = results);
                  },
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: searchResults.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                searchController.text.isEmpty ? Icons.search_rounded : Icons.search_off_rounded,
                                color: AppColors.textMuted, size: 48,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                searchController.text.isEmpty ? 'Type to search your catalog' : 'No results found',
                                style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: searchResults.length,
                          itemBuilder: (ctx, index) {
                            final item = searchResults[index];
                            final alreadyAdded = addedTmdbIds.contains(item.id);
                            return _buildManifestResultCard(
                              ctx, item, alreadyAdded,
                              onAdded: () {
                                setSheetState(() {
                                  addedTmdbIds.add(item.id);
                                  addedCount++;
                                });
                                // Clear search for next item
                                searchController.clear();
                                setSheetState(() => searchResults = []);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );

    // Refresh entries list when sheet closes if items were added
    if (addedCount > 0) {
      ref.invalidate(notificationEntriesProvider(widget.category));
    }
  }

  Widget _buildManifestResultCard(BuildContext ctx, ManifestItem item, bool alreadyAdded, {VoidCallback? onAdded}) {
    return GestureDetector(
      onTap: alreadyAdded
          ? null
          : () async {
              final entry = NotificationEntry(
                id: '',
                tmdbId: item.id,
                mediaType: item.mediaType,
                title: item.title,
                posterUrl: item.posterUrl,
                backdropUrl: item.backdropUrl,
                releaseYear: item.releaseYear,
                voteAverage: item.voteAverage,
                category: widget.category,
                createdAt: DateTime.now(),
              );
              try {
                final notifier = ref.read(notificationEntriesProvider(widget.category).notifier);
                final success = await notifier.addEntry(entry);
                if (success) {
                  onAdded?.call();
                }
                if (mounted) {
                  CustomToast.show(context, success ? '${item.title} added!' : 'Failed to add', type: success ? ToastType.success : ToastType.error);
                }
              } catch (e) {
                if (ctx.mounted) CustomToast.show(ctx, 'Failed: $e', type: ToastType.error);
              }
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: alreadyAdded ? const Color(0xFF22C55E).withValues(alpha: 0.06) : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: alreadyAdded ? const Color(0xFF22C55E).withValues(alpha: 0.4) : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: item.posterUrl != null
                  ? CachedNetworkImage(imageUrl: item.posterUrl!, width: 50, height: 72, fit: BoxFit.cover,
                      placeholder: (_, __) => _placeholder(), errorWidget: (_, __, ___) => _placeholder())
                  : _placeholder(),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: GoogleFonts.plusJakartaSans(
                    color: alreadyAdded ? const Color(0xFF22C55E) : Colors.white,
                    fontWeight: FontWeight.w700, fontSize: 14),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Row(children: [
                    _infoBadge(item.mediaType == 'tv' ? 'TV' : 'Movie'),
                    if (item.releaseYear != null) ...[const SizedBox(width: 8), _infoBadge('${item.releaseYear}')],
                    const SizedBox(width: 8),
                    Text('TMDB: ${item.id}', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 10)),
                  ]),
                ],
              ),
            ),
            alreadyAdded
                ? const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 24)
                : Icon(Icons.add_circle_outline_rounded, color: _accentColor, size: 24),
          ],
        ),
      ),
    );
  }

  Widget _infoBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _accentColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: GoogleFonts.inter(color: _accentColor, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Widget _placeholder() {
    return Container(
      width: 50, height: 72,
      color: AppColors.surface,
      child: const Icon(Icons.movie_rounded, color: AppColors.textMuted, size: 24),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(notificationEntriesProvider(widget.category));

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _clearSelection();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () {
              if (_isSelectionMode) {
                _clearSelection();
              } else {
                context.pop();
              }
            },
          ),
          title: Text(
            _isSelectionMode ? '${_selectedIds.length} Selected' : _title,
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            if (_isSelectionMode) ...[
              entriesAsync.whenData((entries) {
                return IconButton(
                  icon: Icon(
                    _selectedIds.length == entries.length ? Icons.deselect_rounded : Icons.select_all_rounded,
                    color: Colors.white70,
                  ),
                  onPressed: () {
                    if (_selectedIds.length == entries.length) {
                      _clearSelection();
                    } else {
                      _selectAll(entries);
                    }
                  },
                );
              }).valueOrNull ?? const SizedBox.shrink(),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                onPressed: _deleteSelected,
              ),
            ] else ...[
              // History button
              IconButton(
                icon: const Icon(Icons.history_rounded, color: Colors.white54),
                tooltip: 'Sent History',
                onPressed: () => _showHistorySheet(context),
              ),
              // Auto-Add button (only for Recently Added)
              if (_isRecentlyAdded)
                _isAutoAdding
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0891B2))),
                      )
                    : IconButton(
                        icon: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF0891B2)),
                        tooltip: 'Auto-Add New Items',
                        onPressed: _autoAddItems,
                      ),
              // Send button
              _isSending
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                    )
                  : IconButton(
                      icon: Icon(Icons.send_rounded, color: _accentColor),
                      tooltip: 'Send Notifications',
                      onPressed: _sendNotifications,
                    ),
            ],
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _showAddEntryDialog,
          backgroundColor: _accentColor,
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
        ),
        body: entriesAsync.when(
          loading: () => Center(child: CircularProgressIndicator(color: _accentColor)),
          error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.error))),
          data: (entries) {
            if (entries.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isRecentlyAdded ? Icons.movie_filter_outlined : Icons.new_releases_outlined,
                      size: 56, color: AppColors.textMuted,
                    ),
                    const SizedBox(height: 16),
                    Text('No entries yet', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    Text(
                      _isRecentlyAdded ? 'Tap ✨ to auto-add or + to add manually' : 'Tap + to add content',
                      style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: [
                // Top status bar
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: _accentColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _accentColor.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: _accentColor, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        '${entries.length} entries ready',
                        style: GoogleFonts.inter(color: _accentColor, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                // Entry list
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final isSelected = _selectedIds.contains(entry.id);
                      return _buildEntryCard(entry, isSelected);
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildEntryCard(NotificationEntry entry, bool isSelected) {
    return GestureDetector(
      onTap: _isSelectionMode ? () => _toggleSelection(entry.id) : null,
      onLongPress: () => _activateSelection(entry.id),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.red.withValues(alpha: 0.08) : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? Colors.red.withValues(alpha: 0.6) : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            if (_isSelectionMode) ...[
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
                color: isSelected ? Colors.red : Colors.white24, size: 20,
              ),
              const SizedBox(width: 12),
            ],
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: entry.posterUrl != null
                  ? CachedNetworkImage(imageUrl: entry.posterUrl!, width: 50, height: 70, fit: BoxFit.cover,
                      placeholder: (_, __) => _placeholder(), errorWidget: (_, __, ___) => _placeholder())
                  : _placeholder(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 5),
                  Row(children: [
                    _infoBadge(entry.mediaType == 'tv' ? 'TV' : 'Movie'),
                    if (entry.releaseYear != null) ...[const SizedBox(width: 6), _infoBadge('${entry.releaseYear}')],
                    const SizedBox(width: 6),
                    Text('ID: ${entry.tmdbId}', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 11)),
                  ]),
                ],
              ),
            ),
            if (!_isSelectionMode)
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                onPressed: () async {
                  final notifier = ref.read(notificationEntriesProvider(widget.category).notifier);
                  final success = await notifier.removeEntry(entry.id);
                  if (mounted) {
                    CustomToast.show(context, success ? 'Removed ${entry.title}' : 'Failed to remove', type: success ? ToastType.info : ToastType.error);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Show bottom sheet with per-category notification history (last 7 days)
  void _showHistorySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.7,
        decoration: const BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.history_rounded, color: _accentColor, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    '$_title History (7 days)',
                    style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            Expanded(
              child: Consumer(
                builder: (ctx, ref, _) {
                  final historyAsync = ref.watch(categoryNotificationHistoryProvider(widget.category));
                  return historyAsync.when(
                    loading: () => Center(child: CircularProgressIndicator(color: _accentColor)),
                    error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.error))),
                    data: (notifications) {
                      if (notifications.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.notifications_off_outlined, color: AppColors.textMuted, size: 48),
                              const SizedBox(height: 12),
                              Text('No notifications sent yet', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14)),
                            ],
                          ),
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: notifications.length,
                        itemBuilder: (ctx, index) {
                          final n = notifications[index];
                          return _buildHistoryCard(n);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard(AppNotification notification) {
    final timeStr = DateFormat('MMM d, h:mm a').format(notification.createdAt);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            notification.title,
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            notification.body,
            style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.schedule_rounded, color: AppColors.textMuted, size: 14),
              const SizedBox(width: 4),
              Text(timeStr, style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}
