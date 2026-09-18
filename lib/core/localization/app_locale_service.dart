import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLocaleService {
  static const String _prefKey = 'app_language_code';
  static const String _userSelectedKey = 'app_user_selected_language';

  static const List<Locale> supportedLocales = [
    Locale('ar'),
    Locale('fr'),
    Locale('en'),
  ];

  static bool _hasUserSelected = false;
  static bool get hasUserSelected => _hasUserSelected;

  static final ValueNotifier<Locale> localeNotifier =
      ValueNotifier<Locale>(detectDeviceLocale());

  static Locale get currentLocale => localeNotifier.value;
  static String get currentLanguageCode => localeNotifier.value.languageCode;
  static bool get isRtl => currentLanguageCode == 'ar';

  /// Détection de la langue de l'appareil parmi les langues supportées (ar, fr, en)
  static Locale detectDeviceLocale() {
    try {
      final dispatcher = PlatformDispatcher.instance;

      // 1. Parcourir les langues préférées de l'appareil dans l'ordre de priorité
      for (final locale in dispatcher.locales) {
        final code = locale.languageCode.toLowerCase();
        if (code.startsWith('ar')) return const Locale('ar');
        if (code.startsWith('fr')) return const Locale('fr');
        if (code.startsWith('en')) return const Locale('en');
      }

      // 2. Vérifier la langue principale si disponible
      final primaryCode = dispatcher.locale.languageCode.toLowerCase();
      if (primaryCode.startsWith('ar')) return const Locale('ar');
      if (primaryCode.startsWith('fr')) return const Locale('fr');
      if (primaryCode.startsWith('en')) return const Locale('en');
    } catch (e) {
      debugPrint('Error detecting device locale: $e');
    }

    // Par défaut (ar) pour le public marocain
    return const Locale('ar');
  }

  /// Initialisation au lancement de l'application
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userSelected = prefs.getString(_userSelectedKey);

      // Si l'utilisateur a déjà choisi une langue manuellement dans les paramètres
      if (userSelected != null &&
          supportedLocales.any((l) => l.languageCode == userSelected)) {
        _hasUserSelected = true;
        localeNotifier.value = Locale(userSelected);
        return;
      }

      // Première ouverture ou aucun choix manuel :
      // Utilisation automatique de la langue de l'appareil
      _hasUserSelected = false;
      final initialLocale = detectDeviceLocale();
      localeNotifier.value = initialLocale;

      // Écouter les changements de langue du système si aucun choix manuel n'a été fait
      PlatformDispatcher.instance.onLocaleChanged = () {
        if (!_hasUserSelected) {
          final newDeviceLocale = detectDeviceLocale();
          if (localeNotifier.value.languageCode != newDeviceLocale.languageCode) {
            localeNotifier.value = newDeviceLocale;
          }
        }
      };
    } catch (e) {
      debugPrint('Error initializing AppLocaleService: $e');
    }
  }

  /// Changer de langue manuellement et sauvegarder dans SharedPreferences
  static Future<void> setLocale(Locale newLocale) async {
    if (!supportedLocales.any((l) => l.languageCode == newLocale.languageCode)) {
      return;
    }
    _hasUserSelected = true;
    localeNotifier.value = newLocale;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userSelectedKey, newLocale.languageCode);
      await prefs.setString(_prefKey, newLocale.languageCode);
    } catch (e) {
      debugPrint('Error saving locale: $e');
    }
  }

  /// Réinitialiser pour suivre automatiquement la langue de l'appareil
  static Future<void> resetToDeviceLocale() async {
    _hasUserSelected = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userSelectedKey);
      await prefs.remove(_prefKey);
    } catch (e) {
      debugPrint('Error resetting locale: $e');
    }
    localeNotifier.value = detectDeviceLocale();
  }

  static String get currentLanguageDisplayName =>
      displayNameFromCode(currentLanguageCode);

  static String displayNameFromCode(String code) {
    switch (code) {
      case 'ar':
        return 'العربية';
      case 'fr':
        return 'Français';
      case 'en':
        return 'English';
      default:
        return 'العربية';
    }
  }

  static Locale localeFromDisplayName(String name) {
    switch (name) {
      case 'العربية':
        return const Locale('ar');
      case 'Français':
        return const Locale('fr');
      case 'English':
        return const Locale('en');
      default:
        return const Locale('ar');
    }
  }
}
