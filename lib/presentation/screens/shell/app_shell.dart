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
import '../../widgets/filter_selector_sheet.dart';
import '../../widgets/main_filter_panel_sheet.dart';

/// App shell with custom glassmorphism bottom navigation bar
class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _currentIndex = 0;
  DateTime? _lastBackPressed;

  static const _tabs = [
    '/home',
    '/search', // Replacing explore with search
    '/watchlist',
    '/downloads',
    '/profile',
  ];

  static const _icons = [
    Icons.home_outlined,
    Icons.search_outlined,
    Icons.bookmark_outline_rounded,
    Icons.download_outlined,
    Icons.person_outline,
  ];

  static const _activeIcons = [
    Icons.home_rounded,
    Icons.search_rounded,
    Icons.bookmark_rounded,
    Icons.download_rounded,
    Icons.person,
  ];

  static const _labels = [
    'Home',
    'Search',
    'My List',
    'Download',
    'Profile',
  ];

  void _onTap(int index) {
    if (index != _currentIndex) {
      setState(() => _currentIndex = index);
      // Failsafe for missing directories, let's keep it mostly intact but only route if we want.
      // We will try routing and handle missing gracefully, but standard go_router is what we use.
      context.go(_tabs[index]);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateIndex();
  }

  void _updateIndex() {
    final location = GoRouterState.of(context).uri.toString();
    for (int i = 0; i < _tabs.length; i++) {
      if (location.startsWith(_tabs[i])) {
        if (_currentIndex != i) {
          setState(() => _currentIndex = i);
        }
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final isSearchExpanded = ref.watch(searchExpandedProvider);
    // Only keeping the first 4 tabs
    final _bottomTabs = _tabs.sublist(0, 4);
    final _bottomIcons = _icons.sublist(0, 4);
    final _bottomActiveIcons = _activeIcons.sublist(0, 4);

    final downloadState = ref.watch(downloadModalProvider);
    final filterState = ref.watch(filterModalProvider);
    final isModalOpen = downloadState.isOpen || filterState.isOpen;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        // 1. If modal is open, close modal or step back
        if (isModalOpen) {
          if (downloadState.isOpen) {
            ref.read(downloadModalProvider.notifier).state = const DownloadModalState();
          } else if (filterState.view == FilterView.optionsList && filterState.isSubMenu) {
            ref.read(filterModalProvider.notifier).state = const FilterModalState(view: FilterView.mainPanel);
          } else {
            ref.read(filterModalProvider.notifier).state = const FilterModalState(view: FilterView.none);
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
        if (_lastBackPressed == null || now.difference(_lastBackPressed!) > const Duration(seconds: 3)) {
          _lastBackPressed = now;
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Press back again to close the app'),
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.surfaceElevated,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
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
                    ref.read(downloadModalProvider.notifier).state = const DownloadModalState();
                    ref.read(filterModalProvider.notifier).state = const FilterModalState(view: FilterView.none);
                  },
                  child: Container(color: Colors.black.withOpacity(0.4)),
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
                  constraints: BoxConstraints(maxWidth: isModalOpen ? 600 : 400),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: isModalOpen ? 16 : 24),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(isModalOpen ? 24 : 32),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.fastOutSlowIn,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(isModalOpen ? 24 : 32),
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
                            child: isModalOpen
                                ? Material(
                                    color: Colors.transparent,
                                    child: downloadState.isOpen
                                        ? QualitySelectorContent(
                                            m3u8Url: downloadState.m3u8Url ?? '',
                                            title: downloadState.title ?? 'Download',
                                            onSelected: downloadState.onSelected ?? (_) {},
                                            onCancel: downloadState.onCancel ?? () {},
                                          )
                                        : (filterState.view == FilterView.optionsList
                                            ? FilterSelectorContent(
                                                title: filterState.title,
                                                currentValue: filterState.currentValue,
                                                options: filterState.options,
                                                onChanged: filterState.onChanged ?? (_) {},
                                                onCancel: () {
                                                  if (filterState.isSubMenu) {
                                                    ref.read(filterModalProvider.notifier).state = const FilterModalState(view: FilterView.mainPanel);
                                                  } else {
                                                    ref.read(filterModalProvider.notifier).state = const FilterModalState(view: FilterView.none);
                                                  }
                                                },
                                              )
                                            : const MainFilterPanelContent()),
                                  )
                                : Container(
                                    height: 64,
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      children: List.generate(_bottomTabs.length, (index) {
                                        final isSelected = _currentIndex == index;
                                        return GestureDetector(
                                          onTap: () => _onTap(index),
                                          behavior: HitTestBehavior.opaque,
                                          child: Container(
                                            width: 56,
                                            alignment: Alignment.center,
                                            child: TweenAnimationBuilder<double>(
                                              tween: Tween(
                                                begin: isSelected ? 0.0 : 1.0,
                                                end: isSelected ? 1.0 : 0.0,
                                              ),
                                              duration: const Duration(milliseconds: 200),
                                              builder: (context, value, child) {
                                                return Stack(
                                                  alignment: Alignment.center,
                                                  children: [
                                                    Opacity(
                                                      opacity: value,
                                                      child: Icon(
                                                        _bottomActiveIcons[index],
                                                        color: AppColors.primary,
                                                        size: 26,
                                                      ),
                                                    ),
                                                    Opacity(
                                                      opacity: 1.0 - value,
                                                      child: Icon(
                                                        _bottomIcons[index],
                                                        color: AppColors.textPrimary,
                                                        size: 24,
                                                      ),
                                                    ),
                                                  ],
                                                );
                                              },
                                            ),
                                          ),
                                        );
                                      }),
                                    ),
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
