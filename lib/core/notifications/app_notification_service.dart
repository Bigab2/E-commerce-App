// lib/core/notifications/app_notification_service.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mrbeldi/core/localization/app_locale_service.dart';
import 'package:mrbeldi/core/navigation/app_navigator.dart';
import 'package:mrbeldi/core/services/local_cart_service.dart';
import 'package:mrbeldi/core/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_banner.dart';

class AppNotificationService {
  static const String _prefNotificationsEnabled = 'notifications_push_enabled';
  static const String _prefCartLastInteraction = 'cart_last_interaction_timestamp';
  static const String _prefCartReminderSent = 'cart_reminder_sent';
  static const String _prefSeenNotificationIds = 'seen_firestore_notifications_ids';

  static final ValueNotifier<bool> notificationsEnabledNotifier =
      ValueNotifier<bool>(true);

  static bool get isNotificationsEnabled => notificationsEnabledNotifier.value;

  static OverlayEntry? _activeBannerEntry;
  static StreamSubscription<QuerySnapshot>? _firestoreNotificationsSub;
  static bool _initialized = false;

  /// Initialisation du service au démarrage de l'application
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      // Par défaut : actif (true)
      final enabled = prefs.getBool(_prefNotificationsEnabled) ?? true;
      notificationsEnabledNotifier.value = enabled;

      // Démarrer l'écoute de la collection Firestore "Notifications"
      _startFirestoreNotificationsListener();

