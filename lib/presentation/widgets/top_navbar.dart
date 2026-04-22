import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'underline_glow_indicator.dart';

/// Horizontally-scrollable top navbar synced with a PageView via a
/// shared [TabController]. Only category items are shown (no genres).
class TopNavbar extends StatelessWidget {
  const TopNavbar({super.key, required this.tabController});

  final TabController tabController;

  /// Category items shown in the navbar (genres removed per user request).
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
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      width: double.infinity,
      color: Colors.transparent,
      child: TabBar(
        controller: tabController,
        isScrollable: true,
        dividerColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        indicator: const UnderlineGlowIndicator(),
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: GoogleFonts.inter(
          fontSize: 17,
          fontWeight: FontWeight.bold,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white.withValues(alpha: 0.5),
        tabs: items.map((label) => Tab(text: label)).toList(),
      ),
    );
  }
}
