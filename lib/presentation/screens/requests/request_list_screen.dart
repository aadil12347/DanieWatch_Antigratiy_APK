import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/toast_utils.dart';
import '../../../domain/models/support_ticket.dart';
import '../../providers/support_provider.dart';

class RequestListScreen extends ConsumerStatefulWidget {
  const RequestListScreen({super.key});

  @override
  ConsumerState<RequestListScreen> createState() => _RequestListScreenState();
}

class _RequestListScreenState extends ConsumerState<RequestListScreen> {
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    // Load hidden ticket IDs from SharedPreferences
    WidgetsBinding.instance.addPostFrameCallback((_) {
      loadHiddenTicketIds(ref, isAdmin: false);
    });
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

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;

    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete $count request${count > 1 ? 's' : ''}?',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'This will permanently delete ${count > 1 ? 'these requests' : 'this request'} and all messages. This cannot be undone.',
          style: GoogleFonts.inter(
            fontSize: 14,
            color: AppColors.textMuted,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: GoogleFonts.inter(
              color: const Color(0xFFEF4444),
              fontWeight: FontWeight.w600,
            )),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final service = ref.read(supportServiceProvider);
    await service.deleteTickets(_selectedIds.toList());

    // Invalidate the provider to refresh the list from Supabase
    ref.invalidate(userTicketsProvider);

    if (mounted) {
      CustomToast.show(context, 'Deleted $count request${count > 1 ? 's' : ''}', type: ToastType.success);
      setState(() {
        _selectedIds.clear();
        _selectionMode = false;
      });
    }
  }

  void _exitSelectionMode() {
    setState(() {
      _selectedIds.clear();
      _selectionMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ticketsAsync = ref.watch(userTicketsProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selectionMode) {
          _exitSelectionMode();
          return;
        }
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/profile');
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: _selectionMode
              ? IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _exitSelectionMode,
                )
              : IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/profile');
                    }
                  },
                ),
          title: _selectionMode
              ? Text(
                  '${_selectedIds.length} selected',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
                )
              : Text(
                  'My Requests',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
                ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: _selectionMode
              ? [
                  ticketsAsync.whenOrNull(
                    data: (tickets) => IconButton(
                      icon: Icon(
                        _selectedIds.length == tickets.length
                            ? Icons.deselect_rounded
                            : Icons.select_all_rounded,
                      ),
                      tooltip: 'Select all',
                      onPressed: () => _selectAll(tickets),
                    ),
                  ) ?? const SizedBox(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
                    tooltip: 'Delete selected',
                    onPressed: _deleteSelected,
                  ),
                ]
              : null,
        ),
        floatingActionButton: _selectionMode ? null : _buildFAB(context),
        body: ticketsAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          error: (e, _) => Center(
            child: Text('Error: $e', style: const TextStyle(color: AppColors.textMuted)),
          ),
          data: (tickets) {
            if (tickets.isEmpty) {
              return _buildEmptyState(context);
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: tickets.length,
              itemBuilder: (context, index) => _TicketCard(
                ticket: tickets[index],
                selectionMode: _selectionMode,
                isSelected: _selectedIds.contains(tickets[index].id),
                onTap: () {
                  if (_selectionMode) {
                    _toggleSelection(tickets[index].id);
                  } else {
                    context.push('/requests/chat/${tickets[index].id}');
                  }
                },
                onLongPress: () {
                  if (!_selectionMode) {
                    HapticFeedback.mediumImpact();
                    setState(() => _selectionMode = true);
                  }
                  _toggleSelection(tickets[index].id);
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFAB(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF059669), Color(0xFF047857)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF059669).withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: () => context.push('/requests/new'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text(
          'New Request',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF059669).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.support_agent_rounded,
                size: 48,
                color: Color(0xFF059669),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Requests Yet',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Submit a content request, report a bug,\nor suggest a new feature.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppColors.textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: () => context.push('/requests/new'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF059669), Color(0xFF047857)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Create Your First Request',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  final SupportTicket ticket;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _TicketCard({
    required this.ticket,
    required this.selectionMode,
    required this.isSelected,
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
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFEF4444).withValues(alpha: 0.08)
                  : AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFFEF4444).withValues(alpha: 0.5)
                    : ticket.unreadByUser
                        ? ticket.categoryColor.withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.04),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                // Selection checkbox or category icon
                if (selectionMode)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 24,
                    height: 24,
                    margin: const EdgeInsets.only(right: 14),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? const Color(0xFFEF4444)
                          : Colors.transparent,
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFEF4444)
                            : AppColors.textMuted,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                        : null,
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          ticket.categoryColor.withValues(alpha: 0.2),
                          ticket.categoryColor.withValues(alpha: 0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(ticket.categoryIcon, color: ticket.categoryColor, size: 20),
                  ),
                if (!selectionMode) const SizedBox(width: 14),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              ticket.subject,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: ticket.unreadByUser ? FontWeight.w700 : FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            ticket.timeAgo,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (ticket.lastMessagePreview != null)
                        Text(
                          ticket.lastMessagePreview!,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppColors.textMuted,
                            height: 1.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          // Status badge (only show for meaningful statuses)
                          if (ticket.showStatusBadge)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: ticket.statusColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                ticket.statusLabel,
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: ticket.statusColor,
                                ),
                              ),
                            ),
                          const SizedBox(width: 8),
                          // Category label
                          Text(
                            ticket.categoryLabel,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: AppColors.textHint,
                            ),
                          ),
                          const Spacer(),
                          // Unread dot
                          if (ticket.unreadByUser)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: ticket.categoryColor,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: ticket.categoryColor.withValues(alpha: 0.5),
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
