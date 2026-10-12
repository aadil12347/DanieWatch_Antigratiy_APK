import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import 'package:daniewatch_app/core/utils/toast_utils.dart';

class EarnMoneyScreen extends StatelessWidget {
  const EarnMoneyScreen({super.key});

  static const String _emailAddress = 'mdaniyalaadil@gmail.com';
  static const String _channelUrl = 'https://whatsapp.com/channel/0029VbDU6Fu84OmBWJDC1Q1J';

  Future<void> _openWhatsAppChannel(BuildContext context) async {
    final uri = Uri.parse(_channelUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        CustomToast.show(
          context,
          'Link copied to clipboard!',
          type: ToastType.info,
        );
        Clipboard.setData(const ClipboardData(text: _channelUrl));
      }
    }
  }

  Future<void> _openEmail(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: _emailAddress,
      queryParameters: {
        'subject': 'TikTok GIP Masterclass - Reserve Slot',
        'body': 'Hi Danie,\n\nI want to reserve my slot for the TikTok GIP Masterclass.\n\nMy Details:\n• Name: \n• Country: \n• Preferred Payment Method: \n\nLooking forward to your reply!',
      },
    );

    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        final webmail = Uri.parse(
          'https://mail.google.com/mail/?view=cm&fs=1&to=$_emailAddress&su=TikTok+GIP+Masterclass',
        );
        await launchUrl(webmail, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      try {
        final webmail = Uri.parse(
          'https://mail.google.com/mail/?view=cm&fs=1&to=$_emailAddress&su=TikTok+GIP+Masterclass',
        );
        await launchUrl(webmail, mode: LaunchMode.externalApplication);
      } catch (e) {
        if (context.mounted) {
          CustomToast.show(
            context,
            'Email copied to clipboard!',
            type: ToastType.info,
          );
          Clipboard.setData(const ClipboardData(text: _emailAddress));
        }
      }
    }
  }

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    CustomToast.show(
      context,
      '$label copied to clipboard!',
      type: ToastType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background.withValues(alpha: 0.95),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Text(
              'Earn Money',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: AppColors.textPrimary,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'TIKTOK GIP',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: AppColors.background,
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: () => _openWhatsAppChannel(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 4,
              shadowColor: const Color(0xFF25D366).withValues(alpha: 0.4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.campaign_rounded, size: 22),
                const SizedBox(width: 10),
                Text(
                  'Contact Us on WhatsApp Channel',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward_rounded, size: 18),
              ],
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero card with glowing border
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF10B981).withValues(alpha: 0.15),
                    const Color(0xFF1E1E1E),
                    const Color(0xFF141413),
                  ],
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.35),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    blurRadius: 24,
                    spreadRadius: -4,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Exclusive Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.4),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.local_fire_department_rounded,
                          size: 14,
                          color: Color(0xFF34D399),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'HIDDEN MONETIZATION PROGRAM',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF34D399),
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Main Headline
                  Text(
                    'Stop just scrolling on TikTok — get paid for it. 🚀',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.3,
                      letterSpacing: -0.4,
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Paragraph
                  Text(
                    'TikTok is quietly paying people through a hidden program called GIP, and 95% of users don\'t even know it exists. Turn 10 minutes of daily screen time into dollar earnings with the TikTok GIP program. No face, no expensive PC, no massive follower count needed. Master the TikTok Gaming Incentive Program and start monetizing simple gaming tasks.',
                    style: GoogleFonts.inter(
                      fontSize: 14.5,
                      color: const Color(0xFFD4D4D8),
                      height: 1.6,
                      fontWeight: FontWeight.w400,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Advantage Chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildChip(Icons.face_retouching_off_rounded, 'No Face Needed'),
                      _buildChip(Icons.computer_rounded, 'No PC Required'),
                      _buildChip(Icons.group_off_rounded, 'Zero Followers'),
                      _buildChip(Icons.timer_outlined, '10 Mins / Day'),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Exact blueprint callout card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF27272A),
                    Color(0xFF1E1E1E),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Color(0xFF34D399),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'You just need the exact blueprint to set it up, get approved, and start earning.',
                      style: GoogleFonts.inter(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        height: 1.45,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Masterclass steps header
            Text(
              'I’ve put together a step-by-step masterclass showing you:',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),

            const SizedBox(height: 12),

            // 3 Steps
            _buildCurriculumTile(
              index: '01',
              icon: Icons.public_rounded,
              color: const Color(0xFF6366F1),
              title: 'Global Dashboard Access',
              description: 'How to unlock and navigate the TikTok GIP dashboard from anywhere.',
            ),
            _buildCurriculumTile(
              index: '02',
              icon: Icons.sports_esports_rounded,
              color: const Color(0xFFEC4899),
              title: 'Task Completion & Rewards',
              description: 'The exact methods to complete tasks and claim cash rewards.',
            ),
            _buildCurriculumTile(
              index: '03',
              icon: Icons.payments_rounded,
              color: const Color(0xFF10B981),
              title: 'Smooth Cashout System',
              description: 'How to receive your payouts smoothly, step by step.',
            ),

            const SizedBox(height: 24),

            // Course Access Fee Section
            Text(
              'Course Access Fee:',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'One-time payment • Lifetime blueprint & mentorship access',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),

            const SizedBox(height: 14),

            // Pricing Cards
            Row(
              children: [
                Expanded(
                  child: _buildPricingCard(
                    flag: '🇵🇰',
                    country: 'Pakistan',
                    price: '2,500 PKR',
                    accentColor: const Color(0xFF10B981),
                    paymentOptions: 'EasyPaisa · JazzCash · Bank',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildPricingCard(
                    flag: '🌍',
                    country: 'International',
                    price: '\$10 USD',
                    accentColor: const Color(0xFF38BDF8),
                    paymentOptions: 'Binance · USDT · Wise',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Limited Spots Notice
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFF59E0B).withValues(alpha: 0.16),
                    const Color(0xFFF59E0B).withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  const Text('⚡', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Spots are limited for the upcoming batch. Send a direct message now to reserve your slot:',
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFFDE68A),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Interactive Contact Section (Email & WhatsApp Channel only)
            _buildContactTile(
              context: context,
              icon: Icons.mail_rounded,
              iconColor: const Color(0xFFEA4335),
              title: 'Email',
              value: _emailAddress,
              subtext: 'Tap to send an email / Gmail',
              onTap: () => _openEmail(context),
              onCopy: () => _copyToClipboard(context, _emailAddress, 'Email address'),
            ),

            const SizedBox(height: 12),

            _buildContactTile(
              context: context,
              icon: Icons.campaign_rounded,
              iconColor: const Color(0xFF25D366),
              title: 'WhatsApp Channel',
              value: 'Join Official Channel',
              subtext: 'Tap to join community & reserve slot',
              onTap: () => _openWhatsAppChannel(context),
              onCopy: () => _copyToClipboard(context, _channelUrl, 'Channel link'),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF34D399)),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurriculumTile({
    required String index,
    required IconData icon,
    required Color color,
    required String title,
    required String description,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: 0.25),
                  color.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFFA1A1AA),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPricingCard({
    required String flag,
    required String country,
    required String price,
    required Color accentColor,
    required String paymentOptions,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.3),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(flag, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  country,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            price,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: accentColor,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            paymentOptions,
            style: GoogleFonts.inter(
              fontSize: 10.5,
              color: AppColors.textMuted,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactTile({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String subtext,
    required VoidCallback onTap,
    required VoidCallback onCopy,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: iconColor.withValues(alpha: 0.1),
        highlightColor: iconColor.withValues(alpha: 0.05),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: iconColor.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtext,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: iconColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 18, color: Colors.white60),
                tooltip: 'Copy',
                onPressed: onCopy,
                visualDensity: VisualDensity.compact,
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Colors.white38,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
