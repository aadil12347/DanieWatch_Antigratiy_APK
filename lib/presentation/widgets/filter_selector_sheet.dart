import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';

class FilterSelectorContent extends ConsumerWidget {
  final String title;
  final String currentValue;
  final List<String> options;
  final void Function(String) onChanged;
  final VoidCallback onCancel;

  const FilterSelectorContent({
    super.key,
    required this.title,
    required this.currentValue,
    required this.options,
    required this.onChanged,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
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
                    color: Colors.red.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.tune_rounded,
                      color: Colors.red, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon:
                      const Icon(Icons.close, color: Colors.white54, size: 22),
                  onPressed: onCancel,
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white10, height: 32),

          // ── Options List ───────────────────────────────────────
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (context, index) {
                final option = options[index];
                final isSelected = option == currentValue;

                return InkWell(
                  onTap: () {
                    onChanged(option);
                    onCancel(); // Close after selection
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.transparent,
                    child: Row(
                      children: [
                        Text(
                          option,
                          style: TextStyle(
                            color:
                                isSelected ? Colors.white : AppColors.textMuted,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        if (isSelected)
                          const Icon(Icons.check_circle,
                              color: Colors.red, size: 20),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
