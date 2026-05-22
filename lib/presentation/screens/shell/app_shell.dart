
import '../../../core/utils/responsive.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:flutter/physics.dart';
import 'package:go_router/go_router.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/search_provider.dart';
import '../../providers/download_modal_provider.dart';
import '../../providers/filter_modal_provider.dart';
import '../../providers/actor_modal_provider.dart';
import '../../widgets/quality_selector_sheet.dart';
import '../../../core/utils/toast_utils.dart';
import '../../widgets/main_filter_panel_sheet.dart';
import '../../widgets/actor_modal_content.dart';
import '../../../data/local/download_manager.dart';
import '../../widgets/filter_selector_sheet.dart';
import 'dart:async';
import '../../providers/confirmation_modal_provider.dart';
import '../../widgets/confirmation_modal_content.dart';
import '../../providers/scroll_provider.dart';
import '../../widgets/liquid_glass.dart';
import '../../widgets/liquid_nav_bar.dart';
import '../../providers/support_modal_provider.dart';
import '../../providers/admin_provider.dart';
import '../../providers/support_provider.dart';
import '../../../domain/models/support_ticket.dart';
import '../../widgets/support_fab.dart';
import '../../providers/app_update_provider.dart';
import '../../widgets/force_update_modal.dart';

/// App shell with custom glassmorphism bottom navigation bar
class AppShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  DateTime? _lastBackPressed;
  late AnimationController _supportModalController;

  // Swipe navigation tracking
  double _swipeDx = 0;
  double _swipeDy = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _supportModalController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _downloadSub =
        DownloadManager.instance.updateStream.listen(_handleDownloadUpdate);

    // Initialize the app update check
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(appUpdateStateProvider.notifier).initialize();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // If we return from the Android installer, check if install was cancelled
      ref.read(appUpdateStateProvider.notifier).onAppResumed();
    }
  }


  static void closeModals(WidgetRef ref) {
    ref.read(downloadModalProvider.notifier).state = const DownloadModalState();
    ref.read(filterModalProvider.notifier).state =
        const FilterModalState(view: FilterView.none);
    ref.read(confirmationModalProvider.notifier).state =
        const ConfirmationModalState();
    ref.read(actorModalProvider.notifier).state = const ActorModalState();
    ref.read(supportModalProvider.notifier).state = false;
  }

  void _onTap(int index) {
    final isCurrent = index == widget.navigationShell.currentIndex;
    if (isCurrent) {
      // Check if we are at the root of the branch
      final location = GoRouterState.of(context).uri.toString();
      final rootLocations = ['/home', '/search', '/watchlist', '/downloads'];
      
      // If the current location is not one of the roots, it means we are in a detail page
      // or a sub-page. In this case, we navigate to the initial location (pop to root).
      if (!rootLocations.contains(location)) {
        widget.navigationShell.goBranch(
          index,
          initialLocation: true,
        );
      } else {
        // We are already at the root, so we trigger scroll to top
        ref.read(scrollProvider).scrollToTop(index);
      }
    } else {
      // Different tab, just switch
      widget.navigationShell.goBranch(index);
    }
  }

  StreamSubscription? _downloadSub;

  void _handleDownloadUpdate(DownloadItem item) {
    if (!mounted) return;

    // We only show toasts for major status transitions, not progress updates
    switch (item.status) {
      case DownloadStatus.completed:
        CustomToast.show(
          context,
          '${item.displayName} completed',
          type: ToastType.success,
          icon: Icons.download_done_rounded,
        );
        break;
      case DownloadStatus.failed:
        CustomToast.show(
          context,
          'Download failed: ${item.displayName}',
          type: ToastType.error,
          icon: Icons.error_outline_rounded,
        );
        break;
      case DownloadStatus.paused:
        // Only show if user manually paused? Usually status changes are user-driven
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _downloadSub?.cancel();
    _supportModalController.dispose();
    super.dispose();
  }

  // Navigation state is now managed by StatefulNavigationShell
  bool _isTabSelected(int index) {
    return widget.navigationShell.currentIndex == index;
  }

  void _closeAllModals() {
    ref.read(downloadModalProvider.notifier).state = const DownloadModalState();
    ref.read(filterModalProvider.notifier).state =
        const FilterModalState(view: FilterView.none);
    ref.read(confirmationModalProvider.notifier).state =
        const ConfirmationModalState();
    ref.read(actorModalProvider.notifier).state = const ActorModalState();
    _closeSupportModal();
  }

  void _closeSupportModal() {
    if (ref.read(supportModalProvider)) {
      _supportModalController.reverse().then((_) {
        if (mounted) ref.read(supportModalProvider.notifier).state = false;
      });
    }
  }

  void _openSupportModal() {
    ref.read(supportModalProvider.notifier).state = true;
    _supportModalController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final isSearchExpanded = ref.watch(searchExpandedProvider);
    final hideNavBar = location.startsWith('/notifications');

    final downloadState = ref.watch(downloadModalProvider);
    final filterState = ref.watch(filterModalProvider);
    final confirmState = ref.watch(confirmationModalProvider);
    final actorState = ref.watch(actorModalProvider);
    final isSupportOpen = ref.watch(supportModalProvider);
    final isOtherModalOpen =
        downloadState.isOpen || filterState.isOpen || confirmState.isOpen || actorState.isOpen;
    final isModalOpen = isOtherModalOpen || isSupportOpen;
    final isAdmin = ref.watch(isAdminProvider).valueOrNull ?? false;

    // Listen for support modal provider to trigger animation
    ref.listen<bool>(supportModalProvider, (prev, next) {
      if (next && !(prev ?? false)) {
        _supportModalController.forward(from: 0);
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;


        // 2. If support modal is open, close it
        if (isSupportOpen) {
          _closeSupportModal();
          return;
        }

        // 3. If global modals are open, close them
        if (isOtherModalOpen) {
          // Special case for filter step-back
          if (filterState.view == FilterView.optionsList &&
              filterState.isSubMenu) {
            ref.read(filterModalProvider.notifier).state =
                const FilterModalState(view: FilterView.mainPanel);
          } else {
            _closeAllModals();
          }
          return;
        }

        // 3. If any search field is focused, unfocus it first (Universal check)
        final isSearchFocused = ref.read(searchFocusProvider);
        if (isSearchFocused) {
          FocusManager.instance.primaryFocus?.unfocus();
          return;
        }

        // 4. Navigation-level back logic (Go to Home if not there)
        if (widget.navigationShell.currentIndex != 0) {
          _onTap(0);
          return;
        }

        // 4b. If on Home branch but at a sub-page (e.g. /notifications),
        //     navigate back to /home instead of showing exit prompt.
        final currentLocation = GoRouterState.of(context).uri.toString();
        if (currentLocation != '/home') {
          context.go('/home');
          return;
        }

        // 5. Double back to exit (only on Home tab at /home root)
        final now = DateTime.now();
        if (_lastBackPressed == null ||
            now.difference(_lastBackPressed!) > const Duration(seconds: 3)) {
          _lastBackPressed = now;
          CustomToast.show(
            context,
            'Press back again to close the app',
            type: ToastType.warning,
            icon: Icons.exit_to_app_rounded,
          );
        } else {
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
        extendBody: true,
        body: Stack(
          children: [
            // Static black background — gradient is now local to carousel in HomeScreen
            Container(color: Colors.black),
            // Main content ON TOP of gradient
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (_) {
                _swipeDx = 0;
                _swipeDy = 0;
              },
              onHorizontalDragUpdate: (details) {
                _swipeDx += details.delta.dx;
                _swipeDy += details.delta.dy;
              },
              onHorizontalDragEnd: (_) {
                final absDx = _swipeDx.abs();
                final absDy = _swipeDy.abs();
                // Intentional swipe: >80px horizontal, ratio > 2x vertical
                if (absDx > 80 && (absDy < 1 || absDx / absDy > 2.0)) {
                  final current = widget.navigationShell.currentIndex;
                  if (_swipeDx < 0 && current < 3) {
                    // Swipe left → next tab
                    HapticFeedback.lightImpact();
                    _onTap(current + 1);
                  } else if (_swipeDx > 0 && current > 0) {
                    // Swipe right → previous tab
                    HapticFeedback.lightImpact();
                    _onTap(current - 1);
                  }
                }
                _swipeDx = 0;
                _swipeDy = 0;
              },
              child: widget.navigationShell,
            ),
            // Barrier to dismiss modal when tapping outside
            if (isModalOpen)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (isSupportOpen) {
                      _closeSupportModal();
                    } else {
                      _closeAllModals();
                    }
                  },
                  child: Container(color: Colors.black.withValues(alpha: 0.4)),
                ),
              ),
            // Floating support FAB
            if (!isSupportOpen && !isOtherModalOpen)
              const SupportFAB(),
            // Floating Bottom Nav Bar or Download/Filter Modal
            if (!isSearchExpanded && !hideNavBar)
              Builder(builder: (context) {
                final r = Responsive(context);
                final navBottom = MediaQuery.paddingOf(context).bottom + r.h(24);
                final anyModalOpen = isOtherModalOpen || isSupportOpen;
                final navMaxWidth = anyModalOpen ? r.wClamped(600, minVal: 320) : r.wClamped(400, minVal: 280);
                final navHPad = anyModalOpen ? r.w(16) : r.w(24);
                final navRadius = anyModalOpen ? r.w(24) : r.w(32);
                final iconSize = r.d(24).clamp(18.0, 30.0);
                final labelSize = r.f(11).clamp(9.0, 14.0);
                final tabWidth = r.w(64).clamp(48.0, 80.0);
                final navHeight = r.h(64).clamp(52.0, 76.0);

                return Positioned(
                  bottom: navBottom,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutExpo,
                      constraints: BoxConstraints(maxWidth: navMaxWidth),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: navHPad),
                        child: LiquidGlass(
                          borderRadius: navRadius,
                          intensity: anyModalOpen ? GlassIntensity.heavy : GlassIntensity.medium,
                          enableAnimatedBorder: true,
                          enableTouchRipple: false,
                          edgeGlow: anyModalOpen ? 0.10 : 0.18,
                          child: AnimatedSize(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutExpo,
                            alignment: Alignment.bottomCenter,
                            clipBehavior: Clip.hardEdge,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              // Outgoing: fade out FAST in first 40% so buttons
                              // vanish before container size changes squish them
                              switchOutCurve: const Interval(0.6, 1.0),
                              // Incoming: fade in from 30% mark onward
                              switchInCurve: const Interval(0.3, 1.0, curve: Curves.easeOut),
                              // CRITICAL: Use bottomCenter alignment so old navbar
                              // stays pinned to bottom instead of drifting to center
                              layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
                                return Stack(
                                  alignment: Alignment.bottomCenter,
                                  clipBehavior: Clip.hardEdge,
                                  children: <Widget>[
                                    ...previousChildren,
                                    if (currentChild != null) currentChild,
                                  ],
                                );
                              },
                              transitionBuilder: (child, animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: child,
                                );
                              },
                              child: isSupportOpen
                                ? _SupportModalContent(
                                    isAdmin: isAdmin,
                                    animation: _supportModalController,
                                    onClose: _closeSupportModal,
                                  )
                                : isOtherModalOpen
                                ? Material(
                                    color: Colors.transparent,
                                    child: downloadState.isOpen
                                            ? QualitySelectorContent(
                                                m3u8Url:
                                                    downloadState.m3u8Url ??
                                                        '',
                                                title: downloadState.title ??
                                                    'Download',
                                                onSelected: downloadState
                                                        .onSelected ??
                                                    (_) {},
                                                onCancel: () {
                                                  downloadState.onCancel?.call();
                                                  _closeAllModals();
                                                },
                                              )
                                            : confirmState.isOpen
                                                ? ConfirmationModalContent(
                                                    title: confirmState.title,
                                                    message:
                                                        confirmState.message,
                                                    confirmLabel: confirmState
                                                        .confirmLabel,
                                                    showDeviceDeleteToggle:
                                                        confirmState
                                                            .showDeviceDeleteToggle,
                                                    onConfirm: (also) {
                                                      confirmState.onConfirm
                                                          ?.call(also);
                                                      ref
                                                          .read(
                                                              confirmationModalProvider
                                                                  .notifier)
                                                          .state = const ConfirmationModalState();
                                                    },
                                                    onCancel: () {
                                                      confirmState.onCancel?.call();
                                                      _closeAllModals();
                                                    },
                                                  )
                                                : actorState.isOpen
                                                    ? const ActorModalContent(
                                                        key: ValueKey('actor_modal'),
                                                      )
                                                    : (filterState.view == FilterView.optionsList
                                                        ? FilterSelectorContent(
                                                            title: filterState.title,
                                                            currentValue: filterState.currentValue,
                                                            options: filterState.options,
                                                            onChanged: filterState.onChanged ?? (_) {},
                                                            onCancel: _closeAllModals,
                                                          )
                                                        : const MainFilterPanelContent(
                                                            key: ValueKey('filter_main'),
                                                          )),
                                  )
                                : LiquidNavBarContent(
                                    key: const ValueKey('liquid_navbar'),
                                    currentIndex: widget.navigationShell.currentIndex,
                                    navHeight: navHeight,
                                    tabWidth: tabWidth,
                                    iconSize: iconSize,
                                    labelSize: labelSize,
                                    horizontalPad: r.w(12),
                                    onTap: _onTap,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),

            // ── Force Update Modal (topmost layer — blocks all interaction) ──
            Consumer(
              builder: (context, ref, _) {
                final updateState = ref.watch(appUpdateStateProvider);
                // Only show modal when an update is needed
                if (updateState is AppUpdateUpToDate ||
                    updateState is AppUpdateChecking) {
                  return const SizedBox.shrink();
                }
                return const ForceUpdateModal();
              },
            ),
          ],
        ),
      ),
    );
  }
}




