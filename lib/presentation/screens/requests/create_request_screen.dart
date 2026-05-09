import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/toast_utils.dart';
import '../../providers/support_provider.dart';

class CreateRequestScreen extends ConsumerStatefulWidget {
  const CreateRequestScreen({super.key});

  @override
  ConsumerState<CreateRequestScreen> createState() => _CreateRequestScreenState();
}

class _CreateRequestScreenState extends ConsumerState<CreateRequestScreen> {
  final _messageController = TextEditingController();
  String _selectedCategory = 'add_movie_series'; // Default category
  bool _isSubmitting = false;

  static const _categories = [
    {'value': 'add_movie_series', 'label': 'Add Movie or Series', 'icon': Icons.movie_filter_rounded, 'color': Color(0xFF7C3AED)},
    {'value': 'bug_report', 'label': 'Bug Report', 'icon': Icons.bug_report_rounded, 'color': Color(0xFFEF4444)},
    {'value': 'feature_request', 'label': 'Feature Request', 'icon': Icons.lightbulb_rounded, 'color': Color(0xFFF59E0B)},
    {'value': 'other', 'label': 'Other', 'icon': Icons.chat_bubble_rounded, 'color': Color(0xFF6B7280)},
  ];

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Validate message
    if (_messageController.text.trim().isEmpty) {
      CustomToast.show(context, 'Please enter a message', type: ToastType.error);
      return;
    }

    setState(() => _isSubmitting = true);

    final message = _messageController.text.trim();
    // Use first line or first 80 chars as subject
    final firstLine = message.contains('\n') ? message.split('\n').first : message;
    final subject = firstLine.length > 80 ? '${firstLine.substring(0, 80)}...' : firstLine;

    final service = ref.read(supportServiceProvider);
    final ticket = await service.createTicket(
      subject: subject,
      description: message,
      category: _selectedCategory,
    );

    if (!mounted) return;

    if (ticket != null) {
      CustomToast.show(context, 'Request submitted!', type: ToastType.success);
      context.push('/requests/chat/${ticket.id}');
    } else {
      setState(() => _isSubmitting = false);
      CustomToast.show(context, 'Failed to submit request', type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/requests');
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/requests');
              }
            },
          ),
          title: Text(
            'New Request',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),

            // ── Category Selection ─────────────────────────────────
            _buildLabel('Category', required: true),
            const SizedBox(height: 10),
            _buildCategorySelector(),
            const SizedBox(height: 24),

            // ── Message ────────────────────────────────────────────
            _buildLabel('Message', required: true),
            const SizedBox(height: 10),
            _buildTextField(
              controller: _messageController,
              hint: _getHintForCategory(_selectedCategory),
              maxLines: 6,
            ),
            const SizedBox(height: 32),

            // ── Submit Button ──────────────────────────────────────
            _buildSubmitButton(),
            const SizedBox(height: 40),
          ],
        ),
      ),
      ),
    );
  }

  String _getHintForCategory(String category) {
    switch (category) {
      case 'add_movie_series':
        return 'e.g. Please add "The Dark Knight" or "Breaking Bad Season 5"';
      case 'bug_report':
        return 'Describe the bug you encountered...';
      case 'feature_request':
        return 'Describe the feature you\'d like to see...';
      default:
        return 'Describe your request in detail...';
    }
  }

  Widget _buildLabel(String text, {bool required = false}) {
    return Row(
      children: [
        Text(
          text,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
        if (required)
          Text(
            ' *',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.error,
            ),
          ),
      ],
    );
  }

  Widget _buildCategorySelector() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.04),
          width: 1,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: ButtonTheme(
          alignedDropdown: true,
          child: DropdownButton<String>(
            value: _selectedCategory,
            isExpanded: true,
            dropdownColor: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppColors.textSecondary,
            ),
            items: _categories.map((cat) {
              final color = cat['color'] as Color;
              return DropdownMenuItem<String>(
                value: cat['value'] as String,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        cat['icon'] as IconData,
                        size: 16,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      cat['label'] as String,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedCategory = value;
                });
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: GoogleFonts.inter(
          fontSize: 14,
          color: AppColors.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.inter(
            fontSize: 14,
            color: AppColors.textHint,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return GestureDetector(
      onTap: _isSubmitting ? null : _submit,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _isSubmitting
                ? [AppColors.textMuted, AppColors.textHint]
                : [const Color(0xFF059669), const Color(0xFF047857)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: _isSubmitting
              ? []
              : [
                  BoxShadow(
                    color: const Color(0xFF059669).withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Center(
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Submit Request',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
