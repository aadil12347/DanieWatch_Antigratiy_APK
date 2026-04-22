import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'underline_glow_indicator.dart';

/// Horizontally-scrollable top navbar synced with a PageView via a
/// shared [TabController]. Only category items are shown (no genres).
///
/// Uses the passed TabController directly so the red indicator smoothly
/// tracks swipes and taps. Text sizes animate via AnimatedDefaultTextStyle.
class TopNavbar extends StatefulWidget {
  const TopNavbar({super.key, required this.tabController});

  final TabController tabController;

  static const List<String> items = [
    'Explore',
    'Bollywood',
    'Hollywood',
    'Anime',
    'Korean',
    'Chinese',
    'Punjabi',
  ];

  @override
  State<TopNavbar> createState() => _TopNavbarState();
}

class _TopNavbarState extends State<TopNavbar> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.tabController.index;
    widget.tabController.addListener(_onTabChanged);
  }

  @override
  void didUpdateWidget(covariant TopNavbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabController != widget.tabController) {
      oldWidget.tabController.removeListener(_onTabChanged);
      widget.tabController.addListener(_onTabChanged);
      if (_currentIndex != widget.tabController.index) {
        setState(() {
          _currentIndex = widget.tabController.index;
        });
      }
    }
  }

  void _onTabChanged() {
    // Update text style when tab settles (not during animation)
    if (!widget.tabController.indexIsChanging) {
      final newIndex = widget.tabController.index;
      if (_currentIndex != newIndex) {
        setState(() {
          _currentIndex = newIndex;
        });
      }
    }
  }

  @override
  void dispose() {
    widget.tabController.removeListener(_onTabChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      width: double.infinity,
      color: Colors.transparent,
      child: TabBar(
        controller: widget.tabController,
        isScrollable: true,
        dividerColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        indicator: const UnderlineGlowIndicator(),
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white.withValues(alpha: 0.5),
        // Use default label styles as fallback (TabBar needs these for layout)
        labelStyle: GoogleFonts.inter(
          fontSize: 17,
          fontWeight: FontWeight.bold,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        tabs: List.generate(TopNavbar.items.length, (index) {
          final isSelected = _currentIndex == index;
          return Tab(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              style: isSelected
                  ? GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    )
                  : GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
              child: Text(TopNavbar.items[index]),
            ),
          );
        }),
      ),
    );
  }
}