/// Support modal content — mirrors the full request list page.
/// Same size as the filter modal, showing all tickets with proper cards.
class _SupportModalContent extends ConsumerWidget {
  final bool isAdmin;
  final AnimationController animation;
  final VoidCallback onClose;

  const _SupportModalContent({
    required this.isAdmin,
    required this.animation,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxModalHeight = screenHeight * 0.75;

    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
      ),
      child: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxModalHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header bar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF059669).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.support_agent_rounded,
                        color: Color(0xFF059669),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isAdmin ? 'Support Inbox' : 'My Requests',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppColors.textMuted, size: 22),
                      onPressed: onClose,
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white10, height: 1),
              // Ticket list content
              Flexible(
                child: isAdmin
                    ? _FullAdminTicketList(onClose: onClose)
                    : _FullUserTicketList(onClose: onClose),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full user ticket list — mirrors RequestListScreen content
class _FullUserTicketList extends ConsumerWidget {
  final VoidCallback onClose;
  const _FullUserTicketList({required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(userTicketsProvider);

    return ticketsAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(color: Color(0xFF059669), strokeWidth: 2),
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Error: $e', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)),
      ),
      data: (tickets) {
        if (tickets.isEmpty) {
          return _buildEmptyState(context, ref);
        }
        return Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                itemCount: tickets.length,
                itemBuilder: (context, index) {
                  final ticket = tickets[index];
                  return _ModalTicketCard(
                    ticket: ticket,
                    isAdmin: false,
                    onTap: () {
                      context.push('/requests/chat/${ticket.id}');
                    },
                  );
                },
              ),
            ),
            // New Request button at bottom
            _ModalNewRequestButton(onClose: onClose),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF059669).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.support_agent_rounded, size: 40, color: Color(0xFF059669)),
          ),
          const SizedBox(height: 20),
          Text(
            'No Requests Yet',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Submit a content request, report a bug,\nor suggest a new feature.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted, height: 1.5),
          ),
          const SizedBox(height: 24),
          _ModalNewRequestButton(onClose: onClose),
        ],
      ),
    );
  }
}

