import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../provider/theme_provider.dart';
import '../theme/app_theme.dart';

class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback? onAvatarTap;
  final ValueChanged<String>? onSearchChanged;

  const AppTopBar({super.key, this.onAvatarTap, this.onSearchChanged});

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    // Passing the theme value to the theme-changer button.
    final themeNotifier = context.watch<ThemeProvider>();
    final colors = context.myAppColors;
    final isLight = themeNotifier.themeMode == ThemeMode.light;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: onAvatarTap,
          child: CircleAvatar(
            radius: 18,
            backgroundColor: colors.descriptionColor.withValues(alpha: 0.15),
            child: Icon(Icons.person_rounded, color: colors.descriptionColor, size: 26),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: colors.searchbarColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: colors.borderColor),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: colors.descriptionColor, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    onChanged: onSearchChanged,
                    style: TextStyle(color: colors.headingTextColor, fontSize: 15),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Search documents...',
                      hintStyle: TextStyle(color: colors.descriptionColor, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          height: 38,
          width: 38,
          decoration: BoxDecoration(
            color: colors.backgroundColor,
            shape: BoxShape.circle,
            border: Border.all(color: colors.borderColor , width: 0.4),
          ),
          child: Center(
            child: IconButton(
              onPressed: () => themeNotifier.toggle(),
              icon: Icon(isLight ?  
              Icons.dark_mode_rounded :  
              Icons.light_mode_sharp,
                color: colors.descriptionColor,
                size: 22,
              ),
            ),
          ),
        ),
      ],
    );
  }
}