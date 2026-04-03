import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/search_provider.dart';

class TopNavbar extends ConsumerWidget {
  const TopNavbar({super.key});

  static const List<String> items = [
    'Explore',
    'Korean',
    'Anime',
    'Bollywood',
    'Action',
    'Comedy',
    'Thriller',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchState = ref.watch(searchProvider);
    final filters = searchState.filters;

    // Determine which item is currently active
    // Determine which item is currently active
    int selectedIndex = 0; // Default to 'Explore'

    if (filters.categories.contains('Korean')) {
      selectedIndex = 1;
    } else if (filters.categories.contains('Anime')) {
      selectedIndex = 2;
    } else if (filters.categories.contains('Bollywood')) {
      selectedIndex = 3;
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

    return Container(
      height: 60,
      width: double.infinity,
      color: Colors.transparent,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final isSelected = selectedIndex == index;
            final label = items[index];

            return GestureDetector(
              onTap: () => _onItemTapped(ref, label, filters),
              child: Padding(
                padding: const EdgeInsets.only(right: 32.0),
                child: Center(
                  child: AnimatedScale(
                    scale: isSelected ? 1.12 : 1.0,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutBack,
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      style: GoogleFonts.inter(
                        fontSize: isSelected ? 17 : 15,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected 
                            ? Colors.white 
                            : Colors.white.withValues(alpha: 0.5),
                        shadows: isSelected ? [
                          Shadow(
                            color: Colors.white.withValues(alpha: 0.4),
                            blurRadius: 15,
                            offset: Offset.zero,
                          ),
                        ] : [],
                      ),
                      child: Text(label),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _onItemTapped(WidgetRef ref, String label, SearchFilters currentFilters) {
    final notifier = ref.read(searchProvider.notifier);
    
    if (label == 'Explore') {
      // Clear all filters to return to fresh Explore state
      notifier.updateFilters(const SearchFilters());
      return;
    }

    // Is it a category or a genre?
    const categories = {'Korean', 'Anime', 'Bollywood'};
    const genres = {'Action', 'Comedy', 'Thriller'};

    if (categories.contains(label)) {
      // Reset filters and apply the new category
      notifier.updateFilters(SearchFilters(categories: {label}));
    } else if (genres.contains(label)) {
      // Reset filters and apply the new genre
      notifier.updateFilters(SearchFilters(genres: {label}));
    }
  }
}
