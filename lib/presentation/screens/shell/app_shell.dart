import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/search_provider.dart';
import '../../providers/download_modal_provider.dart';
import '../../providers/filter_modal_provider.dart';
import '../../widgets/quality_selector_sheet.dart';
import '../../../core/utils/toast_utils.dart';
import '../../widgets/main_filter_panel_sheet.dart';
import '../../../data/local/download_manager.dart';
import '../../widgets/filter_selector_sheet.dart';
import '../../widgets/more_modal_content.dart';
import 'dart:async';
import '../../providers/confirmation_modal_provider.dart';
import '../../widgets/confirmation_modal_content.dart';

/// App shell with custom glassmorphism bottom navigation bar
class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _currentIndex = 0;
  bool _isMoreOpen = false;
  DateTime? _lastBackPressed;

  static const _tabs = [
    '/home',
    '/search',
    '/watchlist',
  ];

  static const _icons = [
    Icons.home_outlined,
    Icons.search_outlined,
    Icons.bookmark_outline_rounded,
    Icons.more_horiz_rounded,
  ];

  static const _activeIcons = [
    Icons.home_rounded,
    Icons.search_rounded,
    Icons.bookmark_rounded,
    Icons.more_horiz_rounded,
  ];

  static const _labels = [
    'Home',
    'Explore',
    'Favourite',
    'More',
  ];

  void _onTap(int index) {
    // 4th button (More) toggles the modal instead of navigating
    if (index == 3) {
      setState(() => _isMoreOpen = !_isMoreOpen);
      return;
    }
    // Close more modal if navigating
    if (_isMoreOpen) setState(() => _isMoreOpen = false);
    if (index != _currentIndex) {
      setState(() => _currentIndex = index);
      context.go(_tabs[index]);
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateIndex();
  }

  void _updateIndex() {
    final location = GoRouterState.of(context).uri.toString();
    
    // Check main tabs first
    for (int i = 0; i < 3; i++) {
      if (location == _tabs[i]) {
        if (_currentIndex != i) {
          setState(() => _currentIndex = i);
        }
        return;
      }
    }

    // If it's any other route (anime, korean, bollywood, tv, downloads), it belongs to "More" (index 3)
    if (_currentIndex != 3) {
      setState(() => _currentIndex = 3);
    }
  }

  bool _isTabSelected(int index) {
    if (index < 3) return _currentIndex == index && !_isMoreOpen;
    // More tab is selected if _currentIndex is 3 OR _isMoreOpen is true
    return _currentIndex == 3 || _isMoreOpen;
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
    final isModalOpen = isOtherModalOpen || _isMoreOpen;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        // 1. If more modal is open, close it
        if (_isMoreOpen) {
          setState(() => _isMoreOpen = false);
          return;
        }

        // 2. If search field is focused (Explore tab), unfocus it first
        final isSearchFocused = ref.read(searchFocusProvider);
        if (_currentIndex == 1 && isSearchFocused) {
          FocusManager.instance.primaryFocus?.unfocus();
          return;
        }

        // 2. If download/filter modal is open, close modal or step back
        if (downloadState.isOpen || filterState.isOpen) {
          if (downloadState.isOpen) {
            ref.read(downloadModalProvider.notifier).state =
                const DownloadModalState();
          } else if (filterState.view == FilterView.optionsList &&
              filterState.isSubMenu) {
            ref.read(filterModalProvider.notifier).state =
                const FilterModalState(view: FilterView.mainPanel);
          } else {
            ref.read(filterModalProvider.notifier).state =
                const FilterModalState(view: FilterView.none);
          }
          return;
        }

        // 2. If not on Home Tab, route back to Home Tab
        if (_currentIndex != 0) {
          _onTap(0);
          return;
        }

        // 3. We are on Home Tab. Handle double back to exit
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
          // Double back pressed within 3 seconds, close the app
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
        extendBody: true,
        body: Stack(
          children: [
            widget.child,
            // Barrier to dismiss modal when tapping outside
            if (isModalOpen)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() => _isMoreOpen = false);
                    ref.read(downloadModalProvider.notifier).state =
                        const DownloadModalState();
                    ref.read(filterModalProvider.notifier).state =
                        const FilterModalState(view: FilterView.none);
                    ref.read(confirmationModalProvider.notifier).state =
                        const ConfirmationModalState();
                  },
                  child: Container(color: Colors.black.withValues(alpha: 0.4)),
                ),
              ),
            // Floating Bottom Nav Bar or Download/Filter Modal
            if (!isSearchExpanded)
              Positioned(
                bottom: MediaQuery.paddingOf(context).bottom + 24,
                left: 0,
                right: 0,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.fastOutSlowIn,
                    constraints:
                        BoxConstraints(maxWidth: isOtherModalOpen ? 600 : 400),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: isOtherModalOpen ? 16 : 24),
                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.circular(isOtherModalOpen ? 24 : 32),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.fastOutSlowIn,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius:
                                  BorderRadius.circular(isOtherModalOpen ? 24 : 32),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
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
                              duration: const Duration(milliseconds: 350),
                              curve: Curves.fastOutSlowIn,
                              alignment: Alignment.bottomCenter,
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
                                                  onCancel:
                                                      downloadState.onCancel ??
                                                          () {},
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
                                                        confirmState.onCancel
                                                            ?.call();
                                                        ref
                                                            .read(
                                                                confirmationModalProvider
                                                                    .notifier)
                                                            .state = const ConfirmationModalState();
                                                      },
                                                    )
                                                  : (filterState.view ==
                                                           FilterView.optionsList
                                                      ? FilterSelectorContent(
                                                      title: filterState.title,
                                                      currentValue: filterState
                                                          .currentValue,
                                                      options:
                                                          filterState.options,
                                                      onChanged: filterState
                                                              .onChanged ??
                                                          (_) {},
                                                      onCancel: () {
                                                        if (filterState
                                                            .isSubMenu) {
                                                          ref
                                                                  .read(filterModalProvider
                                                                      .notifier)
                                                                  .state =
                                                              const FilterModalState(
                                                                  view: FilterView
                                                                      .mainPanel);
                                                        } else {
                                                          ref
                                                                  .read(filterModalProvider
                                                                      .notifier)
                                                                  .state =
                                                              const FilterModalState(
                                                                  view:
                                                                      FilterView
                                                                          .none);
                                                        }
                                                      },
                                                    )
                                                  : const MainFilterPanelContent()),
                                    )
                                  : Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // More menu row (animated in/out)
                                        AnimatedSize(
                                          duration: const Duration(milliseconds: 300),
                                          curve: Curves.fastOutSlowIn,
                                          alignment: Alignment.bottomCenter,
                                          child: _isMoreOpen
                                              ? Column(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    MoreModalContent(
                                                      currentRoute: location,
                                                      onClose: () => setState(
                                                          () => _isMoreOpen = false),
                                                    ),
                                                    Padding(
                                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                                      child: Divider(
                                                        height: 1,
                                                        color: Colors.white.withValues(alpha: 0.08),
                                                      ),
                                                    ),
                                                  ],
                                                )
                                              : const SizedBox.shrink(),
                                        ),
                                        // Main navbar row (always visible)
                                        Container(
                                          height: 64,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12),
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
                                                  width: 64,
                                                  alignment: Alignment.center,
                                                  child: Column(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Stack(
                                                        alignment: Alignment.center,
                                                        children: [
                                                          // Active State Icon (uses implicit animation for stability)
                                                          AnimatedOpacity(
                                                            duration: const Duration(milliseconds: 200),
                                                            opacity: isSelected ? 1.0 : 0.0,
                                                            child: Icon(
                                                              _activeIcons[index],
                                                              color: AppColors.primary,
                                                              size: 24,
                                                            ),
                                                          ),
                                                          // Inactive State Icon
                                                          AnimatedOpacity(
                                                            duration: const Duration(milliseconds: 200),
                                                            opacity: isSelected ? 0.0 : 1.0,
                                                            child: Icon(
                                                              _icons[index],
                                                              color: AppColors.textPrimary,
                                                              size: 24,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 2),
                                                      // Stable text animation
                                                      AnimatedDefaultTextStyle(
                                                        duration: const Duration(milliseconds: 200),
                                                        style: TextStyle(
                                                          color: isSelected
                                                              ? AppColors.primary
                                                              : AppColors.textPrimary,
                                                          fontSize: 10,
                                                          fontWeight: isSelected
                                                              ? FontWeight.w600
                                                              : FontWeight.w400,
                                                        ),
                                                        child: Text(_labels[index]),
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
          ],
        ),
      ),
    );
  }
}
