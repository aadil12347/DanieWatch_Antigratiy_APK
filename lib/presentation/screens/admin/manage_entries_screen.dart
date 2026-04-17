import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../../../core/utils/toast_utils.dart';
import '../../../domain/models/manifest_item.dart';
import '../../providers/admin_provider.dart';
import '../../providers/manifest_provider.dart';
import '../../../domain/models/notification_entry.dart';

/// Screen for managing content entries (Newly Added / Recently Released).
/// Supports add by TMDB ID, multi-select, bulk delete — just like Downloads screen.
class ManageEntriesScreen extends ConsumerStatefulWidget {
  final String category;
  const ManageEntriesScreen({super.key, required this.category});

  @override
  ConsumerState<ManageEntriesScreen> createState() => _ManageEntriesScreenState();
}

class _ManageEntriesScreenState extends ConsumerState<ManageEntriesScreen> {
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;

  String get _title => widget.category == 'newly_added' ? 'Newly Added' : 'Recently Released';

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
        content: const Text(
          'This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
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
      try {
        await AdminService.instance.removeEntries(_selectedIds.toList());
        _clearSelection();
        ref.invalidate(notificationEntriesProvider(widget.category));
        if (mounted) {
          CustomToast.show(context, 'Entries deleted', type: ToastType.success);
        }
      } catch (e) {
        if (mounted) {
          CustomToast.show(context, 'Failed to delete: $e', type: ToastType.error);
        }
      }
    }
  }

  Future<void> _showAddEntryDialog() async {
    final searchController = TextEditingController();
    List<ManifestItem> searchResults = [];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Add Entry',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Search your manifest by title, TMDB ID, or IMDB ID',
                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 20),

                // Search Input
                TextField(
                  controller: searchController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Search title, TMDB ID, or IMDB ID...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: AppColors.surface,
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
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

                    // Search manifest items
                    final allItems = ref.read(allItemsProvider);
                    final results = allItems.where((item) {
                      // Match by title
                      if (item.title.toLowerCase().contains(q)) return true;
                      // Match by TMDB ID
                      if (item.id.toString() == q) return true;
                      // Match by IMDB ID
                      if (item.imdbId != null && item.imdbId!.toLowerCase() == q) return true;
                      return false;
                    }).take(20).toList();

                    setSheetState(() => searchResults = results);
                  },
                ),
                const SizedBox(height: 16),

                // Results
                Expanded(
                  child: searchResults.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                searchController.text.isEmpty
                                    ? Icons.search_rounded
                                    : Icons.search_off_rounded,
                                color: AppColors.textMuted,
                                size: 48,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                searchController.text.isEmpty
                                    ? 'Type to search your catalog'
                                    : 'No results found',
                                style: GoogleFonts.inter(
                                  color: AppColors.textMuted,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: searchResults.length,
                          itemBuilder: (ctx, index) {
                            final item = searchResults[index];
                            return _buildManifestResultCard(ctx, item);
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildManifestResultCard(BuildContext ctx, ManifestItem item) {
    return GestureDetector(
      onTap: () async {
        // Convert ManifestItem → NotificationEntry
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
          await AdminService.instance.addEntry(entry);
          ref.invalidate(notificationEntriesProvider(widget.category));
          if (ctx.mounted) Navigator.pop(ctx);
          if (mounted) {
            CustomToast.show(context, '${item.title} added!', type: ToastType.success);
          }
        } catch (e) {
          if (ctx.mounted) {
            CustomToast.show(ctx, 'Failed: $e', type: ToastType.error);
          }
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: item.posterUrl != null
                  ? CachedNetworkImage(
                      imageUrl: item.posterUrl!,
                      width: 55,
                      height: 80,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _placeholder(),
                      errorWidget: (_, __, ___) => _placeholder(),
                    )
                  : _placeholder(),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _infoBadge(item.mediaType == 'tv' ? 'TV' : 'Movie'),
                      if (item.releaseYear != null) ...[
                        const SizedBox(width: 8),
                        _infoBadge('${item.releaseYear}'),
                      ],
                      const SizedBox(width: 8),
                      const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                      const SizedBox(width: 3),
                      Text(
                        item.voteAverage.toStringAsFixed(1),
                        style: GoogleFonts.inter(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'TMDB: ${item.id}${item.imdbId != null ? ' • IMDB: ${item.imdbId}' : ''}',
                    style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary, size: 24),
          ],
        ),
      ),
    );
  }

  Widget _infoBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: 60,
      height: 85,
      color: AppColors.surface,
      child: const Icon(Icons.movie_rounded, color: AppColors.textMuted, size: 28),
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
              // Select All
              entriesAsync.whenData((entries) {
                return IconButton(
                  icon: Icon(
                    _selectedIds.length == entries.length
                        ? Icons.deselect_rounded
                        : Icons.select_all_rounded,
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
              // Delete Selected
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                onPressed: _deleteSelected,
              ),
            ],
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _showAddEntryDialog,
          backgroundColor: AppColors.primary,
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
        ),
        body: entriesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => Center(
            child: Text('Error: $e', style: const TextStyle(color: AppColors.error)),
          ),
          data: (entries) {
            if (entries.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.category == 'newly_added'
                          ? Icons.new_releases_outlined
                          : Icons.movie_filter_outlined,
                      size: 64,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No entries yet',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap + to add content by TMDB ID',
                      style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final isSelected = _selectedIds.contains(entry.id);

                return GestureDetector(
                  onTap: _isSelectionMode
                      ? () => _toggleSelection(entry.id)
                      : null,
                  onLongPress: () => _activateSelection(entry.id),
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.red.withValues(alpha: 0.1)
                          : AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? Colors.red.withValues(alpha: 0.8)
                            : AppColors.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Selection checkbox
                        if (_isSelectionMode) ...[
                          Icon(
                            isSelected
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_off_rounded,
                            color: isSelected ? Colors.red : Colors.white24,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                        ],
                        // Poster
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: entry.posterUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: entry.posterUrl!,
                                  width: 55,
                                  height: 75,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => _placeholder(),
                                  errorWidget: (_, __, ___) => _placeholder(),
                                )
                              : _placeholder(),
                        ),
                        const SizedBox(width: 12),
                        // Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  _infoBadge(entry.mediaType == 'tv' ? 'TV' : 'Movie'),
                                  if (entry.releaseYear != null) ...[
                                    const SizedBox(width: 6),
                                    _infoBadge('${entry.releaseYear}'),
                                  ],
                                  const SizedBox(width: 6),
                                  Text(
                                    'ID: ${entry.tmdbId}',
                                    style: GoogleFonts.inter(
                                      color: AppColors.textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Delete button (when not in selection mode)
                        if (!_isSelectionMode)
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
                            onPressed: () async {
                              try {
                                await AdminService.instance.removeEntry(entry.id);
                                ref.invalidate(notificationEntriesProvider(widget.category));
                                if (mounted) {
                                  CustomToast.show(context, 'Removed ${entry.title}', type: ToastType.info);
                                }
                              } catch (e) {
                                if (mounted) {
                                  CustomToast.show(context, 'Failed: $e', type: ToastType.error);
                                }
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
