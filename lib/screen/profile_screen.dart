import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Static profile screen. The user card (picture, name, email) and the
/// account options below are placeholders — they'll be wired to real
/// auth/profile data later, as will the Logout / About / Privacy / Report
/// actions.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  void _comingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature is coming soon')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myAppColors;

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      appBar: AppBar(
        backgroundColor: colors.backgroundColor,
        foregroundColor: colors.headingTextColor,
        elevation: 0,
        title: const Text('Profile'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _buildProfileCard(colors),
          const SizedBox(height: 24),
          Text(
            'Account',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colors.headingTextColor,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: colors.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.borderColor),
            ),
            child: Column(
              children: [
                _ProfileOption(
                  icon: Icons.logout_rounded,
                  iconColor: colors.buttonColor,
                  label: 'Logout',
                  onTap: () => _comingSoon(context, 'Logout'),
                ),
                Divider(height: 1, thickness: 1, color: colors.borderColor),
                _ProfileOption(
                  icon: Icons.info_outline_rounded,
                  iconColor: colors.buttonColor,
                  label: 'About Us',
                  onTap: () => _comingSoon(context, 'About Us'),
                ),
                Divider(height: 1, thickness: 1, color: colors.borderColor),
                _ProfileOption(
                  icon: Icons.privacy_tip_outlined,
                  iconColor: colors.buttonColor,
                  label: 'Privacy Policy',
                  onTap: () => _comingSoon(context, 'Privacy Policy'),
                ),
                Divider(height: 1, thickness: 1, color: colors.borderColor),
                _ProfileOption(
                  icon: Icons.flag_outlined,
                  iconColor: colors.buttonColor,
                  label: 'Report a Problem',
                  onTap: () => _comingSoon(context, 'Report a Problem'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard(CustomAppColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: colors.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.borderColor),
      ),
      child: Column(
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors.buttonColor.withValues(alpha: 0.85),
                  colors.buttonColor,
                ],
              ),
            ),
            child: Icon(
              Icons.person_rounded,
              size: 48,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'John Doe', // static placeholder — wire to real account data later
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: colors.headingTextColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'john.doe@example.com', // static placeholder
            style: TextStyle(fontSize: 13.5, color: colors.descriptionColor),
          ),
        ],
      ),
    );
  }
}

class _ProfileOption extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  const _ProfileOption({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myAppColors;

    return ListTile(
      leading: Icon(icon, color: iconColor, size: 22),
      title: Text(
        label,
        style: TextStyle(fontSize: 14.5, color: colors.headingTextColor),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: colors.descriptionColor,
      ),
      onTap: onTap,
    );
  }
}