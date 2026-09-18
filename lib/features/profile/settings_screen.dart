// lib/features/profile/settings_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mrbeldi/core/localization/app_locale_service.dart';
import 'package:mrbeldi/core/localization/app_strings.dart';
import 'package:mrbeldi/core/notifications/app_notification_service.dart';
import 'package:mrbeldi/core/theme/app_colors.dart';
import 'package:mrbeldi/routes/app_routes.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notifs = AppNotificationService.isNotificationsEnabled;
  bool _promos = true;

  // ---------------------------------------------------------------------
  // Dialogs
  // ---------------------------------------------------------------------

  void _showProfileInfoDialog(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final w = MediaQuery.of(context).size.width;
    final creation = user?.metadata.creationTime;
    final creationLabel = creation != null
        ? '${creation.day.toString().padLeft(2, '0')}/'
          '${creation.month.toString().padLeft(2, '0')}/'
          '${creation.year}'
        : context.tr('not_available');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              width: w * 0.11,
              height: w * 0.11,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.person_rounded,
                  color: AppColors.primary, size: w * 0.06),
            ),
            SizedBox(width: w * 0.03),
            Expanded(
              child: Text(context.tr('profile_info'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProfileInfoRow(
                label: context.tr('name'),
                value: user?.displayName?.isNotEmpty == true
                    ? user!.displayName!
                    : context.tr('not_provided')),
            _ProfileInfoRow(
                label: context.tr('email'),
                value: user?.email ?? context.tr('not_provided')),
            _ProfileInfoRow(
                label: context.tr('phone'),
                value: user?.phoneNumber ?? context.tr('not_provided')),
            _ProfileInfoRow(
                label: context.tr('account_created'), value: creationLabel),
            _ProfileInfoRow(
                label: context.tr('status'),
                value: (user?.emailVerified ?? false)
                    ? context.tr('verified')
                    : context.tr('not_verified')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('close'),
                style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showLanguageDialog(BuildContext context) {
    final currentCode = AppLocaleService.currentLanguageCode;
    const languages = [
      {'code': 'ar', 'name': 'العربية'},
      {'code': 'fr', 'name': 'Français'},
      {'code': 'en', 'name': 'English'},
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(context.tr('choose_language'),
            style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: languages.map((lang) {
            final code = lang['code']!;
            final name = lang['name']!;
            return RadioListTile<String>(
              value: code,
              groupValue: currentCode,
              activeColor: AppColors.primary,
              title: Text(name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              onChanged: (v) async {
                if (v == null) return;
                Navigator.pop(ctx);
                await AppLocaleService.setLocale(Locale(v));
                if (mounted) setState(() {});
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel'),
                style: TextStyle(
                    color: AppColors.textLight,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color color,
    required String content,
  }) {
    final w = MediaQuery.of(context).size.width;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              width: w * 0.11,
              height: w * 0.11,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: w * 0.06),
            ),
            SizedBox(width: w * 0.03),
            Expanded(
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            content,
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('close'),
                style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        title: Text(
          context.tr('settings_title'),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        elevation: 0,
        leading: const BackButton(color: Colors.white),
      ),
      body: ListView(
        padding: EdgeInsets.all(w * 0.04),
        children: [
          // compte
          _SLabel(context.tr('section_account'), w),
          _SettingTile(
            icon: Icons.badge_rounded,
            label: context.tr('profile_info'),
            color: AppColors.primary,
            w: w,
            onTap: () => _showProfileInfoDialog(context),
          ),
          _SettingTile(
            icon: Icons.email_rounded,
            label: user?.email ?? context.tr('email'),
            color: AppColors.accent,
            w: w,
            subtitle: context.tr('account_connected'),
            onTap: () {},
          ),

          SizedBox(height: w * 0.04),
          _SLabel(context.tr('section_preferences'), w),
          _SettingTile(
            icon: Icons.language_rounded,
            label: context.tr('change_language'),
            color: const Color(0xFF7B61FF),
            w: w,
            subtitle: AppLocaleService.currentLanguageDisplayName,
            onTap: () => _showLanguageDialog(context),
          ),

          SizedBox(height: w * 0.04),
          _SLabel(context.tr('notifications'), w),
          _ToggleTile(
            icon: Icons.notifications_rounded,
            label: context.tr('notifications_push'),
            value: _notifs,
            w: w,
            onChanged: (v) async {
              setState(() => _notifs = v);
              await AppNotificationService.setNotificationsEnabled(v);
            },
          ),
          _ToggleTile(
            icon: Icons.local_offer_rounded,
            label: context.tr('promos'),
            value: _promos,
            w: w,
            onChanged: (v) => setState(() => _promos = v),
          ),

          SizedBox(height: w * 0.04),
          _SLabel(context.tr('section_about'), w),
          _SettingTile(
            icon: Icons.info_rounded,
            label: context.tr('about_mrbeldi'),
            color: AppColors.secondary,
            w: w,
            onTap: () => _showInfoDialog(
              context: context,
              title: context.tr('about_mrbeldi'),
              icon: Icons.info_rounded,
              color: AppColors.secondary,
              content: context.tr('about_content'),
            ),
          ),
          _SettingTile(
            icon: Icons.privacy_tip_rounded,
            label: context.tr('privacy_policy'),
            color: AppColors.textSecondary,
            w: w,
            onTap: () => _showInfoDialog(
              context: context,
              title: context.tr('privacy_policy'),
              icon: Icons.privacy_tip_rounded,
              color: AppColors.textSecondary,
              content: context.tr('privacy_content'),
            ),
          ),
          _SettingTile(
            icon: Icons.description_rounded,
            label: context.tr('terms_of_service'),
            color: AppColors.textSecondary,
            w: w,
            onTap: () => _showInfoDialog(
              context: context,
              title: context.tr('terms_of_service'),
              icon: Icons.description_rounded,
              color: AppColors.textSecondary,
              content: context.tr('terms_content'),
            ),
          ),
          _SettingTile(
            icon: Icons.headset_mic_rounded,
            label: context.tr('support'),
            color: const Color(0xFF1565C0),
            w: w,
            onTap: () => context.push('/support'),
          ),

          // ── Zone sensible (déconnexion + suppression de compte) ────────
          SizedBox(height: w * 0.06),
          _SLabel(context.tr('danger_zone'), w),

          _SettingTile(
            icon: Icons.person_remove_rounded,
            label: context.tr('delete_account'),
            subtitle: context.tr('delete_account_sub'),
            color: AppColors.error,
            w: w,
            onTap: () => context.push(Routes.deleteAccount),
          ),

          SizedBox(height: w * 0.025),

          GestureDetector(
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) context.go('/home');
            },
            child: Container(
              padding: EdgeInsets.symmetric(vertical: w * 0.04),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.logout_rounded,
                      color: AppColors.error, size: 20),
                  SizedBox(width: w * 0.025),
                  Text(
                    context.tr('logout'),
                    style: TextStyle(
                      fontSize: w * 0.038,
                      fontWeight: FontWeight.w700,
                      color: AppColors.error,
                    ),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: w * 0.04),
          Center(
            child: Text(
              context.tr('app_version_tag'),
              style: TextStyle(
                fontSize: w * 0.028,
                color: AppColors.textLight,
              ),
            ),
          ),
          SizedBox(height: w * 0.1),
        ],
      ),
    );
  }
}

class _SLabel extends StatelessWidget {
  final String label;
  final double w;
  const _SLabel(this.label, this.w);

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsetsDirectional.only(bottom: w * 0.02, start: w * 0.01),
        child: Text(
          label,
          style: TextStyle(
            fontSize: w * 0.032,
            fontWeight: FontWeight.w700,
            color: AppColors.textLight,
            letterSpacing: 0.5,
          ),
        ),
      );
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color color;
  final double w;
  final VoidCallback onTap;

  const _SettingTile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.color,
    required this.w,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: EdgeInsets.only(bottom: w * 0.025),
          padding: EdgeInsets.symmetric(
              horizontal: w * 0.04, vertical: w * 0.035),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: w * 0.1,
                height: w * 0.1,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: w * 0.05),
              ),
              SizedBox(width: w * 0.03),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: w * 0.036,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: w * 0.028,
                          color: AppColors.textLight,
                        ),
                      ),
                  ],
                ),
              ),
              Transform.flip(
                flipX: Directionality.of(context) == TextDirection.rtl,
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textLight,
                  size: w * 0.05,
                ),
              ),
            ],
          ),
        ),
      );
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final double w;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.w,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: EdgeInsets.only(bottom: w * 0.025),
        padding: EdgeInsets.symmetric(
            horizontal: w * 0.04, vertical: w * 0.025),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: w * 0.1,
              height: w * 0.1,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.primary, size: w * 0.05),
            ),
            SizedBox(width: w * 0.03),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: w * 0.036,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeTrackColor: AppColors.primary,
            ),
          ],
        ),
      );
}

class _ProfileInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textLight,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
}