import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class MonthFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const MonthFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myAppColors;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? colors.buttonColor : colors.cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: selected ? colors.buttonColor : colors.borderColor),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : colors.headingTextColor,
          ),
        ),
      ),
    );
  }
}