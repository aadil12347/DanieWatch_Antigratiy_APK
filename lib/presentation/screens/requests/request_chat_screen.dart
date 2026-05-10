import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  int _lastMessageCount = 0;
  bool _hasMarkedInitialRead = false;

  @override
  void initState() {
    super.initState();
    // Mark ticket + messages as read once after a small delay
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _markAsRead();
        _hasMarkedInitialRead = true;
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _markAsRead() async {
    final isAdmin = ref.read(isAdminProvider).valueOrNull ?? false;
    await ref.read(supportServiceProvider).markTicketRead(
      widget.ticketId,
      isAdmin: isAdmin,
    );
    // Mark messages from the other party as read (blue ticks)
    await ref.read(supportServiceProvider).markMessagesRead(
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

    // NOTE: markAsRead is handled in _buildMessageList when count changes
    // Do NOT call it here — it causes infinite rebuild loops.

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(isAdmin ? '/support-inbox' : '/requests');
        }
      },
      child: Scaffold(
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
                  // Only scroll + mark read when new messages actually arrive
                  if (messages.length != _lastMessageCount) {
                    _lastMessageCount = messages.length;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _scrollToBottom();
                      if (_hasMarkedInitialRead) _markAsRead();
                    });
                  }
                  return _buildMessageList(messages, isAdmin, ticket);
                },
              ),
            ),

            // Input area
            _buildInputArea(ticket, isAdmin),
          ],
        ),
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
            context.go(isAdmin ? '/support-inbox' : '/requests');
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
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
    // Get current user's avatar for user messages
    final currentUser = Supabase.instance.client.auth.currentUser;
    final currentUserAvatar = currentUser?.userMetadata?['avatar_url'] as String?;

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

        // Avatar URL: admin uses app logo, user uses their profile pic
        String? avatarUrl;
        if (!isMyMessage) {
          // Messages from the other party
          if (message.isAdmin) {
            avatarUrl = null; // Will show app logo icon
          } else {
            avatarUrl = ticket?.userAvatarUrl;
          }
        }

        return Column(
          children: [
            if (showDate) _buildDateSeparator(message.createdAt),
            _ChatBubble(
              message: message,
              isMyMessage: isMyMessage,
              isAdminMessage: message.isAdmin,
              avatarUrl: isMyMessage ? null : avatarUrl,
              showAvatar: !isMyMessage,
              currentUserAvatar: isMyMessage ? (isAdmin ? null : currentUserAvatar) : null,
              userAvatarUrl: ticket?.userAvatarUrl,
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
    // Lock chat for BOTH parties when ticket is closed
    final isDisabled = isClosed;

    return Container(
      padding: EdgeInsets.fromLTRB(
        12, 8, 8,
        MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: isDisabled
          ? _buildDisabledInput(ticket!, isAdmin)
          : _buildActiveInput(),
    );
  }

  Widget _buildDisabledInput(SupportTicket ticket, bool isAdmin) {
    final isCompleted = ticket.status == 'completed';
    if (!isAdmin) {
      // User sees a locked message — only admin can change status
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
    // Admin sees a locked message with hint to use status menu
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
            isCompleted ? 'Completed — change status to reply' : 'Rejected — change status to reply',
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Text field
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
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
                  horizontal: 16,
                  vertical: 10,
                ),
                isDense: true,
              ),
              onSubmitted: (_) => _sendMessage(),
              textInputAction: TextInputAction.send,
              maxLines: 4,
              minLines: 1,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Send button
        GestureDetector(
          onTap: _sendMessage,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF059669), Color(0xFF047857)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF059669).withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _isSending
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(
                    Icons.send_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
          ),
        ),
      ],
    );
  }
}

// ─── Chat Bubble Widget ──────────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  final SupportMessage message;
  final bool isMyMessage;
  final bool isAdminMessage;
  final String? avatarUrl;
  final bool showAvatar;
  final String? currentUserAvatar;
  final String? userAvatarUrl;

  const _ChatBubble({
    required this.message,
    required this.isMyMessage,
    required this.isAdminMessage,
    this.avatarUrl,
    this.showAvatar = false,
    this.currentUserAvatar,
    this.userAvatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final isStatusMessage = message.body.startsWith('\u{1F4CB}');

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
          // Avatar for received messages
          if (!isMyMessage) ...[
            _buildAvatar(),
            const SizedBox(width: 8),
          ],
          // Bubble
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
                  // Sender label for received admin messages
                  if (!isMyMessage && isAdminMessage)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        'DanieWatch Support',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF7C3AED),
                        ),
                      ),
                    ),
                  // Message body
                  Text(
                    message.body,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Time + read ticks row
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Spacer(),
                      Text(
                        message.timeFormatted,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: AppColors.textHint,
                        ),
                      ),
                      // WhatsApp-style ticks — only on own messages
                      if (isMyMessage) ...[
                        const SizedBox(width: 4),
                        _buildTicks(),
                      ],
                    ],
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

  /// Build avatar widget
  Widget _buildAvatar() {
    if (isAdminMessage) {
      // Admin avatar: app logo style
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7C3AED), Color(0xFF5B21B6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.headset_mic_rounded,
          size: 16,
          color: Colors.white,
        ),
      );
    } else {
      // User avatar: profile pic or fallback
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: AppColors.surface,
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        clipBehavior: Clip.antiAlias,
        child: avatarUrl != null && avatarUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: avatarUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => const Icon(
                  Icons.person_rounded,
                  size: 16,
                  color: AppColors.textHint,
                ),
                errorWidget: (_, __, ___) => const Icon(
                  Icons.person_rounded,
                  size: 16,
                  color: AppColors.textHint,
                ),
              )
            : const Icon(
                Icons.person_rounded,
                size: 16,
                color: AppColors.textHint,
              ),
      );
    }
  }

  /// WhatsApp-style tick indicators
  Widget _buildTicks() {
    final isRead = message.status == MessageStatus.read;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Double tick icon
        Icon(
          Icons.done_all_rounded,
          size: 14,
          color: isRead ? const Color(0xFF34B7F1) : AppColors.textHint,
        ),
      ],
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
