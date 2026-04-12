import 'dart:ui';
import '../../../core/utils/responsive.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/search_provider.dart';
import '../../providers/download_modal_provider.dart';
import '../../providers/filter_modal_provider.dart';
import '../../widgets/quality_selector_sheet.dart';
import '../../../core/utils/toast_utils.dart';
import '../../widgets/main_filter_panel_sheet.dart';
import '../../../data/local/download_manager.dart';
import '../../widgets/filter_selector_sheet.dart';
import 'dart:async';
import '../../providers/confirmation_modal_provider.dart';
import '../../widgets/confirmation_modal_content.dart';
import '../../providers/scroll_provider.dart';

/// App shell with custom glassmorphism bottom navigation bar
class AppShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  DateTime? _lastBackPressed;

  static const _icons = [
    Icons.home_outlined,
    Icons.search_outlined,
    Icons.bookmark_outline_rounded,
    Icons.download_outlined,
  ];

  static const _activeIcons = [
    Icons.home_rounded,
    Icons.search_rounded,
    Icons.bookmark_rounded,
    Icons.download_rounded,
  ];

  static const _labels = [
    'Home',
    'Explore',
    'Favourite',
    'Downloads',
  ];

  static void closeModals(WidgetRef ref) {
    // 1. Close "More" if open (this is local state in AppShell, but we can't easily reach it from static)
    // Actually, for consistency, we'll keep _isMoreOpen in AppShell for now,
    // and let its own PopScope handle that if needed, or better, move it to a provider.
    // Let's only close the providers for now.

    ref.read(downloadModalProvider.notifier).state = const DownloadModalState();
    ref.read(filterModalProvider.notifier).state =
        const FilterModalState(view: FilterView.none);
    ref.read(confirmationModalProvider.notifier).state =
        const ConfirmationModalState();
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

  @override
  void initState() {
    super.initState();
    _downloadSub =
        DownloadManager.instance.updateStream.listen(_handleDownloadUpdate);
  }

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
    _downloadSub?.cancel();
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
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final isSearchExpanded = ref.watch(searchExpandedProvider);

    final downloadState = ref.watch(downloadModalProvider);
    final filterState = ref.watch(filterModalProvider);
    final confirmState = ref.watch(confirmationModalProvider);
    final isOtherModalOpen =
        downloadState.isOpen || filterState.isOpen || confirmState.isOpen;
    final isModalOpen = isOtherModalOpen;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;


        // 2. If global modals are open, close them
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

        // 5. Double back to exit (only on Home tab with no modals)
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
            widget.navigationShell,
            // Barrier to dismiss modal when tapping outside
            if (isModalOpen)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _closeAllModals,
                  child: Container(color: Colors.black.withValues(alpha: 0.4)),
                ),
              ),
            // Floating Bottom Nav Bar or Download/Filter Modal
            if (!isSearchExpanded)
              Builder(builder: (context) {
                final r = Responsive(context);
                final navBottom = MediaQuery.paddingOf(context).bottom + r.h(24);
                final navMaxWidth = isOtherModalOpen ? r.wClamped(600, minVal: 320) : r.wClamped(400, minVal: 280);
                final navHPad = isOtherModalOpen ? r.w(16) : r.w(24);
                final navRadius = isOtherModalOpen ? r.w(24) : r.w(32);
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
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOutCubic,
                      constraints: BoxConstraints(maxWidth: navMaxWidth),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: navHPad),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(navRadius),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeInOutCubic,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(navRadius),
                                border: Border.all(
                                  color: AppColors.surface.withValues(alpha: 0.15),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    blurRadius: 20,
                                    spreadRadius: -5,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: AnimatedSize(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeInOutCubic,
                                alignment: Alignment.bottomCenter,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 150),
                                  switchInCurve: Curves.easeOut,
                                  switchOutCurve: Curves.easeIn,
                                  transitionBuilder: (child, animation) {
                                    return FadeTransition(
                                      opacity: animation,
                                      child: ScaleTransition(
                                        scale: Tween<double>(begin: 0.96, end: 1.0).animate(animation),
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: isOtherModalOpen
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
                                    : Column(
                                        key: const ValueKey('navbar_column'),
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Main navbar row (always visible)
                                          Container(
                                            height: navHeight,
                                            padding: EdgeInsets.symmetric(
                                                horizontal: r.w(12)),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceEvenly,
                                              children: List.generate(4, (index) {
                                                final isSelected = _isTabSelected(index);
                                                return GestureDetector(
                                                  onTap: () => _onTap(index),
                                                  behavior: HitTestBehavior.opaque,
                                                  child: Container(
                                                    key: ValueKey('tab_$index'),
                                                    width: tabWidth,
                                                    alignment: Alignment.center,
                                                    child: Column(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Stack(
                                                          alignment: Alignment.center,
                                                          children: [
                                                            AnimatedOpacity(
                                                              duration: const Duration(milliseconds: 150),
                                                              opacity: isSelected ? 1.0 : 0.0,
                                                              child: Icon(
                                                                _activeIcons[index],
                                                                color: AppColors.primary,
                                                                size: iconSize,
                                                              ),
                                                            ),
                                                            AnimatedOpacity(
                                                              duration: const Duration(milliseconds: 150),
                                                              opacity: isSelected ? 0.0 : 1.0,
                                                              child: Icon(
                                                                _icons[index],
                                                                color: AppColors.textPrimary,
                                                                size: iconSize,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        SizedBox(height: r.h(2)),
                                                        FittedBox(
                                                          fit: BoxFit.scaleDown,
                                                          child: AnimatedDefaultTextStyle(
                                                            duration: const Duration(milliseconds: 150),
                                                            style: GoogleFonts.inter(
                                                              color: isSelected
                                                                  ? AppColors.primary
                                                                  : AppColors.textPrimary,
                                                              fontSize: labelSize,
                                                              fontWeight: isSelected
                                                                  ? FontWeight.w600
                                                                  : FontWeight.w500,
                                                              letterSpacing: -0.2,
                                                            ),
                                                            child: Text(
                                                              _labels[index],
                                                              maxLines: 1,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              }),
                                            ),
                                          ),
                                        ],
                                      ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
          ],
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
    final isModalOpen =
        downloadState.isOpen || filterState.isOpen || confirmState.isOpen;

    return PopScope(
      canPop: !isModalOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && isModalOpen) {
          if (downloadState.isOpen) {
            ref.read(downloadModalProvider.notifier).state =
                const DownloadModalState();
          } else if (confirmState.isOpen) {
            ref.read(confirmationModalProvider.notifier).state =
                const ConfirmationModalState();
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