/// Full admin ticket list — mirrors AdminSupportInboxScreen content
class _FullAdminTicketList extends ConsumerWidget {
  final VoidCallback onClose;
  const _FullAdminTicketList({required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(allTicketsProvider);

    return ticketsAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(color: Color(0xFF059669), strokeWidth: 2),
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Error: $e', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)),
      ),
      data: (tickets) {
        if (tickets.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inbox_rounded, color: AppColors.textMuted.withValues(alpha: 0.4), size: 40),
                const SizedBox(height: 12),
                Text('No requests', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14)),
              ],
            ),
          );
        }
        return Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                itemCount: tickets.length,
                itemBuilder: (context, index) {
                  final ticket = tickets[index];
                  return _ModalTicketCard(
                    ticket: ticket,
                    isAdmin: true,
                    onTap: () {
                      context.push('/requests/chat/${ticket.id}');
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Full-featured ticket card for the support modal — matches request_list_screen design
class _ModalTicketCard extends StatelessWidget {
  final SupportTicket ticket;
  final bool isAdmin;
  final VoidCallback onTap;

  const _ModalTicketCard({
    required this.ticket,
    required this.isAdmin,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isUnread = isAdmin ? ticket.unreadByAdmin : ticket.unreadByUser;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isUnread
                ? ticket.categoryColor.withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.04),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Category icon
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    ticket.categoryColor.withValues(alpha: 0.2),
                    ticket.categoryColor.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(ticket.categoryIcon, color: ticket.categoryColor, size: 18),
            ),
            const SizedBox(width: 12),
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
                            fontSize: 13,
                            fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        ticket.timeAgo,
                        style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                  if (ticket.lastMessagePreview != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      ticket.lastMessagePreview!,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                        height: 1.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (isAdmin && ticket.username != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      ticket.username!,
                      style: GoogleFonts.inter(fontSize: 11, color: AppColors.textHint),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      // Status badge (only show for meaningful statuses)
                      if (ticket.showStatusBadge)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: ticket.statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            ticket.statusLabel,
                            style: GoogleFonts.inter(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: ticket.statusColor,
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      Text(
                        ticket.categoryLabel,
                        style: GoogleFonts.inter(fontSize: 10, color: AppColors.textHint),
                      ),
                      const Spacer(),
                      // Unread dot
                      if (isUnread)
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: ticket.categoryColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: ticket.categoryColor.withValues(alpha: 0.5),
                                blurRadius: 5,
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
    );
  }
}

/// New request button for the modal bottom
class _ModalNewRequestButton extends ConsumerWidget {
  final VoidCallback onClose;
  const _ModalNewRequestButton({required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      child: GestureDetector(
        onTap: () {
          context.push('/requests/new');
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF059669), Color(0xFF047857)],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF059669).withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                'New Request',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// A nested PopScope that intercepts system back button to close global modals
/// when we are deeper in the navigation stack (e.g. Details page).
/// Without this, the inner Navigator would pop the page instead of closing the modal.
class ShellPopScope extends ConsumerWidget {
  final Widget child;
  const ShellPopScope({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadState = ref.watch(downloadModalProvider);
    final filterState = ref.watch(filterModalProvider);
    final confirmState = ref.watch(confirmationModalProvider);
    final actorState = ref.watch(actorModalProvider);
    final isSupportOpen = ref.watch(supportModalProvider);

    // When the support modal is open but user is on a support sub-route
    // (e.g. /requests/chat/... or /requests/new), allow normal back navigation
    // instead of closing the modal. The modal should persist while navigating
    // within the support flow.
    final location = GoRouterState.of(context).uri.toString();
    final isOnSupportSubRoute = location.startsWith('/requests/chat/') ||
        location.startsWith('/requests/new');
    final shouldInterceptSupport = isSupportOpen && !isOnSupportSubRoute;

    final isOtherModalOpen =
        downloadState.isOpen || filterState.isOpen || confirmState.isOpen || actorState.isOpen;
    final isModalOpen = isOtherModalOpen || shouldInterceptSupport;

    return PopScope(
      canPop: !isModalOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && isModalOpen) {
          if (shouldInterceptSupport) {
            ref.read(supportModalProvider.notifier).state = false;
          } else if (downloadState.isOpen) {
            ref.read(downloadModalProvider.notifier).state =
                const DownloadModalState();
          } else if (confirmState.isOpen) {
            ref.read(confirmationModalProvider.notifier).state =
                const ConfirmationModalState();
          } else if (actorState.isOpen) {
            ref.read(actorModalProvider.notifier).state =
                const ActorModalState();
          } else if (filterState.isOpen) {
            if (filterState.view == FilterView.optionsList &&
                filterState.isSubMenu) {
              ref.read(filterModalProvider.notifier).state =
                  const FilterModalState(view: FilterView.mainPanel);
            } else {
              ref.read(filterModalProvider.notifier).state =
                  const FilterModalState(view: FilterView.none);
            }
          }
        }
      },
      child: child,
    );
  }
}
