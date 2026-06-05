import 'package:flutter/material.dart';

enum StatusType {
  active,
  expired,
  paid,
  pending,
}

class StatusChip extends StatelessWidget {
  final StatusType type;

  const StatusChip({
    super.key,
    required this.type,
  });

  String get _label {
    switch (type) {
      case StatusType.active:
        return 'ACTIVE';
      case StatusType.expired:
        return 'EXPIRED';
      case StatusType.paid:
        return 'SETTLED';
      case StatusType.pending:
        return 'PENDING';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Color backgroundColor;
    Color textColor;
    Color borderColor;

    switch (type) {
      case StatusType.active:
      case StatusType.paid:
        // Success green scheme
        backgroundColor = isDark ? Colors.green.withAlpha(40) : const Color(0xFFF0FDF4);
        textColor = isDark ? Colors.greenAccent : const Color(0xFF16A34A);
        borderColor = isDark ? Colors.green.withAlpha(80) : const Color(0xFFBBF7D0);
        break;
      case StatusType.expired:
        // Alert red scheme
        backgroundColor = isDark ? Colors.red.withAlpha(40) : const Color(0xFFFEF2F2);
        textColor = isDark ? Colors.redAccent : const Color(0xFFDC2626);
        borderColor = isDark ? Colors.red.withAlpha(80) : const Color(0xFFFECACA);
        break;
      case StatusType.pending:
        // Warning orange/amber scheme
        backgroundColor = isDark ? Colors.amber.withAlpha(40) : const Color(0xFFFFFBEB);
        textColor = isDark ? Colors.amber.shade700 : const Color(0xFFD97706);
        borderColor = isDark ? Colors.amber.withAlpha(80) : const Color(0xFFFDE68A);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Text(
        _label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: textColor,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
