import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';

/// A dropdown-style button that opens a scrollable popup anchored directly
/// below (or above) the trigger button.
///
/// Uses a proper [PopupRoute] so the Navigator manages the overlay lifecycle —
/// no orphaned overlays, no race conditions, no duplicate modals.
///
/// Behaviour:
///  • Tap button → open dropdown
///  • Tap button again while open → close dropdown
///  • Tap outside → close dropdown
///  • Swipe/scroll parent → close dropdown (barrier catches it)
///  • After any close, next tap opens a fresh dropdown at the current position
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

class _StickyDropdownModalState<T> extends State<StickyDropdownModal<T>> {
  final GlobalKey _buttonKey = GlobalKey();
  bool _isOpen = false;

  void _toggle() {
    if (_isOpen) {
      // Close the currently open route
      Navigator.of(context, rootNavigator: true).pop();
      // _isOpen will be set to false in the .then() callback below
    } else {
      _openDropdown();
    }
  }

  void _openDropdown() {
    final renderBox =
        _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) return;

    HapticFeedback.selectionClick();

    final buttonSize = renderBox.size;
    final buttonPos = renderBox.localToGlobal(Offset.zero);
    final buttonRect = Rect.fromLTWH(
      buttonPos.dx,
      buttonPos.dy,
      buttonSize.width,
      buttonSize.height,
    );

    setState(() => _isOpen = true);

    Navigator.of(context, rootNavigator: true)
        .push<T>(_DropdownRoute<T>(
      buttonRect: buttonRect,
      items: widget.items,
      value: widget.value,
      itemLabelBuilder: widget.itemLabelBuilder,
      maxHeight: widget.maxHeight,
    ))
        .then((selected) {
      if (mounted) setState(() => _isOpen = false);
      if (selected != null) {
        widget.onChanged(selected);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: _buttonKey,
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      child: widget.child,
    );
  }
}

// ─── Popup Route ─────────────────────────────────────────────────────────────

class _DropdownRoute<T> extends PopupRoute<T> {
  final Rect buttonRect;
  final List<T> items;
  final T value;
  final String Function(T) itemLabelBuilder;
  final double maxHeight;

  _DropdownRoute({
    required this.buttonRect,
    required this.items,
    required this.value,
    required this.itemLabelBuilder,
    required this.maxHeight,
  });

  @override
  Color? get barrierColor => null; // transparent barrier

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss dropdown';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 160);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 120);

  @override
  bool get opaque => false;

  @override
  bool get maintainState => false;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return const SizedBox.shrink(); // content is built in buildTransitions
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final screen = MediaQuery.of(context).size;
    const itemHeight = 44.0;
    const vPad = 6.0;
    final contentH = (items.length * itemHeight) + vPad * 2;
    final dropH = contentH.clamp(itemHeight, maxHeight);

    // Position below button, flip above if needed
    final spaceBelow = screen.height - buttonRect.bottom - 8;
    final showBelow = spaceBelow >= dropH;
    final top =
        showBelow ? buttonRect.bottom + 4 : buttonRect.top - dropH - 4;
    final left = buttonRect.left;
    final width = buttonRect.width;

    // Auto-scroll to selected item
    final selIdx = items.indexOf(value);
    final initOffset =
        selIdx > 0 ? ((selIdx - 1) * itemHeight).clamp(0.0, double.infinity) : 0.0;

    final fadeAnim = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOut,
    );
    final scaleAnim = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
    );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => Navigator.of(context).pop(), // tap outside = dismiss
      onPanStart: (_) => Navigator.of(context).pop(), // swipe = dismiss
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: width,
            height: dropH,
            child: FadeTransition(
              opacity: fadeAnim,
              child: ScaleTransition(
                alignment:
                    showBelow ? Alignment.topLeft : Alignment.bottomLeft,
                scale: scaleAnim,
                child: Material(
                  color: Colors.transparent,
                  child: GestureDetector(
                    // Prevent taps on dropdown items from dismissing
                    onTap: () {},
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
                          itemCount: items.length,
                          itemExtent: itemHeight,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final isSelected = item == value;

                            return InkWell(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                Navigator.of(context).pop(item);
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
                                        itemLabelBuilder(item),
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
            ),
          ),
        ],
      ),
    );
  }
}
