import 'package:flutter/material.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';

class ShutterTransition extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  final bool isOpening; // True: 1.0 -> 0.0 (panels split), False: 0.0 -> 1.0 (panels meet)

  const ShutterTransition({
    super.key,
    required this.animation,
    required this.child,
    this.isOpening = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // The background/underlying content
        child,
        
        // The Shutter Panels
        AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            // value 0.0 = fully open, value 1.0 = fully closed (meeting in center)
            final value = isOpening ? (1.0 - animation.value) : animation.value;
            
            if (value <= 0) return const SizedBox.shrink();

            return Stack(
              children: [
                // Top Panel
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: MediaQuery.of(context).size.height / 2,
                  child: FractionalTranslation(
                    translation: Offset(0, -1 + value),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        boxShadow: [
                          if (value < 1.0)
                            BoxShadow(
                              color: Colors.black.withOpacity(0.5),
                              blurRadius: 20,
                              offset: const Offset(0, 5),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Bottom Panel
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: MediaQuery.of(context).size.height / 2,
                  child: FractionalTranslation(
                    translation: Offset(0, 1 - value),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        boxShadow: [
                          if (value < 1.0)
                            BoxShadow(
                              color: Colors.black.withOpacity(0.5),
                              blurRadius: 20,
                              offset: const Offset(0, -5),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