      // Vérifier le rappel de panier après un court délai (10 secondes après ouverture)
      Timer(const Duration(seconds: 10), () {
        checkCartAbandonment();
      });
    } catch (e) {
      debugPrint('AppNotificationService.init error: $e');
    }
  }

  /// Activer ou désactiver les notifications (depuis SettingsScreen)
  static Future<void> setNotificationsEnabled(bool enabled) async {
    notificationsEnabledNotifier.value = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefNotificationsEnabled, enabled);
    } catch (e) {
      debugPrint('Error saving notificationsEnabled: $e');
    }
  }

  /// Enregistrer une interaction avec le panier (ajout, retrait, consultation)
  static Future<void> recordCartInteraction() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(_prefCartLastInteraction, now);
      // Réinitialise le flag d'envoi pour que le rappel puisse se redéclencher
      // si le panier reste à nouveau abandonné pendant 3 jours
      await prefs.setBool(_prefCartReminderSent, false);
    } catch (e) {
      debugPrint('Error recording cart interaction: $e');
    }
  }

  /// Vérification de l'abandon de panier (3 jours sans retour)
  static Future<void> checkCartAbandonment() async {
    if (!isNotificationsEnabled) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadySent = prefs.getBool(_prefCartReminderSent) ?? false;
      if (alreadySent) return; // Notification envoyée une seule fois !

      // 1. Vérifier si le panier contient des articles
      bool hasItems = false;
      final uid = FirebaseAuth.instance.currentUser?.uid;

      if (uid != null) {
        final cartSnap = await FirebaseFirestore.instance
            .collection('carts')
            .doc(uid)
            .collection('items')
            .limit(1)
            .get();
        hasItems = cartSnap.docs.isNotEmpty;
      } else {
        final localItems = await LocalCartService.getItems();
        hasItems = localItems.isNotEmpty;
      }

      if (!hasItems) {
        // Panier vide : réinitialiser
        await prefs.setBool(_prefCartReminderSent, false);
        return;
      }

      // 2. Vérifier la date de dernière interaction
      final now = DateTime.now();
      final lastInteractionMs = prefs.getInt(_prefCartLastInteraction);

      if (lastInteractionMs == null) {
        // Première fois qu'on détecte un panier rempli : initialiser l'horodatage
        await prefs.setInt(_prefCartLastInteraction, now.millisecondsSinceEpoch);
        return;
      }

      final lastInteraction =
          DateTime.fromMillisecondsSinceEpoch(lastInteractionMs);
      final diff = now.difference(lastInteraction);

      // Si le panier est abandonné depuis 3 jours (72 heures)
      if (diff.inDays >= 3) {
        final lang = AppLocaleService.detectDeviceLocale().languageCode;
        String title;
        String body;

        if (lang == 'ar') {
          title = 'سلتك في انتظارك! 🛒';
          body = 'لديك منتجات بانتظارك في السلة، أكمل طلبك الآن قبل نفاد الكمية.';
        } else if (lang == 'fr') {
          title = 'Votre panier vous attend ! 🛒';
          body = 'Vous avez des articles dans votre panier. Finalisez votre commande avant rupture de stock.';
        } else {
          title = 'Your cart is waiting! 🛒';
          body = 'You have items in your cart. Complete your order now before they run out.';
        }

        showNotification(
          title: title,
          message: body,
          icon: Icons.shopping_basket_rounded,
          iconColor: AppColors.accent,
          onTap: () {
            final nav = appNavigatorKey.currentState;
            nav?.pushNamed('/cart');
          },
        );

        // Marquer comme envoyé pour ne plus jamais renvoyer pour ce cycle
        await prefs.setBool(_prefCartReminderSent, true);
      }
    } catch (e) {
      debugPrint('Error checking cart abandonment: $e');
    }
  }

  /// Écouteur en temps réel de la collection "Notifications"
  static void _startFirestoreNotificationsListener() {
    _firestoreNotificationsSub?.cancel();

    // On écoute les documents de la collection "Notifications"
    _firestoreNotificationsSub = FirebaseFirestore.instance
        .collection('Notifications')
        .snapshots()
        .listen((snapshot) async {
      if (!isNotificationsEnabled) return;

      try {
        final prefs = await SharedPreferences.getInstance();
        final seenIds =
            prefs.getStringList(_prefSeenNotificationIds)?.toSet() ?? {};

        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final doc = change.doc;
            final docId = doc.id;

            if (seenIds.contains(docId)) continue;

            final data = doc.data();
            if (data == null) continue;

            final note = data['note'] as String?;
            if (note == null || note.trim().isEmpty) continue;

            // Marquer comme vu immédiatement pour ne pas répéter
            seenIds.add(docId);
            await prefs.setStringList(
                _prefSeenNotificationIds, seenIds.toList());

            // Titre selon la langue de l'appareil
            final lang = AppLocaleService.detectDeviceLocale().languageCode;
            String title;
            if (lang == 'ar') {
              title = 'لا تفوت هذا العرض المذهل';
            } else if (lang == 'fr') {
              title = 'Ne manquez pas cette offre incroyable !';
            } else {
              title = "Don't miss this amazing offer!";
            }

            showNotification(
              title: title,
              message: note.trim(),
              icon: Icons.local_offer_rounded,
              iconColor: AppColors.primary,
            );

            // On n'affiche qu'une notification à la fois
            break;
          }
        }
      } catch (e) {
        debugPrint('Error handling Firestore Notifications snapshot: $e');
      }
    }, onError: (e) {
      debugPrint('Firestore Notifications listener error: $e');
    });
  }

  /// Afficher une bannière d'alerte en haut de l'écran
  static void showNotification({
    required String title,
    required String message,
    IconData icon = Icons.notifications_active_rounded,
    Color iconColor = AppColors.primary,
    VoidCallback? onTap,
    Duration duration = const Duration(seconds: 8),
  }) {
    if (!isNotificationsEnabled) return;

    final overlayState = appNavigatorKey.currentState?.overlay;
    if (overlayState == null) return;

    // Fermer toute notification déjà active
    _activeBannerEntry?.remove();
    _activeBannerEntry = null;

    HapticFeedback.mediumImpact();

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => NotificationBanner(
        title: title,
        message: message,
        icon: icon,
        iconColor: iconColor,
        duration: duration,
        onTap: onTap,
        onDismiss: () {
          if (_activeBannerEntry == entry) {
            _activeBannerEntry?.remove();
            _activeBannerEntry = null;
          }
        },
      ),
    );

    _activeBannerEntry = entry;
    overlayState.insert(entry);
  }
}
