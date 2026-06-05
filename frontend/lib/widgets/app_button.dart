import 'package:flutter/material.dart';
import '../core/theme.dart';

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final bool isSecondary;
  final double? width;
  final EdgeInsets? padding;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.isSecondary = false,
    this.width,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final isBtnDisabled = onPressed == null || isLoading;

    final Widget content = isLoading
        ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20),
                const SizedBox(width: 8),
              ],
              Text(label),
            ],
          );

    final Widget button = isSecondary
        ? OutlinedButton(
            onPressed: isBtnDisabled ? null : onPressed,
            style: OutlinedButton.styleFrom(
              padding: padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
            child: content,
          )
        : ElevatedButton(
            onPressed: isBtnDisabled ? null : onPressed,
            style: ElevatedButton.styleFrom(
              padding: padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              backgroundColor: isBtnDisabled ? Colors.grey : AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: content,
          );

    if (width != null) {
      return SizedBox(width: width, child: button);
    }
    return button;
  }
}
