import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../providers/search_provider.dart';
import '../providers/filter_modal_provider.dart';
import 'filter_selector_sheet.dart';

class MainFilterPanelContent extends ConsumerStatefulWidget {
  const MainFilterPanelContent({super.key});

  @override
  ConsumerState<MainFilterPanelContent> createState() => _MainFilterPanelContentState();
}

class _MainFilterPanelContentState extends ConsumerState<MainFilterPanelContent> {

  void _showSelectionModal(String title, String currentValue, List<String> options, Function(String) onChanged) {
    ref.read(filterModalProvider.notifier).state = FilterModalState(
      view: FilterView.optionsList,
      title: title,
      currentValue: currentValue,
      options: options,
      onChanged: onChanged,
      isSubMenu: true, // Tell it to return to mainPanel on cancel
    );
  }

  Widget _buildDropdownSection(String title, String value, List<String> options, Function(String) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _showSelectionModal(title, value, options, onChanged),
          child: Container(
            height: 48,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 16)),
                const Icon(Icons.keyboard_arrow_down, color: Colors.white54),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final filters = searchState.filters;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.tune_rounded, color: Colors.red, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Filters',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 22),
                  onPressed: () => ref.read(filterModalProvider.notifier).state = const FilterModalState(view: FilterView.none),
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white10, height: 24),

          // ── Options List ───────────────────────────────────────
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDropdownSection('Genre', filters.genre, ['All Genres', 'Action', 'Animation', 'Comedy', 'Crime', 'Documentary', 'Drama', 'Family', 'Fantasy', 'History', 'Horror', 'Music', 'Mystery', 'Romance', 'Science Fiction', 'Thriller', 'War', 'Western'], (val) {
                     ref.read(searchProvider.notifier).updateFilters(filters.copyWith(genre: val));
                  }),
                  _buildDropdownSection('Year', filters.year, ['All Years', '2026', '2025', '2024', '2023', '2022', '2021', '2020', '2019', '2018', '2017', '2016'], (val) {
                     ref.read(searchProvider.notifier).updateFilters(filters.copyWith(year: val));
                  }),
                  _buildDropdownSection('Country', filters.country, ['All Countries', 'United States', 'United Kingdom', 'South Korea', 'Japan', 'India'], (val) {
                     ref.read(searchProvider.notifier).updateFilters(filters.copyWith(country: val));
                  }),
                  _buildDropdownSection('Sort By', filters.sortBy, ['Popularity (High to Low)', 'Popularity (Low to High)', 'Rating (High to Low)', 'Rating (Low to High)', 'Release Date (Newest)'], (val) {
                     ref.read(searchProvider.notifier).updateFilters(filters.copyWith(sortBy: val));
                  }),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () {
                        ref.read(filterModalProvider.notifier).state = const FilterModalState(view: FilterView.none);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Apply Filters', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
