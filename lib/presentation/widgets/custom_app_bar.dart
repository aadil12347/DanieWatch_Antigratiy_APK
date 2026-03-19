import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../providers/search_provider.dart';
import '../screens/search/widgets/filter_bottom_sheet.dart';

class CustomAppBar extends ConsumerStatefulWidget {
  final Widget child;
  final bool isSearchScreen;
  final bool showBackButton;
  final bool extendBehindAppBar;
  const CustomAppBar({
    super.key, 
    required this.child, 
    this.isSearchScreen = false,
    this.showBackButton = false,
    this.extendBehindAppBar = true,
  });

  @override
  ConsumerState<CustomAppBar> createState() => _CustomAppBarState();
}

class _CustomAppBarState extends ConsumerState<CustomAppBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  bool _isVisible = true;
  late bool _isSearchExpanded;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _isSearchExpanded = widget.isSearchScreen;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -1.0),
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
    _fadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (widget.isSearchScreen) {
          _isVisible = true;
          _searchFocus.requestFocus();
        }
      }
    });

    final currentQuery = ref.read(searchProvider).query;
    if (currentQuery.isNotEmpty) {
      _searchController.text = currentQuery;
    }
    
    // Sync expanded state with provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(searchExpandedProvider.notifier).state = _isSearchExpanded;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _handleScroll(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      if (notification.metrics.axis == Axis.vertical) {
        if (notification.scrollDelta != null) {
          if (notification.scrollDelta! > 10 &&
              _isVisible &&
              !_isSearchExpanded) {
            // Scrolling down, hide (only if search is not expanded)
            _isVisible = false;
            _controller.forward();
          } else if (notification.scrollDelta! < -10 && !_isVisible) {
            // Scrolling up, show
            _isVisible = true;
            _controller.reverse();
          } else if (notification.metrics.pixels <= 0 && !_isVisible) {
            // At top, force show
            _isVisible = true;
            _controller.reverse();
          }
        }
      }
    }
  }

  void _toggleSearch() {
    setState(() {
      _isSearchExpanded = !_isSearchExpanded;
      if (_isSearchExpanded) {
        // Ensure the bar is visible when expanding
        if (!_isVisible) {
          _isVisible = true;
          _controller.reverse();
        }
        context.go('/search');
        // Delay focus slightly to let the animation start
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
          ref.read(searchExpandedProvider.notifier).state = true;
          _searchFocus.requestFocus();
        }
        });
      } else {
        _searchFocus.unfocus();
        _searchController.clear();
        ref.read(searchExpandedProvider.notifier).state = false;
      }
    });
  }

  void _closeSearch() {
    _searchFocus.unfocus();
    ref.read(searchExpandedProvider.notifier).state = false;
    if (context.canPop()) {
      context.pop();
      // Clear after pop animation finishes
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _searchController.clear();
          ref.read(searchProvider.notifier).search('');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final bool hidePill = !widget.isSearchScreen && location == '/search';

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        _handleScroll(notification);
        return false;
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: widget.extendBehindAppBar
                ? widget.child
                : Padding(
                    padding: const EdgeInsets.only(top: 96),
                    child: widget.child,
                  ),
          ),
          // Floating pill NavBar
          if (!hidePill)
            Positioned(
              top: 0, left: 0, right: 0,
              child: SizeTransition(
                sizeFactor: ReverseAnimation(_controller),
                axisAlignment: -1.0,
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: 16,
                    bottom: 16,
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: SlideTransition(
                    position: _slideAnimation,
                    child: AnimatedBuilder(
                      animation: _fadeAnimation,
                      builder: (context, child) {
                        final fadeValue = _fadeAnimation.value;
                        return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 400),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(32),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: (10 * fadeValue).clamp(0.001, 10.0),
                                  sigmaY: (10 * fadeValue).clamp(0.001, 10.0),
                                ),
                                child: Hero(
                                  tag: 'custom_search_bar_hero',
                                  child: Container(
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.5 * fadeValue),
                                      borderRadius: BorderRadius.circular(32),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.1 * fadeValue),
                                        width: 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.2 * fadeValue),
                                          blurRadius: 20,
                                          spreadRadius: -5,
                                          offset: const Offset(0, 10),
                                        ),
                                      ],
                                    ),
                                    child: Opacity(
                                      opacity: fadeValue.clamp(0.0, 1.0),
                                      child: LayoutBuilder(
                                        builder: (context, constraints) {
                                          return Stack(
                                            alignment: Alignment.centerRight,
                                            children: [
                                              // Right Side: Search / Expanding Input Layer (Rendered FIRST so it is behind the back arrow)
                                              Positioned(
                                                top: 0,
                                                bottom: 0,
                                                right: 12,
                                                child: Center(
                                                  child: AnimatedContainer(
                                                    duration: const Duration(milliseconds: 400),
                                                    curve: Curves.easeOutCubic,
                                                    width: (_isSearchExpanded ? constraints.maxWidth - 52 : 44).clamp(0.0, double.infinity).toDouble(),
                                                    height: 44,
                                                    decoration: const BoxDecoration(
                                                      color: Colors.transparent,
                                                    ),
                                                    child: Stack(
                                                      alignment: Alignment.centerRight,
                                                      children: [
                                                        // The expanding content
                                                        ClipRRect(
                                                          borderRadius: BorderRadius.circular(32),
                                                          child: OverflowBox(
                                                            alignment: Alignment.centerRight,
                                                            maxWidth: (constraints.maxWidth - 52).clamp(150.0, 400.0).toDouble(),
                                                            minWidth: (constraints.maxWidth - 52).clamp(150.0, 400.0).toDouble(),
                                                            maxHeight: 44,
                                                            minHeight: 44,
                                                            child: AnimatedOpacity(
                                                              duration: const Duration(milliseconds: 300),
                                                              opacity: _isSearchExpanded ? 1.0 : 0.0,
                                                              child: Stack(
                                                                alignment: Alignment.centerRight,
                                                                children: [
                                                                  // Text Field (Back layer)
                                                                  Positioned.fill(
                                                                    child: IgnorePointer(
                                                                      ignoring: !_isSearchExpanded,
                                                                      child: Material( // Wrapped TextField in Material
                                                                        type: MaterialType.transparency,
                                                                        child: TextField(
                                                                          controller: _searchController,
                                                                          focusNode: _searchFocus,
                                                                          autofocus: widget.isSearchScreen,
                                                                          cursorColor: AppColors.primary,
                                                                          onChanged: (val) {
                                                                            _onSearchChanged(val);
                                                                            setState((){});
                                                                          },
                                                                          style: const TextStyle(
                                                                            color: AppColors.textPrimary,
                                                                            fontSize: 16,
                                                                            fontWeight: FontWeight.w400,
                                                                          ),
                                                                          decoration: const InputDecoration(
                                                                            isDense: true,
                                                                            hintText: "",
                                                                            border: InputBorder.none,
                                                                            focusedBorder: InputBorder.none,
                                                                            enabledBorder: InputBorder.none,
                                                                            contentPadding: EdgeInsets.only(left: 48, right: 44, top: 12, bottom: 12), 
                                                                          ),
                                                                          onSubmitted: (_) => _searchFocus.unfocus(),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  // Buttons (Front layer)
                                                                  Row(
                                                                    mainAxisSize: MainAxisSize.min,
                                                                    children: [
                                                                      // Clear Button
                                                                      AnimatedOpacity(
                                                                        duration: const Duration(milliseconds: 200),
                                                                        opacity: (_isSearchExpanded && _searchController.text.isNotEmpty) ? 1.0 : 0.0,
                                                                        child: IconButton(
                                                                          onPressed: () {
                                                                            _searchController.clear();
                                                                            _onSearchChanged('');
                                                                            setState((){});
                                                                          },
                                                                          icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary, size: 18),
                                                                          padding: EdgeInsets.zero,
                                                                          constraints: const BoxConstraints(minWidth: 32, minHeight: 44),
                                                                        ),
                                                                      ),
                                                                      // Filter Button
                                                                      IconButton(
                                                                        onPressed: _showFilterSheet,
                                                                        icon: const Icon(Icons.tune_rounded, color: AppColors.primary, size: 20),
                                                                        padding: EdgeInsets.zero,
                                                                        constraints: const BoxConstraints(minWidth: 32, minHeight: 44),
                                                                      ),
                                                                      // Space for Search Icon
                                                                      const SizedBox(width: 44),
                                                                    ],
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        // Search Icon
                                                        Positioned(
                                                          right: 0,
                                                          child: IconButton(
                                                            onPressed: () {
                                                              if (!_isSearchExpanded) {
                                                                 context.push('/search');
                                                              } else {
                                                                 _searchFocus.unfocus();
                                                                 setState((){});
                                                              }
                                                            },
                                                            icon: Icon(
                                                              Icons.search_rounded,
                                                              color: _isSearchExpanded ? AppColors.primary : AppColors.textPrimary,
                                                              size: 22,
                                                            ),
                                                            padding: EdgeInsets.zero,
                                                            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                                                            splashRadius: 22,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),

                                              // Left Icon: Profile -> Back Arrow Layer (Rendered SECOND so it is ON TOP of the text field)
                                              Positioned(
                                                top: 0,
                                                bottom: 0,
                                                left: 8,
                                                child: Center(
                                                  child: Container(
                                                    width: 44,
                                                    height: 44,
                                                    alignment: Alignment.center,
                                                    child: Material(
                                                      type: MaterialType.transparency,
                                                      child: IconButton(
                                                        onPressed: () {
                                                          if (_isSearchExpanded) {
                                                            _closeSearch();
                                                          } else if (widget.showBackButton) {
                                                            context.pop();
                                                          } else {
                                                            ScaffoldMessenger.of(context).showSnackBar(
                                                              const SnackBar(content: Text('Profile login coming soon')),
                                                            );
                                                          }
                                                        },
                                                        icon: AnimatedSwitcher(
                                                          duration: const Duration(milliseconds: 300),
                                                          child: Icon(
                                                            _isSearchExpanded 
                                                                ? Icons.arrow_back_ios_new_rounded 
                                                                : (widget.showBackButton ? Icons.arrow_back_rounded : Icons.person_rounded),
                                                            key: ValueKey('${_isSearchExpanded}_${widget.showBackButton}'),
                                                            color: AppColors.textPrimary,
                                                            size: 24,
                                                          ),
                                                        ),
                                                        padding: EdgeInsets.zero,
                                                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                                                        splashRadius: 22,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ), // SlideTransition
                ), // Material
              ), // Padding
            ), // SizeTransition
            ), // Positioned
        ],
      ),
    );
  }

  void _onSearchChanged(String query) {
    ref.read(searchProvider.notifier).search(query);
  }

  void _showFilterSheet() {
    final searchFilters = ref.read(searchProvider).filters;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => FilterBottomSheet(
        initialFilters: searchFilters,
        onApply: (newFilters) {
          ref.read(searchProvider.notifier).updateFilters(newFilters);
        },
      ),
    );
  }
}
