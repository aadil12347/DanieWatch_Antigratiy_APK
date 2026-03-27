import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';

class EmptyResultsView extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;

  const EmptyResultsView({
    super.key,
    this.title = 'No Results Found',
    this.message = 'Try adjusting your filters or search keywords to find what you\'re looking for.',
    this.icon = Icons.search_off_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Subtle Premium Icon
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 64,
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(height: 32),
            
            // Beautifully Styled Heading
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: AppColors.primary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 12),
            
            // Short matching sub-message
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 14,
                height: 1.6,
                letterSpacing: 0.1,
              ),
            ),
            
            // Minimalist Red Accent Dash
            const SizedBox(height: 32),
            Container(
              width: 24,
              height: 2,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
