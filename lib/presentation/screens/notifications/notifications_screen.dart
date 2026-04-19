import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../../../core/services/notification_service.dart';
import '../../../domain/models/local_notification.dart';
import '../../providers/notification_inbox_provider.dart';
import '../details/details_screen.dart';

/// Notification inbox screen — accessible from the bell icon on home.
/// Shows rich notification cards with poster, title, year, and type.
/// Supports grouped "Recently Added" cards that expand to show all entries.
/// Tapping a rich notification opens the detail page directly.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  String? _highlightTmdbId;

  @override
  void initState() {
    super.initState();
    // Consume highlight data from notification tap
    _highlightTmdbId = NotificationService.instance.highlightTmdbId;
    NotificationService.instance.highlightTmdbId = null;

    // Auto-clear highlight after 3 seconds
    if (_highlightTmdbId != null) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _highlightTmdbId = null);
      });
    }

    // Mark ALL notifications as seen/read when user opens this page
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(notificationInboxProvider.notifier).markAllAsRead();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final notifications = ref.watch(notificationInboxProvider);
    final unreadCount = ref.watch(unreadCountProvider);

    // Group "recently_released" notifications by batch group_id
    final displayItems = _buildDisplayItems(notifications);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
        title: Text(
          'Notifications',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed: () {
                ref.read(notificationInboxProvider.notifier).markAllAsRead();
              },
              child: Text(
                'Mark all read',
                style: GoogleFonts.inter(
                  color: AppColors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (notifications.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, color: AppColors.textMuted),
              onPressed: () => _showClearDialog(context, ref),
            ),
        ],
      ),
      body: displayItems.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: displayItems.length,
              itemBuilder: (context, index) {
                final item = displayItems[index];
                if (item is _GroupedNotificationItem) {
                  return _GroupedNotificationCard(group: item);
                } else {
                  final notif = item as LocalNotification;
                  return _NotificationCard(
                    notification: notif,
                    isHighlighted: _highlightTmdbId != null &&
                        notif.tmdbId?.toString() == _highlightTmdbId,
                  );
                }
              },
            ),
    );
  }

  /// Build display items: group "recently_released" by batch group_id, keep others as singles
  List<dynamic> _buildDisplayItems(List<LocalNotification> notifications) {
    final result = <dynamic>[];
    final recentlyReleasedByGroup = <String, List<LocalNotification>>{};
    
    for (final n in notifications) {
      if (n.type == 'recently_released' && n.isRichNotification) {
        final groupKey = n.groupId ?? 'legacy_${n.createdAt.year}-${n.createdAt.month}-${n.createdAt.day}';
        recentlyReleasedByGroup.putIfAbsent(groupKey, () => []).add(n);
      } else {
        result.add(n);
      }
    }

    for (final entry in recentlyReleasedByGroup.entries) {
      final items = entry.value;
      result.add(_GroupedNotificationItem(
        notifications: items,
        dateKey: entry.key,
      ));
    }

    // Sort by date (newest first)
    result.sort((a, b) {
      final aDate = a is _GroupedNotificationItem
          ? a.notifications.first.createdAt
          : (a as LocalNotification).createdAt;
      final bDate = b is _GroupedNotificationItem
          ? b.notifications.first.createdAt
          : (b as LocalNotification).createdAt;
      return bDate.compareTo(aDate);
    });

    return result;
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: AppColors.surfaceElevated,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_off_outlined,
              color: AppColors.textMuted,
              size: 48,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No notifications yet',
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.textSecondary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'New updates will appear here',
            style: GoogleFonts.inter(
              color: AppColors.textMuted,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  void _showClearDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Clear all notifications?',
          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This will remove all notifications from your inbox.',
          style: GoogleFonts.inter(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () {
              ref.read(notificationInboxProvider.notifier).clearAll();
              Navigator.pop(ctx);
            },
            child: Text('Clear', style: GoogleFonts.inter(color: AppColors.error, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// Data holder for grouped notification display
class _GroupedNotificationItem {
  final List<LocalNotification> notifications;
  final String dateKey;

  _GroupedNotificationItem({required this.notifications, required this.dateKey});

  bool get hasUnread => notifications.any((n) => !n.isRead);
}

/// Expandable grouped notification card for "Recently Added" batch notifications
class _GroupedNotificationCard extends ConsumerStatefulWidget {
  final _GroupedNotificationItem group;
  const _GroupedNotificationCard({required this.group});

  @override
  ConsumerState<_GroupedNotificationCard> createState() => _GroupedNotificationCardState();
}

class _GroupedNotificationCardState extends ConsumerState<_GroupedNotificationCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final count = group.notifications.length;
    final hasUnread = group.hasUnread;
    const accentColor = AppColors.secondary;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasUnread
              ? accentColor.withValues(alpha: 0.3)
              : AppColors.border,
        ),
      ),
      child: Column(
        children: [
          // Header — tappable to expand/collapse
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() => _expanded = !_expanded);
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  if (hasUnread)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: const BoxDecoration(
                        color: accentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.movie_filter_rounded, color: accentColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Show movie titles on top
                        Text(
                          group.notifications.map((n) {
                            var t = n.title.replaceAll(RegExp(r'^🎬\s*'), '');
                            t = t.replaceAll(RegExp(r'^Recently Added\s*', caseSensitive: false), '');
                            return t;
                          }).where((t) => t.isNotEmpty).take(3).join(', ') +
                            (count > 3 ? ' +${count - 3} more' : ''),
                          style: GoogleFonts.inter(
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
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$count Recently Added',
                                style: GoogleFonts.inter(
                                  color: accentColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _timeAgo(group.notifications.first.createdAt),
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
                  Icon(
                    _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: AppColors.textMuted,
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
          // Expanded list of individual entries
          if (_expanded) ...[
            const Divider(color: Colors.white10, height: 1),
            ...group.notifications.map((n) => _GroupedEntryTile(notification: n)),
          ],
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

/// Single entry tile inside a grouped card — shows poster + title + year + type
class _GroupedEntryTile extends StatelessWidget {
  final LocalNotification notification;
  const _GroupedEntryTile({required this.notification});

  @override
  Widget build(BuildContext context) {
    var title = notification.title.replaceAll(RegExp(r'^🎬\s*'), '');
    title = title.replaceAll(RegExp(r'^Recently Added\s*', caseSensitive: false), '');
    title = title.replaceAll(RegExp(r'\s*\(\d{4}\)\s*$'), '');
    if (title.isEmpty) title = notification.body;
    final mediaType = notification.mediaType;
    final year = notification.releaseYear;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (notification.tmdbId != null && notification.mediaType != null) {
            Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(
                builder: (_) => DetailsScreen(
                  tmdbId: notification.tmdbId!,
                  mediaType: notification.mediaType!,
                ),
              ),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              if (notification.posterUrl != null || notification.backdropUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CachedNetworkImage(
                    imageUrl: notification.posterUrl ?? notification.backdropUrl!,
                    width: 40,
                    height: 60,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(width: 40, height: 60, color: AppColors.surface),
                    errorWidget: (_, __, ___) => Container(
                      width: 40, height: 60, color: AppColors.surface,
                      child: const Icon(Icons.movie, color: AppColors.textMuted, size: 16),
                    ),
                  ),
                )
              else
                Container(
                  width: 40, height: 60,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.movie, color: AppColors.textMuted, size: 16),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    // Year first, then type
                    Row(
                      children: [
                        if (year != null)
                          _typeBadge('$year'),
                        if (year != null && mediaType != null)
                          const SizedBox(width: 6),
                        if (mediaType != null)
                          _typeBadge(mediaType == 'tv' ? 'TV' : 'Movie'),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted.withValues(alpha: 0.5),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: AppColors.secondary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Individual (non-grouped) notification card
class _NotificationCard extends ConsumerWidget {
  final LocalNotification notification;
  final bool isHighlighted;
  const _NotificationCard({required this.notification, this.isHighlighted = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRich = notification.isRichNotification;

    return GestureDetector(
      onTap: () {
        // Mark as read
        ref.read(notificationInboxProvider.notifier).markAsRead(notification.id);

        // Navigate to detail page if rich notification
        if (isRich && notification.tmdbId != null && notification.mediaType != null) {
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(
              builder: (_) => DetailsScreen(
                tmdbId: notification.tmdbId!,
                mediaType: notification.mediaType!,
              ),
            ),
          );
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: notification.isRead
              ? AppColors.surfaceElevated
              : AppColors.surfaceElevated.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isHighlighted
                ? AppColors.primary
                : notification.isRead
                    ? AppColors.border
                    : AppColors.primary.withValues(alpha: 0.3),
            width: isHighlighted ? 2 : 1,
          ),
          boxShadow: isHighlighted
              ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 12, spreadRadius: 2)]
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Unread indicator dot
            if (!notification.isRead)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6, right: 8),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),

            // Poster or icon
            if (isRich && (notification.posterUrl != null || notification.backdropUrl != null))
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: notification.posterUrl ?? notification.backdropUrl!,
                  width: 50,
                  height: 75,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    width: 50,
                    height: 75,
                    color: AppColors.surface,
                    child: const Icon(Icons.movie, color: AppColors.textMuted, size: 20),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    width: 50,
                    height: 75,
                    color: AppColors.surface,
                    child: const Icon(Icons.broken_image, color: AppColors.textMuted, size: 20),
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _getTypeColor().withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_getTypeIcon(), color: _getTypeColor(), size: 22),
              ),

            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    notification.title,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),

                  // Body
                  Text(
                    notification.body,
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),

                  // Category badge + type + time
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _getTypeColor().withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          notification.categoryLabel,
                          style: GoogleFonts.inter(
                            color: _getTypeColor(),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (isRich && notification.mediaType != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            notification.mediaType == 'tv' ? 'TV' : 'Movie',
                            style: GoogleFonts.inter(
                              color: AppColors.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        _timeAgo(notification.createdAt),
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

            // Arrow for rich notifications
            if (isRich)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 20),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted.withValues(alpha: 0.5),
                  size: 20,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _getTypeColor() {
    switch (notification.type) {
      case 'newly_added':
        return AppColors.primary;
      case 'recently_released':
        return AppColors.secondary;
      default:
        return AppColors.primary;
    }
  }

  IconData _getTypeIcon() {
    switch (notification.type) {
      case 'newly_added':
        return Icons.new_releases_rounded;
      case 'recently_released':
        return Icons.movie_filter_rounded;
      default:
        return Icons.message_rounded;
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
