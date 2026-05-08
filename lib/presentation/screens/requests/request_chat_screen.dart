import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/support_message.dart';
import '../../../domain/models/support_ticket.dart';
import '../../providers/support_provider.dart';
import '../../providers/admin_provider.dart';

class RequestChatScreen extends ConsumerStatefulWidget {
  final String ticketId;
  const RequestChatScreen({super.key, required this.ticketId});

  @override
  ConsumerState<RequestChatScreen> createState() => _RequestChatScreenState();
}

class _RequestChatScreenState extends ConsumerState<RequestChatScreen>
    with TickerProviderStateMixin {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSending = false;
  late AnimationController _inputAnimController;

  @override
  void initState() {
    super.initState();
    _inputAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    // Mark ticket as read after a small delay
    Future.delayed(const Duration(milliseconds: 500), _markAsRead);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _inputAnimController.dispose();
    super.dispose();
  }

  Future<void> _markAsRead() async {
    final isAdmin = ref.read(isAdminProvider).valueOrNull ?? false;
    await ref.read(supportServiceProvider).markTicketRead(
      widget.ticketId,
      isAdmin: isAdmin,
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _messageController.clear();

    final isAdmin = ref.read(isAdminProvider).valueOrNull ?? false;
    await ref.read(supportServiceProvider).sendMessage(
      ticketId: widget.ticketId,
      body: text,
      isAdmin: isAdmin,
    );

    setState(() => _isSending = false);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 200), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 100,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(ticketMessagesProvider(widget.ticketId));
    final isAdmin = ref.watch(isAdminProvider).valueOrNull ?? false;

    // Get ticket info from the appropriate provider
    final SupportTicket? ticket;
    if (isAdmin) {
      ticket = ref.watch(allTicketsProvider).whenOrNull(
        data: (tickets) {
          try {
            return tickets.firstWhere((t) => t.id == widget.ticketId);
          } catch (_) {
            return null;
          }
        },
      );
    } else {
      ticket = ref.watch(userTicketsProvider).whenOrNull(
        data: (tickets) {
          try {
            return tickets.firstWhere((t) => t.id == widget.ticketId);
          } catch (_) {
            return null;
          }
        },
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(ticket, isAdmin),
      body: Column(
        children: [
          // Status banner
          if (ticket != null && ticket.isClosed) _buildStatusBanner(ticket),

          // Messages
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (e, _) => Center(
                child: Text('Error: $e', style: const TextStyle(color: AppColors.textMuted)),
              ),
              data: (messages) {
                // Auto-scroll on new messages
                WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
                return _buildMessageList(messages, isAdmin, ticket);
              },
            ),
          ),

          // Input area
          _buildInputArea(ticket, isAdmin),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(SupportTicket? ticket, bool isAdmin) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(isAdmin ? '/admin-console/support-inbox' : '/requests');
          }
        },
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ticket?.subject ?? 'Chat',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (ticket != null) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(ticket.categoryIcon, size: 12, color: ticket.categoryColor),
                const SizedBox(width: 4),
                Text(
                  ticket.categoryLabel,
                  style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: ticket.statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
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
                if (isAdmin && ticket.username != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '@${ticket.username}',
                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
      actions: isAdmin && ticket != null
          ? [_buildAdminStatusMenu(ticket)]
          : null,
      backgroundColor: Colors.transparent,
      elevation: 0,
    );
  }

  Widget _buildAdminStatusMenu(SupportTicket ticket) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
      color: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (status) async {
        await ref.read(supportServiceProvider).updateTicketStatus(
          widget.ticketId,
          status,
        );
      },
      itemBuilder: (context) => [
        _statusMenuItem('new', 'New', const Color(0xFF3B82F6), ticket.status),
        _statusMenuItem('pending', 'Pending', const Color(0xFFF59E0B), ticket.status),
        _statusMenuItem('completed', 'Completed', const Color(0xFF10B981), ticket.status),
        _statusMenuItem('rejected', 'Rejected', const Color(0xFFEF4444), ticket.status),
      ],
    );
  }

  PopupMenuItem<String> _statusMenuItem(
    String value,
    String label,
    Color color,
    String currentStatus,
  ) {
    final isActive = value == currentStatus;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              color: isActive ? color : AppColors.textPrimary,
            ),
          ),
          if (isActive) ...[
            const Spacer(),
            Icon(Icons.check_rounded, size: 16, color: color),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBanner(SupportTicket ticket) {
    final isCompleted = ticket.status == 'completed';
    final color = isCompleted ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final icon = isCompleted ? Icons.check_circle_rounded : Icons.cancel_rounded;
    final text = isCompleted
        ? 'This request has been marked as Completed'
        : 'This request has been rejected';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border(bottom: BorderSide(color: color.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(
    List<SupportMessage> messages,
    bool isAdmin,
    SupportTicket? ticket,
  ) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: messages.length + (ticket != null ? 1 : 0),
      itemBuilder: (context, index) {
        // First item: ticket info card
        if (ticket != null && index == 0) {
          return _buildTicketInfoCard(ticket);
        }
        final msgIndex = ticket != null ? index - 1 : index;
        final message = messages[msgIndex];

        // Check if we need a date separator
        final showDate = msgIndex == 0 ||
            _isDifferentDay(messages[msgIndex - 1].createdAt, message.createdAt);

        // Is this message from the current user's perspective?
        final isMyMessage = isAdmin ? message.isAdmin : !message.isAdmin;

        return Column(
          children: [
            if (showDate) _buildDateSeparator(message.createdAt),
            _ChatBubble(
              message: message,
              isMyMessage: isMyMessage,
              isAdmin: message.isAdmin,
            ),
          ],
        );
      },
    );
  }

  bool _isDifferentDay(DateTime a, DateTime b) {
    return a.year != b.year || a.month != b.month || a.day != b.day;
  }

  Widget _buildDateSeparator(DateTime date) {
    final now = DateTime.now();
    String label;
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      label = 'Today';
    } else if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day - 1) {
      label = 'Yesterday';
    } else {
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      label = '${months[date.month - 1]} ${date.day}, ${date.year}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: AppColors.border.withValues(alpha: 0.3))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.textHint,
              ),
            ),
          ),
          Expanded(child: Divider(color: AppColors.border.withValues(alpha: 0.3))),
        ],
      ),
    );
  }

  Widget _buildTicketInfoCard(SupportTicket ticket) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ticket.categoryColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ticket.categoryColor.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ticket.categoryIcon, size: 16, color: ticket.categoryColor),
              const SizedBox(width: 6),
              Text(
                ticket.categoryLabel,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: ticket.categoryColor,
                ),
              ),
              const Spacer(),
              Text(
                _formatDate(ticket.createdAt),
                style: GoogleFonts.inter(fontSize: 10, color: AppColors.textHint),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            ticket.subject,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (ticket.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              ticket.description,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Widget _buildInputArea(SupportTicket? ticket, bool isAdmin) {
    final isClosed = ticket?.isClosed ?? false;

    // Admin can always reopen/reply even when closed
    final isDisabled = isClosed && !isAdmin;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16, 12, 16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: isDisabled
              ? _buildDisabledInput(ticket!)
              : _buildActiveInput(),
        ),
      ),
    );
  }

  Widget _buildDisabledInput(SupportTicket ticket) {
    final isCompleted = ticket.status == 'completed';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isCompleted ? Icons.check_circle_outline_rounded : Icons.block_rounded,
            size: 16,
            color: AppColors.textHint,
          ),
          const SizedBox(width: 8),
          Text(
            isCompleted ? 'This request has been completed' : 'This request has been rejected',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveInput() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Type a message...',
                hintStyle: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppColors.textHint,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              onSubmitted: (_) => _sendMessage(),
              textInputAction: TextInputAction.send,
              maxLines: 4,
              minLines: 1,
            ),
          ),
          // Send button
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: _sendMessage,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF059669), Color(0xFF047857)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF059669).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: _isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Chat Bubble Widget ──────────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  final SupportMessage message;
  final bool isMyMessage;
  final bool isAdmin;

  const _ChatBubble({
    required this.message,
    required this.isMyMessage,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context) {
    final isStatusMessage = message.body.startsWith('📋');

    if (isStatusMessage) {
      return _buildStatusMessage(context);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment:
            isMyMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMyMessage) ...[
            // Admin avatar
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFF5B21B6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.shield_rounded,
                size: 14,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMyMessage
                    ? const Color(0xFF059669).withValues(alpha: 0.2)
                    : AppColors.surfaceElevated,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMyMessage ? 18 : 4),
                  bottomRight: Radius.circular(isMyMessage ? 4 : 18),
                ),
                border: Border.all(
                  color: isMyMessage
                      ? const Color(0xFF059669).withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: 0.06),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMyMessage && isAdmin)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        'Admin',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF7C3AED),
                        ),
                      ),
                    ),
                  Text(
                    message.body,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      message.timeFormatted,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMyMessage) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildStatusMessage(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
          ),
          child: Text(
            message.body,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
