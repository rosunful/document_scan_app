import 'package:flutter/material.dart';
import '../../model/tool_model.dart';
import '../../theme/app_theme.dart';

class ToolCard extends StatelessWidget {
  final ToolItem tool;
  final VoidCallback? onTap;

  const ToolCard({super.key, required this.tool, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.myAppColors;

    return Material(
      color: colors.cardColor,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: tool.iconBackground,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(tool.icon, color: tool.iconColor, size: 22),
                  ),
                  Icon(Icons.chevron_right_rounded, color: colors.descriptionColor),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                tool.title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: colors.headingTextColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                tool.subtitle,
                style: TextStyle(fontSize: 12.5, color: colors.descriptionColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}