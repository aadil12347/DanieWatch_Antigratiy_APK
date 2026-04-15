import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/search_provider.dart';
import 'underline_glow_indicator.dart';

class TopNavbar extends ConsumerWidget {
  const TopNavbar({super.key});

  static const List<String> items = [
    'Explore',
    'Bollywood',
    'Hollywood',
    'Anime',
    'Korean',
    'Chinese',
    'Punjabi',
    'Pakistani',
    'Action',
    'Comedy',
    'Romance',
    'Horror',
    'Drama',
    'Thriller',
    'Sci-Fi',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchState = ref.watch(searchProvider('explore'));
    final filters = searchState.filters;

    // Determine which item is currently active
    int selectedIndex = 0; // Default to 'Explore'

    if (filters.categories.isNotEmpty) {
      final activeCategory = filters.categories.firstWhere(
        (c) => items.contains(c),
        orElse: () => '',
      );
      if (activeCategory.isNotEmpty) {
        selectedIndex = items.indexOf(activeCategory);
      } else {
        selectedIndex = -1;
      }
    } else if (filters.genres.isNotEmpty) {
      // Check if any selected genre is present in our navbar list
      final activeGenre = filters.genres.firstWhere(
        (g) => items.contains(g),
        orElse: () => '',
      );
      if (activeGenre.isNotEmpty) {
        selectedIndex = items.indexOf(activeGenre);
      } else {
        // Genre selected but not in navbar
        selectedIndex = -1;
      }
    } else if (filters.hasActiveFilters) {
      // Other filters (Year, Language, etc.) but no category/genre
      selectedIndex = -1;
    } else {
      selectedIndex = 0; // Clear state -> Explore
    }

    return DefaultTabController(
      length: items.length,
      initialIndex: selectedIndex < 0 ? 0 : selectedIndex,
      child: Container(
        height: 60,
        width: double.infinity,
        color: Colors.transparent,
        child: TabBar(
          isScrollable: true,
          dividerColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          onTap: (index) => _onItemTapped(ref, items[index], filters),
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
      ),
    );
  }

  void _onItemTapped(WidgetRef ref, String label, SearchFilters currentFilters) {
    final notifier = ref.read(searchProvider('explore').notifier);
    
    if (label == 'Explore') {
      // Clear all filters to return to fresh Explore state
      notifier.updateFilters(const SearchFilters());
      return;
    }

    // Is it a category or a genre?
    const categories = {
      'Bollywood', 
      'Hollywood', 
      'Anime', 
      'Korean', 
      'Chinese', 
      'Punjabi', 
      'Pakistani'
    };
    const genres = {
      'Action', 
      'Comedy', 
      'Romance', 
      'Horror', 
      'Drama', 
      'Thriller', 
      'Sci-Fi'
    };

    if (categories.contains(label)) {
      // Reset filters and apply the new category
      notifier.updateFilters(SearchFilters(categories: {label}));
    } else if (genres.contains(label)) {
      // Reset filters and apply the new genre
      notifier.updateFilters(SearchFilters(genres: {label}));
    }
  }
}
