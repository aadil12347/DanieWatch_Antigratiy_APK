import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class StickyDropdownModal<T> extends StatefulWidget {
  final List<T> items;
  final T value;
  final Widget child;
  final String Function(T) itemLabelBuilder;
  final void Function(T) onChanged;
  final double maxHeight;

  const StickyDropdownModal({
    super.key,
    required this.items,
    required this.value,
    required this.child,
    required this.itemLabelBuilder,
    required this.onChanged,
    this.maxHeight = 250,
  });

  @override
  State<StickyDropdownModal<T>> createState() => _StickyDropdownModalState<T>();
}

class _StickyDropdownModalState<T> extends State<StickyDropdownModal<T>> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  void _toggleDropdown() {
    if (_isOpen) {
      _closeDropdown();
    } else {
      _openDropdown();
    }
  }

  void _openDropdown() {
    if (_isOpen) return;
    
    // Close keyboard if active
    FocusScope.of(context).unfocus();

    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    _overlayEntry = _createOverlayEntry(size);
    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _isOpen = true);
  }

  void _closeDropdown() {
    if (!_isOpen) return;
    _overlayEntry?.remove();
    _overlayEntry = null;
    setState(() => _isOpen = false);
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    super.dispose();
  }

  OverlayEntry _createOverlayEntry(Size size) {
    return OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 6), // 6px gap below the button
          child: TapRegion(
            groupId: this,
            onTapOutside: (_) => _closeDropdown(),
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: BoxConstraints(maxHeight: widget.maxHeight),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    shrinkWrap: true,
                    itemCount: widget.items.length,
                    itemBuilder: (context, index) {
                      final item = widget.items[index];
                      final isSelected = item == widget.value;
                      return InkWell(
                        onTap: () {
                          widget.onChanged(item);
                          _closeDropdown();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                widget.itemLabelBuilder(item),
                                style: TextStyle(
                                  color: isSelected ? AppColors.primary : Colors.white,
                                  fontSize: 14,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w400,
                                ),
                              ),
                              if (isSelected)
                                const Icon(Icons.check_rounded, color: AppColors.primary, size: 18),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: this,
      onTapOutside: (_) => _closeDropdown(),
      child: CompositedTransformTarget(
        link: _layerLink,
        child: GestureDetector(
          onTap: _toggleDropdown,
          child: widget.child,
        ),
      ),
    );
  }
}
