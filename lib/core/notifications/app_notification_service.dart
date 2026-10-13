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
import 'package:mrbeldi/routes/app_routes.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_banner.dart';

class AppNotificationService {
  static const String _prefNotificationsEnabled = 'notifications_push_enabled';
  static const String _prefPromosEnabled = 'notifications_promos_enabled';
  static const String _prefCartLastInteraction = 'cart_last_interaction_timestamp';
  static const String _prefCartReminderSent = 'cart_reminder_sent';
  static const String _prefSeenNotificationIds = 'seen_firestore_notifications_ids';

  static final ValueNotifier<bool> notificationsEnabledNotifier =
      ValueNotifier<bool>(true);
  static final ValueNotifier<bool> promosEnabledNotifier =
      ValueNotifier<bool>(true);

  static bool get isNotificationsEnabled => notificationsEnabledNotifier.value;
  static bool get isPromosEnabled => promosEnabledNotifier.value;

  static OverlayEntry? _activeBannerEntry;
  static StreamSubscription<QuerySnapshot>? _firestoreNotificationsSub;
  static StreamSubscription<User?>? _authSubscription;
  static StreamSubscription<QuerySnapshot>? _ordersSubscription;
  static final Map<String, String> _knownOrderStatuses = {};
  static bool _ordersInitialSnapshotDone = false;
  static bool _initialized = false;

