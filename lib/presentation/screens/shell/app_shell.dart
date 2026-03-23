import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/search_provider.dart';
import '../../providers/download_modal_provider.dart';
import '../../widgets/quality_selector_sheet.dart';

/// App shell with custom glassmorphism bottom navigation bar
class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _currentIndex = 0;

  static const _tabs = [
    '/home',
    '/korean', // Mapping Explore to Korean instead of Anime
    '/watchlist',
    '/downloads',
    '/profile',
  ];

  static const _icons = [
    Icons.home_outlined,
    Icons.explore_outlined,
    Icons.bookmark_outline_rounded,
    Icons.download_outlined,
    Icons.person_outline,
  ];

  static const _activeIcons = [
    Icons.home_rounded,
    Icons.explore,
    Icons.bookmark_rounded,
    Icons.download_rounded,
    Icons.person,
  ];

  static const _labels = [
    'Home',
    'Explore',
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
    final isModalOpen = downloadState.isOpen;

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          widget.child,
          // Floating Bottom Nav Bar or Download Modal
          if (!location.contains('/search') && !isSearchExpanded)
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
                                    child: QualitySelectorContent(
                                      m3u8Url: downloadState.m3u8Url ?? '',
                                      title: downloadState.title ?? 'Download',
                                      onSelected: downloadState.onSelected ?? (_) {},
                                      onCancel: downloadState.onCancel ?? () {},
                                    ),
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
    );
  }
}
