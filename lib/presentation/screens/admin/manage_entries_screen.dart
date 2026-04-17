import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../../../core/utils/toast_utils.dart';
import '../../../core/services/tmdb_fetch_service.dart';
import '../../providers/admin_provider.dart';
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
    final tmdbIdController = TextEditingController();
    String selectedType = 'movie';
    NotificationEntry? preview;
    bool isLoading = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Container(
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
            child: SingleChildScrollView(
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
                    'Enter a TMDB ID to auto-fetch movie details',
                    style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),

                  // Media Type Toggle
                  Row(
                    children: [
                      _buildTypeChip('Movie', 'movie', selectedType, (val) {
                        setSheetState(() => selectedType = val);
                      }),
                      const SizedBox(width: 12),
                      _buildTypeChip('TV Series', 'tv', selectedType, (val) {
                        setSheetState(() => selectedType = val);
                      }),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // TMDB ID Input
                  TextField(
                    controller: tmdbIdController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'TMDB ID (e.g. 550 for Fight Club)',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        icon: isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                              )
                            : const Icon(Icons.search_rounded, color: AppColors.primary),
                        onPressed: isLoading
                            ? null
                            : () async {
                                final id = int.tryParse(tmdbIdController.text.trim());
                                if (id == null) {
                                  CustomToast.show(ctx, 'Enter a valid TMDB ID', type: ToastType.error);
                                  return;
                                }
                                setSheetState(() => isLoading = true);
                                final result = await TmdbFetchService.instance.fetchByTmdbId(
                                  tmdbId: id,
                                  mediaType: selectedType,
                                  category: widget.category,
                                );
                                setSheetState(() {
                                  preview = result;
                                  isLoading = false;
                                });
                                if (result == null && ctx.mounted) {
                                  CustomToast.show(ctx, 'Not found on TMDB', type: ToastType.error);
                                }
                              },
                      ),
                    ),
                  ),

                  // Preview Card
                  if (preview != null) ...[
                    const SizedBox(height: 20),
                    _buildPreviewCard(preview!),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () async {
                        try {
                          await AdminService.instance.addEntry(preview!);
                          ref.invalidate(notificationEntriesProvider(widget.category));
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            CustomToast.show(context, '${preview!.title} added!', type: ToastType.success);
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            CustomToast.show(ctx, 'Failed: $e', type: ToastType.error);
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        'Save Entry',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTypeChip(String label, String value, String selected, void Function(String) onTap) {
    final isActive = selected == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary.withValues(alpha: 0.2) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: isActive ? AppColors.primary : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewCard(NotificationEntry entry) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: entry.posterUrl != null
                ? CachedNetworkImage(
                    imageUrl: entry.posterUrl!,
                    width: 60,
                    height: 85,
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
                  entry.title,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _infoBadge(entry.mediaType == 'tv' ? 'TV' : 'Movie'),
                    if (entry.releaseYear != null) ...[
                      const SizedBox(width: 8),
                      _infoBadge('${entry.releaseYear}'),
                    ],
                    const SizedBox(width: 8),
                    const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                    const SizedBox(width: 3),
                    Text(
                      entry.voteAverage.toStringAsFixed(1),
                      style: GoogleFonts.inter(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
