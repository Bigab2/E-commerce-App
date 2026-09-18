// TODO Implement this library.// lib/core/theme/app_colors.dart

import 'package:flutter/material.dart';

class AppColors {
  // Primary - أخضر عضوي رئيسي
  static const Color primary = Color(0xFF2E8B57);        // Sea Green
  static const Color primaryLight = Color(0xFF4CAF7A);
  static const Color primaryDark = Color(0xFF1F5F3E);

  // Secondary
  static const Color secondary = Color(0xFF66B88E);
  static const Color accent = Color(0xFFFFA726);         // برتقالي دافئ للعروض

  // Neutral
  static const Color background = Color(0xFFF8F9FA);
  static const Color surface = Colors.white;
  static const Color card = Colors.white;

  // Text
  static const Color textPrimary = Color(0xFF1F2C25);
  static const Color textSecondary = Color(0xFF4A5F53);
  static const Color textLight = Color(0xFF8A9A92);

  // Status
  static const Color success = Color(0xFF2E8B57);
  static const Color warning = Color(0xFFFFA726);
  static const Color error = Color(0xFFE53935);

  // Border & Shadow
  static const Color border = Color(0xFFE0E7E0);
  static const Color shadow = Color(0x1F000000); // مع شفافية
}