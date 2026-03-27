import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/search_provider.dart';

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
    return Stack(
      children: [
        Positioned.fill(
          child: widget.extendBehindAppBar
              ? widget.child
              : Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: widget.child,
                ),
        ),
      ],
    );
  }

  void _onSearchChanged(String query) {
    ref.read(searchProvider.notifier).search(query);
  }
}
