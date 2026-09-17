import 'package:flutter/material.dart';

/// One of the quick-action cards on the Home screen (Scan, Image to PDF, etc.)
class ToolItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconBackground;
  final Color iconColor;

  const ToolItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconBackground,
    required this.iconColor,
  });
}