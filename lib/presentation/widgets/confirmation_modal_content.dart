import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class ConfirmationModalContent extends StatefulWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final bool showDeviceDeleteToggle;
  final void Function(bool alsoDeleteFile) onConfirm;
  final VoidCallback onCancel;

  const ConfirmationModalContent({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.showDeviceDeleteToggle,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<ConfirmationModalContent> createState() => _ConfirmationModalContentState();
}

class _ConfirmationModalContentState extends State<ConfirmationModalContent> {
  bool _alsoDeleteFile = false; // OFF by default as requested

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AppColors.primary, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: widget.onCancel,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            widget.message,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
          if (widget.showDeviceDeleteToggle) ...[
            const SizedBox(height: 16),
            InkWell(
              onTap: () => setState(() => _alsoDeleteFile = !_alsoDeleteFile),
              child: Row(
                children: [
                  Checkbox(
                    value: _alsoDeleteFile,
                    onChanged: (v) => setState(() => _alsoDeleteFile = v ?? false),
                    activeColor: AppColors.primary,
                    side: const BorderSide(color: Colors.white24, width: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  const Text(
                    'Also delete from device storage',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white10),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => widget.onConfirm(_alsoDeleteFile),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(widget.confirmLabel,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
