import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/toast_utils.dart';
import '../../../domain/models/support_ticket.dart';
import '../../providers/support_provider.dart';

class AdminSupportInboxScreen extends ConsumerStatefulWidget {
  const AdminSupportInboxScreen({super.key});

  @override
  ConsumerState<AdminSupportInboxScreen> createState() =>
      _AdminSupportInboxScreenState();
}

class _AdminSupportInboxScreenState
    extends ConsumerState<AdminSupportInboxScreen> {
  String _categoryFilter = 'all';
  String _statusFilter = 'all';
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  static const _categoryFilters = [
    {'value': 'all', 'label': 'All Categories'},
    {'value': 'add_movie', 'label': 'Movie'},
    {'value': 'add_tv_show', 'label': 'TV Show'},
    {'value': 'bug_report', 'label': 'Bug'},
    {'value': 'feature_request', 'label': 'Feature'},
    {'value': 'other', 'label': 'Other'},
  ];

  static const _statusFilters = [
    {'value': 'all', 'label': 'All Status'},
    {'value': 'new', 'label': 'New'},
    {'value': 'pending', 'label': 'Pending'},
    {'value': 'completed', 'label': 'Completed'},
    {'value': 'rejected', 'label': 'Rejected'},
  ];

  List<SupportTicket> _applyFilters(List<SupportTicket> tickets) {
    return tickets.where((t) {
      if (_categoryFilter != 'all' && t.category != _categoryFilter) return false;
      if (_statusFilter != 'all' && t.status != _statusFilter) return false;
      return true;
    }).toList();
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll(List<SupportTicket> tickets) {
    setState(() {
      if (_selectedIds.length == tickets.length) {
        _selectedIds.clear();
        _selectionMode = false;
      } else {
        _selectedIds.addAll(tickets.map((t) => t.id));
      }
    });
  }

  Future<void> _bulkChangeStatus(String newStatus) async {
    if (_selectedIds.isEmpty) return;
    final service = ref.read(supportServiceProvider);
    final success = await service.bulkUpdateStatus(
      _selectedIds.toList(),
      newStatus,
    );
    if (mounted) {
      if (success) {
        CustomToast.show(
          context,
          'Updated ${_selectedIds.length} ticket(s)',
          type: ToastType.success,
        );
        setState(() {
          _selectedIds.clear();
          _selectionMode = false;
        });
      } else {
        CustomToast.show(context, 'Failed to update', type: ToastType.error);
      }
    }
  }

  Future<void> _showBulkReplyDialog() async {
    if (_selectedIds.isEmpty) return;
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Bulk Reply (${_selectedIds.length} tickets)',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            fontSize: 18,
          ),
        ),
        content: TextField(
          controller: controller,
          maxLines: 4,
          style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Type your reply...',
            hintStyle: GoogleFonts.inter(color: AppColors.textHint),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(
              'Send',
              style: GoogleFonts.inter(
                color: const Color(0xFF059669),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final service = ref.read(supportServiceProvider);
      final success = await service.bulkReply(_selectedIds.toList(), result);
      if (mounted) {
        if (success) {
          CustomToast.show(
            context,
            'Replied to ${_selectedIds.length} ticket(s)',
            type: ToastType.success,
          );
          setState(() {
            _selectedIds.clear();
            _selectionMode = false;
          });
        } else {
          CustomToast.show(context, 'Failed to send', type: ToastType.error);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticketsAsync = ref.watch(allTicketsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(ticketsAsync),
      body: Column(
        children: [
          // Filter bar
          _buildFilterBar(),

          // Ticket list
          Expanded(
            child: ticketsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (e, _) => Center(
                child: Text('Error: $e', style: const TextStyle(color: AppColors.textMuted)),
              ),
              data: (tickets) {
                final filtered = _applyFilters(tickets);
                if (filtered.isEmpty) {
                  return _buildEmptyState();
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) => _AdminTicketCard(
                    ticket: filtered[index],
                    isSelected: _selectedIds.contains(filtered[index].id),
                    selectionMode: _selectionMode,
                    onTap: () {
                      if (_selectionMode) {
                        _toggleSelection(filtered[index].id);
                      } else {
                        context.push('/requests/chat/${filtered[index].id}');
                      }
                    },
                    onLongPress: () {
                      setState(() {
                        _selectionMode = true;
                        _selectedIds.add(filtered[index].id);
                      });
                    },
                  ),
                );
              },
            ),
          ),

          // Bulk action bar
          if (_selectionMode && _selectedIds.isNotEmpty) _buildBulkActionBar(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(AsyncValue<List<SupportTicket>> ticketsAsync) {
    final totalCount = ticketsAsync.whenOrNull(data: (t) => t.length) ?? 0;

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
        onPressed: () {
          if (_selectionMode) {
            setState(() {
              _selectionMode = false;
              _selectedIds.clear();
            });
          } else {
            context.pop();
          }
        },
      ),
      title: _selectionMode
          ? Text(
              '${_selectedIds.length} selected',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Support Inbox',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
                ),
                Text(
                  '$totalCount ticket${totalCount == 1 ? '' : 's'}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
      actions: [
        if (_selectionMode)
          IconButton(
            icon: const Icon(Icons.select_all_rounded),
            onPressed: () {
              final tickets = ref.read(allTicketsProvider).valueOrNull ?? [];
              _selectAll(_applyFilters(tickets));
            },
            tooltip: 'Select All',
          ),
        if (_selectionMode)
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () {
              setState(() {
                _selectionMode = false;
                _selectedIds.clear();
              });
            },
          ),
      ],
      backgroundColor: Colors.transparent,
      elevation: 0,
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(child: _buildDropdown(_categoryFilter, _categoryFilters, (v) {
            setState(() => _categoryFilter = v);
          })),
          const SizedBox(width: 10),
          Expanded(child: _buildDropdown(_statusFilter, _statusFilters, (v) {
            setState(() => _statusFilter = v);
          })),
        ],
      ),
    );
  }

  Widget _buildDropdown(
    String value,
    List<Map<String, String>> items,
    ValueChanged<String> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.textMuted, size: 18),
          items: items.map((item) {
            return DropdownMenuItem<String>(
              value: item['value'],
              child: Text(
                item['label']!,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  Widget _buildBulkActionBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16, 12, 16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Row(
        children: [
          // Bulk status change
          Expanded(
            child: _BulkActionButton(
              icon: Icons.swap_horiz_rounded,
              label: 'Status',
              color: const Color(0xFF3B82F6),
              onTap: () => _showStatusPicker(),
            ),
          ),
          const SizedBox(width: 10),
          // Bulk reply
          Expanded(
            child: _BulkActionButton(
              icon: Icons.reply_all_rounded,
              label: 'Reply All',
              color: const Color(0xFF059669),
              onTap: _showBulkReplyDialog,
            ),
          ),
          const SizedBox(width: 10),
          // Deselect
          _BulkActionButton(
            icon: Icons.deselect_rounded,
            label: 'Clear',
            color: AppColors.textMuted,
            onTap: () {
              setState(() {
                _selectedIds.clear();
                _selectionMode = false;
              });
            },
            compact: true,
          ),
        ],
      ),
    );
  }

  void _showStatusPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textHint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Change Status (${_selectedIds.length} tickets)',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            _statusOption('new', 'New', const Color(0xFF3B82F6)),
            _statusOption('pending', 'Pending', const Color(0xFFF59E0B)),
            _statusOption('completed', 'Completed', const Color(0xFF10B981)),
            _statusOption('rejected', 'Rejected', const Color(0xFFEF4444)),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  Widget _statusOption(String value, String label, Color color) {
    return ListTile(
      leading: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      title: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: () {
        Navigator.pop(context);
        _bulkChangeStatus(value);
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_rounded, size: 48, color: AppColors.textHint),
          const SizedBox(height: 16),
          Text(
            'No tickets found',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Try adjusting your filters',
            style: GoogleFonts.inter(fontSize: 13, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }
}

// ─── Admin Ticket Card ────────────────────────────────────────────────────

class _AdminTicketCard extends StatelessWidget {
  final SupportTicket ticket;
  final bool isSelected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _AdminTicketCard({
    required this.ticket,
    required this.isSelected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(16),
          splashColor: ticket.categoryColor.withValues(alpha: 0.08),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isSelected
                  ? ticket.categoryColor.withValues(alpha: 0.08)
                  : AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? ticket.categoryColor.withValues(alpha: 0.4)
                    : ticket.unreadByAdmin
                        ? const Color(0xFF059669).withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.04),
              ),
            ),
            child: Row(
              children: [
                // Selection checkbox or avatar
                if (selectionMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? ticket.categoryColor
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSelected
                              ? ticket.categoryColor
                              : AppColors.textHint,
                          width: 1.5,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                          : null,
                    ),
                  )
                else
                  // User avatar
                  Container(
                    width: 36,
                    height: 36,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          ticket.categoryColor.withValues(alpha: 0.3),
                          ticket.categoryColor.withValues(alpha: 0.1),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ticket.userAvatarUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              ticket.userAvatarUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Center(
                                child: Text(
                                  (ticket.username ?? '?')[0].toUpperCase(),
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: ticket.categoryColor,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              (ticket.username ?? '?')[0].toUpperCase(),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: ticket.categoryColor,
                              ),
                            ),
                          ),
                  ),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (ticket.username != null)
                            Text(
                              '@${ticket.username}',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: ticket.categoryColor,
                              ),
                            ),
                          const Spacer(),
                          Text(
                            ticket.timeAgo,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: AppColors.textHint,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        ticket.subject,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: ticket.unreadByAdmin
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      if (ticket.lastMessagePreview != null)
                        Text(
                          ticket.lastMessagePreview!,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          // Category chip
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: ticket.categoryColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(ticket.categoryIcon,
                                    size: 10, color: ticket.categoryColor),
                                const SizedBox(width: 3),
                                Text(
                                  ticket.categoryLabel,
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: ticket.categoryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Status badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: ticket.statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              ticket.statusLabel,
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: ticket.statusColor,
                              ),
                            ),
                          ),
                          const Spacer(),
                          // Unread dot
                          if (ticket.unreadByAdmin)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: const Color(0xFF059669),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF059669).withValues(alpha: 0.5),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Bulk Action Button ───────────────────────────────────────────────────

class _BulkActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool compact;

  const _BulkActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 16,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
