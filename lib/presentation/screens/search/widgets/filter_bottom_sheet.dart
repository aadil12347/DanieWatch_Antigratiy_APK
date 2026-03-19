import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../providers/search_provider.dart';

class FilterBottomSheet extends StatefulWidget {
  final SearchFilters initialFilters;
  final Function(SearchFilters) onApply;

  const FilterBottomSheet({
    super.key,
    required this.initialFilters,
    required this.onApply,
  });

  @override
  State<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<FilterBottomSheet> {
  late SearchFilters _currentFilters;

  final List<String> _categories = ['Movie', 'Series'];
  final List<String> _genres = [
    'Action', 'Comedy', 'Drama', 'Sci-Fi', 'Horror', 'Romance', 'Thriller', 'Animation', 'Mystery'
  ];
  final List<String> _sortOptions = ['Popularity', 'Latest Release'];

  List<String> _periods = [];
  late int _earliestYear;
  final int _minYear = 2000;

  @override
  void initState() {
    super.initState();
    _currentFilters = widget.initialFilters;
    _earliestYear = DateTime.now().year - 4; // Latest 5 years initially
    _generatePeriods();
  }

  void _generatePeriods() {
    _periods = ['All Periods'];
    int currentYear = DateTime.now().year;
    for (int y = currentYear; y >= _earliestYear; y--) {
      _periods.add(y.toString());
    }
    if (_earliestYear > _minYear) {
      _periods.add('+ More');
    }
  }

  void _toggleList(List<String> currentList, String item, bool isExclusive) {
    setState(() {
      if (isExclusive) {
        if (!currentList.contains(item)) {
          currentList.clear();
          currentList.add(item);
        }
      } else {
        if (currentList.contains(item)) {
          currentList.remove(item);
        } else {
          currentList.add(item);
        }
      }
    });
  }

  void _handlePeriodSelect(String val) {
    if (val == '+ More') {
      setState(() {
        _earliestYear = (_earliestYear - 5);
        if (_earliestYear < _minYear) {
          _earliestYear = _minYear;
        }
        _generatePeriods();
      });
      return;
    }
    
    final list = List<String>.from(_currentFilters.periods);
    _toggleList(list, val, false);
    setState(() {
      _currentFilters = _currentFilters.copyWith(periods: list);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.85),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              // Drag Handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Sort & Filter',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 24),
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSection('Categories', _categories, _currentFilters.categories, false, (val) {
                        final list = List<String>.from(_currentFilters.categories);
                        _toggleList(list, val, false);
                        _currentFilters = _currentFilters.copyWith(categories: list);
                      }),
                      _buildSection('Genre', _genres, _currentFilters.genres, false, (val) {
                        final list = List<String>.from(_currentFilters.genres);
                        _toggleList(list, val, false);
                        _currentFilters = _currentFilters.copyWith(genres: list);
                      }),
                      _buildSection('Time/Periods', _periods, _currentFilters.periods, true, (val) {
                        _handlePeriodSelect(val);
                      }),
                      _buildSection('Sort', _sortOptions, [_currentFilters.sortBy], true, (val) {
                        setState(() {
                          _currentFilters = _currentFilters.copyWith(sortBy: val);
                        });
                      }),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              // Buttons
              Container(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: 16,
                  bottom: MediaQuery.paddingOf(context).bottom + 24,
                ),
                decoration: BoxDecoration(
                  color: AppColors.background.withValues(alpha: 0.95),
                  border: Border(
                    top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: TextButton(
                        onPressed: () {
                          setState(() {
                            _currentFilters = const SearchFilters();
                          });
                        },
                        style: TextButton.styleFrom(
                          backgroundColor: AppColors.surfaceElevated,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        child: const Text(
                          'Reset',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () {
                          widget.onApply(_currentFilters);
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          elevation: 8,
                          shadowColor: AppColors.primary.withValues(alpha: 0.5),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        child: const Text(
                          'Apply',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(
    String title,
    List<String> options,
    List<String> selectedOptions,
    bool isSingleSelect,
    Function(String) onSelect,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: options.map((option) {
              final isSelected = selectedOptions.contains(option);
              return GestureDetector(
                onTap: () => onSelect(option),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.primary.withValues(alpha: 0.5),
                      width: 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            )
                          ]
                        : null,
                  ),
                  child: Text(
                    option,
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppColors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