  /// Initialisation du service au démarrage de l'application
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_prefNotificationsEnabled) ?? true;
      final promos = prefs.getBool(_prefPromosEnabled) ?? true;

      notificationsEnabledNotifier.value = enabled;
      promosEnabledNotifier.value = promos;

      // Écouter les notifications Firestore de promotions
      _startFirestoreNotificationsListener();

      // Écouter les changements d'état des commandes
      _startOrderStatusListener();

      // Vérifier le rappel de panier après un court délai (10 secondes après ouverture)
      Timer(const Duration(seconds: 10), () {
        checkCartAbandonment();
      });
    } catch (e) {
      debugPrint('AppNotificationService.init error: $e');
    }
  }

  /// Activer ou désactiver les notifications push
  static Future<void> setNotificationsEnabled(bool enabled) async {
    notificationsEnabledNotifier.value = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefNotificationsEnabled, enabled);
    } catch (e) {
      debugPrint('Error saving notificationsEnabled: $e');
    }
  }

  /// Activer ou désactiver les offres et promotions
  static Future<void> setPromosEnabled(bool enabled) async {
    promosEnabledNotifier.value = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefPromosEnabled, enabled);
    } catch (e) {
      debugPrint('Error saving promosEnabled: $e');
    }
  }

  /// Enregistrer une interaction avec le panier (ajout, retrait, consultation)
  static Future<void> recordCartInteraction() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(_prefCartLastInteraction, now);
      await prefs.setBool(_prefCartReminderSent, false);
    } catch (e) {
      debugPrint('Error recording cart interaction: $e');
    }
  }

  /// Réinitialiser l'état du rappel (ex: après finalisation d'une commande)
  static Future<void> resetCartReminder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefCartReminderSent, false);
      await prefs.remove(_prefCartLastInteraction);
    } catch (e) {
      debugPrint('Error resetting cart reminder: $e');
    }
  }

  /// Vérification de l'abandon de panier (3 jours sans retour)
  static Future<void> checkCartAbandonment() async {
    if (!isNotificationsEnabled) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadySent = prefs.getBool(_prefCartReminderSent) ?? false;
      if (alreadySent) return;

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
        await prefs.setBool(_prefCartReminderSent, false);
        return;
      }

      // 2. Vérifier la date de dernière interaction
      final now = DateTime.now();
      final lastInteractionMs = prefs.getInt(_prefCartLastInteraction);

      if (lastInteractionMs == null) {
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
            AppRoutes.router.push(Routes.cart);
          },
        );

        await prefs.setBool(_prefCartReminderSent, true);
      }
    } catch (e) {
      debugPrint('Error checking cart abandonment: $e');
    }
  }

  /// Écouteur en temps réel de la collection "Notifications"
  static void _startFirestoreNotificationsListener() {
    _firestoreNotificationsSub?.cancel();

    _firestoreNotificationsSub = FirebaseFirestore.instance
        .collection('Notifications')
        .snapshots()
        .listen((snapshot) async {
      if (!isNotificationsEnabled || !isPromosEnabled) return;

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

            final note = (data['note'] ?? data['message'] ?? data['body'] ?? data['description']) as String?;
            if (note == null || note.trim().isEmpty) continue;

            // Marquer comme vu immédiatement pour ne pas répéter
            seenIds.add(docId);
            await prefs.setStringList(
                _prefSeenNotificationIds, seenIds.toList());

            // Titre selon document ou langue de l'appareil
            final customTitle = data['title'] as String?;
            final lang = AppLocaleService.detectDeviceLocale().languageCode;
            String title;
            if (customTitle != null && customTitle.trim().isNotEmpty) {
              title = customTitle.trim();
            } else if (lang == 'ar') {
              title = 'لا تفوت هذا العرض المذهل 🌿';
            } else if (lang == 'fr') {
              title = 'Ne manquez pas cette offre incroyable ! 🌿';
            } else {
              title = "Don't miss this amazing offer! 🌿";
            }

            final route = data['route'] as String?;
            final productId = data['productId'] as String?;
            final formule = data['formule'] as String?;

            showNotification(
              title: title,
              message: note.trim(),
              icon: Icons.local_offer_rounded,
              iconColor: AppColors.primary,
              onTap: () {
                if (route != null && route.isNotEmpty) {
                  AppRoutes.router.push(route);
                } else if (productId != null && productId.isNotEmpty) {
                  AppRoutes.router.push(Routes.productPath(productId));
                } else if (formule != null && formule.isNotEmpty) {
                  AppRoutes.router.push(Routes.formulesPath(formule));
                } else {
                  AppRoutes.router.push(Routes.categories);
                }
              },
            );

            // On n'affiche qu'une notification promotionnelle à la fois
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

  /// Écouteur en temps réel des statuts des commandes de l'utilisateur
  static void _startOrderStatusListener() {
    _authSubscription?.cancel();
    _ordersSubscription?.cancel();
    _knownOrderStatuses.clear();
    _ordersInitialSnapshotDone = false;

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      _ordersSubscription?.cancel();
      _knownOrderStatuses.clear();
      _ordersInitialSnapshotDone = false;

      if (user == null) return;

      _ordersSubscription = FirebaseFirestore.instance
          .collection('orders')
          .where('userId', isEqualTo: user.uid)
          .snapshots()
          .listen((snapshot) {
        if (!isNotificationsEnabled) return;

        if (!_ordersInitialSnapshotDone) {
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final status = (data['status'] as String?) ?? 'pending';
            _knownOrderStatuses[doc.id] = status;
          }
          _ordersInitialSnapshotDone = true;
          return;
        }

        for (final change in snapshot.docChanges) {
          final doc = change.doc;
          final orderId = doc.id;
          final data = doc.data();
          if (data == null) continue;

          final newStatus = (data['status'] as String?) ?? 'pending';
          final oldStatus = _knownOrderStatuses[orderId];
          _knownOrderStatuses[orderId] = newStatus;

          if (oldStatus != null && oldStatus != newStatus && newStatus != 'pending') {
            _showOrderStatusNotification(orderId, newStatus);
          }
        }
      }, onError: (e) {
        debugPrint('Order status notification listener error: $e');
      });
    });
  }

  /// Afficher une notification transactionnelle lors de la mise à jour d'un statut de commande
  static void _showOrderStatusNotification(String orderId, String status) {
    final lang = AppLocaleService.detectDeviceLocale().languageCode;
    final shortId = orderId.length >= 6
        ? orderId.substring(0, 6).toUpperCase()
        : orderId.toUpperCase();

    String title;
    String message;
    IconData icon;
    Color iconColor;

    switch (status) {
      case 'confirmed':
        icon = Icons.check_circle_rounded;
        iconColor = AppColors.primary;
        if (lang == 'ar') {
          title = 'تم تأكيد طلبك #$shortId 📦';
          message = 'تمت الموافقة على طلبك بنجاح وهو قيد المتابعة.';
        } else if (lang == 'fr') {
          title = 'Commande confirmée #$shortId 📦';
          message = 'Votre commande a été validée avec succès.';
        } else {
          title = 'Order confirmed #$shortId 📦';
          message = 'Your order has been confirmed successfully.';
        }
        break;

      case 'preparing':
        icon = Icons.inventory_2_rounded;
        iconColor = const Color(0xFFE65100);
        if (lang == 'ar') {
          title = 'طلبك قيد التحضير 🧺';
          message = 'جاري تحضير وتجهيز منتجاتك الطازجة بكل عناية.';
        } else if (lang == 'fr') {
          title = 'Commande en préparation 🧺';
          message = 'Vos produits frais sont en cours de préparation.';
        } else {
          title = 'Order in preparation 🧺';
          message = 'Your fresh products are being carefully prepared.';
        }
        break;

      case 'shipped':
        icon = Icons.local_shipping_rounded;
        iconColor = const Color(0xFF1565C0);
        if (lang == 'ar') {
          title = 'طلبك في الطريق إليك 🚚';
          message = 'المندوب في طريقه لتسليم طلبك إلى عنوانك.';
        } else if (lang == 'fr') {
          title = 'Commande en livraison 🚚';
          message = 'Votre commande est en route vers votre adresse.';
        } else {
          title = 'Out for delivery 🚚';
          message = 'Your order is on the way to your address.';
        }
        break;

      case 'delivered':
        icon = Icons.home_rounded;
        iconColor = AppColors.primary;
        if (lang == 'ar') {
          title = 'تم تسليم طلبك بنجاح ! 🎉';
          message = 'نتمنى لك تجربة ممتعة مع منتجات MrBeldi.';
        } else if (lang == 'fr') {
          title = 'Commande livrée ! 🎉';
          message = 'Votre commande a été livrée. Bonne dégustation !';
        } else {
          title = 'Order delivered! 🎉';
          message = 'Your order has been delivered. Enjoy MrBeldi products!';
        }
        break;

      case 'cancelled':
        icon = Icons.cancel_rounded;
        iconColor = AppColors.error;
        if (lang == 'ar') {
          title = 'تم إلغاء الطلب #$shortId ❌';
          message = 'تم إلغاء طلبك. تواصل مع الدعم لأي استفسار.';
        } else if (lang == 'fr') {
          title = 'Commande annulée #$shortId ❌';
          message = 'Votre commande a été annulée. Contactez le support.';
        } else {
          title = 'Order cancelled #$shortId ❌';
          message = 'Your order has been cancelled. Contact support for help.';
        }
        break;

      default:
        return;
    }

    showNotification(
      title: title,
      message: message,
      icon: icon,
      iconColor: iconColor,
      onTap: () {
        AppRoutes.router.push(Routes.orderTrackingPath(orderId));
      },
    );
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
    if (overlayState == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showNotification(
          title: title,
          message: message,
          icon: icon,
          iconColor: iconColor,
          onTap: onTap,
          duration: duration,
        );
      });
      return;
    }

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
