import 'package:flutter/material.dart';

Future<void> showPlayLoader({
  required BuildContext context,
  required Future<String?> Function() fetchLinkFuture,
  required void Function(String) onSuccess,
  required VoidCallback onError,
}) {
  return showGeneralDialog<void>(
    context: context,
    pageBuilder: (context, animation, secondaryAnimation) {
      return PlayLoaderOverlay(
        fetchLinkFuture: fetchLinkFuture,
        onSuccess: onSuccess,
        onError: onError,
      );
    },
    barrierDismissible: false,
    barrierColor: Colors.transparent, // Let custom panels handle the background
    transitionDuration: const Duration(milliseconds: 50),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

class PlayLoaderOverlay extends StatefulWidget {
  final Future<String?> Function() fetchLinkFuture;
  final void Function(String) onSuccess;
  final VoidCallback onError;

  const PlayLoaderOverlay({
    super.key,
    required this.fetchLinkFuture,
    required this.onSuccess,
    required this.onError,
  });

  @override
  State<PlayLoaderOverlay> createState() => _PlayLoaderOverlayState();
}

class _PlayLoaderOverlayState extends State<PlayLoaderOverlay>
    with TickerProviderStateMixin {
  late AnimationController _barController;
  late AnimationController _panelController;
  late Animation<double> _panelAnimation;
  bool _isCancelled = false;

  @override
  void initState() {
    super.initState();
    _barController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();

    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _panelAnimation = CurvedAnimation(
      parent: _panelController,
      curve: Curves.easeOutQuart,
    );

    // Start by closing the panels
    _panelController.forward();

    _executeFetch();
  }

  Future<void> _executeFetch() async {
    final link = await widget.fetchLinkFuture();
    if (mounted && !_isCancelled) {
      if (link != null && link.isNotEmpty) {
        await _panelController.reverse();
        if (mounted) widget.onSuccess(link);
      } else {
        widget.onError();
        await _panelController.reverse();
        if (mounted) Navigator.of(context).pop();
      }
    }
  }

  @override
  void dispose() {
    _barController.dispose();
    _panelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        _isCancelled = true;
        // Play the exit animation (panels opening)
        final navigator = Navigator.of(context);
        await _panelController.reverse();
        if (mounted) navigator.pop();
      },
      child: AnimatedBuilder(
        animation: _panelAnimation,
        builder: (context, child) {
          return Stack(
            children: [
              // Top Panel
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: MediaQuery.of(context).size.height / 2,
                child: FractionalTranslation(
                  translation: Offset(0, -1 + _panelAnimation.value),
                  child: Container(color: const Color(0xFF1C2020)),
                ),
              ),
              // Bottom Panel
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: MediaQuery.of(context).size.height / 2,
                child: FractionalTranslation(
                  translation: Offset(0, 1 - _panelAnimation.value),
                  child: Container(color: const Color(0xFF1C2020)),
                ),
              ),
              // Loader Bars
              if (_panelAnimation.value > 0.8)
                Center(
                  child: Opacity(
                    opacity: (_panelAnimation.value - 0.8) * 5,
                    child: SizedBox(
                      width: 60,
                      height: 50,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(6, (index) {
                          return _BarItem(
                            index: index,
                            controller: _barController,
                            color: _getBarColor(index),
                          );
                        }),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Color _getBarColor(int index) {
    switch (index) {
      case 0:
        return const Color(0xFF754FA0);
      case 1:
        return const Color(0xFF09B7BF);
      case 2:
        return const Color(0xFF90D36B);
      case 3:
        return const Color(0xFFF2D40D);
      case 4:
        return const Color(0xFFFCB12B);
      case 5:
        return const Color(0xFFED1B72);
      default:
        return Colors.white;
    }
  }
}

class _BarItem extends StatelessWidget {
  final int index;
  final AnimationController controller;
  final Color color;

  const _BarItem({
    required this.index,
    required this.controller,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    // Delays match the CSS animation-delay
    // bar1: 0s, bar2: -0.7s, bar3: -0.6s, etc.
    // In Flutter, we use an interval or shift the value.
    final delays = [0.0, 0.7, 0.6, 0.5, 0.4, 0.3];
    final delay = delays[index];

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        // Calculate shifted value for delay
        double t = (controller.value + (1.0 - delay)) % 1.0;

        // CSS keyframe: 0%, 40%, 100% { scaleY(0.05) } 20% { scaleY(1.0) }
        double scale;
        if (t < 0.2) {
          scale = 0.05 + (0.95 * (t / 0.2));
        } else if (t < 0.4) {
          scale = 1.0 - (0.95 * ((t - 0.2) / 0.2));
        } else {
          scale = 0.05;
        }

        return Transform.scale(
          scaleY: scale,
          child: Container(
            width: 8,
            height: 50,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      },
    );
  }
}
