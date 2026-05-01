import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';

/// A dropdown-style button that opens a scrollable popup anchored directly
/// below the trigger button. Uses OverlayEntry so touches outside the
/// dropdown pass through to the underlying scroll view (closing the dropdown).
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
    this.maxHeight = 300,
  });

  @override
  State<StickyDropdownModal<T>> createState() => _StickyDropdownModalState<T>();
}

class _StickyDropdownModalState<T> extends State<StickyDropdownModal<T>>
    with SingleTickerProviderStateMixin {
  final GlobalKey _buttonKey = GlobalKey();
  OverlayEntry? _barrierEntry;
  OverlayEntry? _dropdownEntry;
  bool _isOpen = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _scaleAnim = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _close(animate: false);
    _animController.dispose();
    super.dispose();
  }

  void _open() {
    if (_isOpen) return;
    HapticFeedback.selectionClick();

    final renderBox =
        _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final buttonSize = renderBox.size;
    final buttonPos = renderBox.localToGlobal(Offset.zero);
    final buttonRect = Rect.fromLTWH(
      buttonPos.dx,
      buttonPos.dy,
      buttonSize.width,
      buttonSize.height,
    );

    // Barrier: transparent, detects touches but passes them through
    _barrierEntry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _close(),
        ),
      ),
    );

    // Dropdown panel
    _dropdownEntry = OverlayEntry(
      builder: (context) {
        final screen = MediaQuery.of(context).size;
        const itemHeight = 44.0;
        const vPad = 6.0;
        final contentH =
            (widget.items.length * itemHeight) + vPad * 2;
        final dropH = contentH.clamp(itemHeight, widget.maxHeight);

        // Position below button, flip above if needed
        final spaceBelow = screen.height - buttonRect.bottom - 8;
        final showBelow = spaceBelow >= dropH;
        final top = showBelow
            ? buttonRect.bottom + 4
            : buttonRect.top - dropH - 4;
        final left = buttonRect.left;
        final width = buttonRect.width;

        // Auto-scroll to selected item
        final selIdx = widget.items.indexOf(widget.value);
        final initOffset =
            selIdx > 0 ? ((selIdx - 1) * itemHeight).clamp(0.0, double.infinity) : 0.0;

        return Positioned(
          left: left,
          top: top,
          width: width,
          height: dropH,
          child: FadeTransition(
            opacity: _fadeAnim,
            child: ScaleTransition(
              alignment:
                  showBelow ? Alignment.topLeft : Alignment.bottomLeft,
              scale: _scaleAnim,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                      width: 0.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ListView.builder(
                      controller: ScrollController(
                        initialScrollOffset: initOffset,
                      ),
                      padding:
                          const EdgeInsets.symmetric(vertical: vPad),
                      physics: const BouncingScrollPhysics(),
                      itemCount: widget.items.length,
                      itemExtent: itemHeight,
                      itemBuilder: (context, index) {
                        final item = widget.items[index];
                        final isSelected = item == widget.value;

                        return InkWell(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _close();
                            widget.onChanged(item);
                          },
                          splashColor:
                              AppColors.primary.withValues(alpha: 0.12),
                          highlightColor:
                              AppColors.primary.withValues(alpha: 0.06),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.itemLabelBuilder(item),
                                    style: TextStyle(
                                      color: isSelected
                                          ? AppColors.primary
                                          : Colors.white,
                                      fontSize: 14,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isSelected)
                                  Icon(
                                    Icons.check_rounded,
                                    color: AppColors.primary,
                                    size: 16,
                                  ),
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
        );
      },
    );

    final overlay = Overlay.of(context);
    overlay.insert(_barrierEntry!);
    overlay.insert(_dropdownEntry!);

    _isOpen = true;
    _animController.forward();
  }

  void _close({bool animate = true}) {
    if (!_isOpen) return;
    _isOpen = false;

    if (animate) {
      _animController.reverse().then((_) {
        _removeEntries();
      });
    } else {
      _animController.reset();
      _removeEntries();
    }
  }

  void _removeEntries() {
    _barrierEntry?.remove();
    _barrierEntry?.dispose();
    _barrierEntry = null;
    _dropdownEntry?.remove();
    _dropdownEntry?.dispose();
    _dropdownEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: _buttonKey,
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_isOpen) {
          _close();
        } else {
          _open();
        }
      },
      child: widget.child,
    );
  }
}
