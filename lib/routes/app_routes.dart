// lib/routes/app_routes.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/navigation/app_navigator.dart';

// ── Core screens ──────────────────────────────────────────────────────────────
import '../features/main/main_screen.dart';
import '../features/home/home_screen.dart';
import '../features/home/product_detail_screen.dart';
import '../features/cart/checkout_screen.dart';
import '../features/cart/order_success_screen.dart';

// ── Auth ──────────────────────────────────────────────────────────────────────
import '../features/auth/login_screen.dart';

// ── Bottom nav screens ────────────────────────────────────────────────────────
import '../features/categories/categories_screen.dart';
import '../features/favourites/favourites_screen.dart';
import '../features/cart/cart_screen.dart';
import '../features/profile/profile_screen.dart';

// ── Profile sub-screens ───────────────────────────────────────────────────────
import '../features/profile/orders_screen.dart';
import '../features/profile/order_tracking_screen.dart';
import '../features/profile/settings_screen.dart';
import '../features/profile/privacy_policy_screen.dart';
import '../features/profile/delete_account_screen.dart';

// ── Support ───────────────────────────────────────────────────────────────────
import '../features/support/support_screen.dart';

// ── Formules ──────────────────────────────────────────────────────────────────
// ⚠️ Vérifie le chemin réel de ton fichier. J'ai supposé
//    lib/features/formules/formules_screen.dart. Adapte si besoin.
import '../features/formules/formules_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  ROUTE NAMES  (évite les fautes de frappe)
// ─────────────────────────────────────────────────────────────────────────────
abstract class Routes {
  // Shell
  static const home       = '/home';
  static const categories = '/categories';
  static const favourites = '/favourites';
  static const cart       = '/cart';
  static const profile    = '/profile';

  // Auth
  static const login      = '/login';

  // Product
  static const product    = '/product/:id';
  static String productPath(String id) => '/product/$id';

  // Formules (paniers thématiques)
  // ⚠️ On identifie la formule par son "title" Firestore (ex: "Beldi", "Sain", "Saisonnier"),
  //    encodé dans l'URL pour rester compatible avec go_router.
  static const formules = '/formules/:formule';
  static String formulesPath(String formule) =>
      '/formules/${Uri.encodeComponent(formule)}';

  // Cart / Checkout flow
  static const checkout      = '/checkout';
  static const orderSuccess  = '/order-success/:orderId';
  static String orderSuccessPath(String id) => '/order-success/$id';
  static const orderTrackingId = '/order-tracking/:orderId';
  static String orderTrackingPath(String id) => '/order-tracking/$id';

  // Support
  static const support    = '/support';

  // Profile sub-screens
  static const orders     = '/orders';
  static const reviews    = '/reviews';
  static const settings   = '/settings';

  // Legal
  // ⚠️ Route non protégée volontairement : la politique de confidentialité
  // doit être consultable sans connexion, notamment depuis login_screen.dart
  // avant même que l'utilisateur ait un compte.
  static const privacyPolicy = '/privacy-policy';

  // Suppression du compte
  // ⚠️ Route non protégée volontairement : elle doit rester accessible
  // même sans connexion (exigence Google Play / App Store pour la
  // suppression de compte), et accessible depuis login_screen.dart.
  static const deleteAccount = '/delete-account';
}

// ─────────────────────────────────────────────────────────────────────────────
//  ROUTER
// ─────────────────────────────────────────────────────────────────────────────
class AppRoutes {
  static const _protected = {
    Routes.profile,
    Routes.orders,
    Routes.reviews,
  };

  // Routes paramétrées (commande) protégées par préfixe plutôt que par
  // égalité exacte, car elles contiennent un :orderId variable.
  static bool _isOrderRoute(String loc) =>
      loc.startsWith('/order-tracking/') || loc.startsWith('/order-success/') ||
      loc == Routes.checkout;

  static bool get _isLoggedIn =>
      FirebaseAuth.instance.currentUser != null;

  static final GoRouter router = GoRouter(
    navigatorKey: appNavigatorKey,
    initialLocation: Routes.home,
    debugLogDiagnostics: false,

    // ── Global redirect ────────────────────────────────────────────────────
    redirect: (context, state) {
      final loc         = state.matchedLocation;
      final isLogin      = loc == Routes.login;
      final isProtected  = _protected.contains(loc) || _isOrderRoute(loc);

      if (isProtected && !_isLoggedIn) {
        // Mémorise la page cible pour y revenir après login
        return '${Routes.login}?from=$loc';
      }
      if (_isLoggedIn && isLogin) {
        final from = state.uri.queryParameters['from'] ?? Routes.profile;
        return from;
      }
      return null;
    },

    routes: [
      // ── Shell Route (barre de navigation) ─────────────────────────────
      ShellRoute(
        builder: (context, state, child) => MainScreen(child: child),
        routes: [
          GoRoute(
            path:    Routes.home,
            builder: (_, __) => const HomeScreen(),
          ),
          GoRoute(
            path:    Routes.categories,
            builder: (_, __) => const CategoriesScreen(),
          ),
          GoRoute(
            path:    Routes.favourites,
            builder: (_, __) => const FavouritesScreen(),
          ),
          GoRoute(
            path:    Routes.cart,
            builder: (_, __) => const CartScreen(),
          ),
          GoRoute(
            path:    Routes.profile,
            builder: (_, __) => const ProfileScreen(),
          ),
        ],
      ),

      // ── Auth ───────────────────────────────────────────────────────────
      GoRoute(
        path: Routes.login,
        pageBuilder: (_, state) {
          final from = state.uri.queryParameters['from'] ?? Routes.profile;
          return _fadePage(LoginScreen(redirectTo: from));
        },
      ),

      // ── Product detail ─────────────────────────────────────────────────
      // ⚠️ Route non protégée volontairement : la fiche produit doit être
      // consultable sans connexion (seul l'ajout au panier exige un login,
      // déjà géré dans home_screen.dart / product_detail_screen.dart).
      GoRoute(
        path: Routes.product,
        pageBuilder: (_, state) => _slidePage(
          ProductDetailScreen(
            productId: state.pathParameters['id'] ?? '',
          ),
        ),
      ),

      // ── Formules (paniers thématiques : Beldi / Sain / Saisonnier) ─────
      GoRoute(
        path: '/formules',
        pageBuilder: (_, __) => _slidePage(const FormulesScreen()),
      ),
      GoRoute(
        path: Routes.formules,
        pageBuilder: (_, state) {
          final formule = Uri.decodeComponent(
              state.pathParameters['formule'] ?? '');
          return _slidePage(FormulesScreen(initialFormule: formule));
        },
      ),

      // ── Checkout (commande) ───────────────────────────────────────────
      // ⚠️ Nécessite que `extra` contienne {cartDocs, productDocs, deliveryFee}
      // tel qu'envoyé par cart_screen.dart (_CartSummaryBar._goToCheckout).
     GoRoute(
  path: Routes.checkout,
  pageBuilder: (_, state) {
    final extra = state.extra as Map<String, dynamic>? ?? {};
    final cartDocs =
        (extra['cartDocs'] as List?)?.cast<QueryDocumentSnapshot>() ?? [];
    final formuleDocs =
        (extra['formuleDocs'] as List?)?.cast<QueryDocumentSnapshot>() ?? [];
    final deliveryFee = (extra['deliveryFee'] as num?)?.toDouble() ?? 0.0;
    final redeemedPoints = (extra['redeemedPoints'] as num?)?.toInt() ?? 0;
    final pointsDiscount = (extra['pointsDiscount'] as num?)?.toDouble() ?? 0.0;
    return _slidePage(
      CheckoutScreen(
        cartDocs: cartDocs,
        formuleDocs: formuleDocs,
        deliveryFee: deliveryFee,
        redeemedPoints: redeemedPoints,
        pointsDiscount: pointsDiscount,
      ),
    );
  },
),

      // ── Confirmation de commande ──────────────────────────────────────
      GoRoute(
        path: Routes.orderSuccess,
        pageBuilder: (_, state) => _fadePage(
          OrderSuccessScreen(orderId: state.pathParameters['orderId'] ?? ''),
        ),
      ),

      // ── Suivi de commande (lit le statut mis à jour par le dashboard) ──
      GoRoute(
        path: Routes.orderTrackingId,
        pageBuilder: (_, state) => _slidePage(
          OrderTrackingScreen(orderId: state.pathParameters['orderId'] ?? ''),
        ),
      ),

      // ── Stopgap : cart_screen.dart (carrousel "commandes en cours") et
      //    orders_screen.dart naviguent vers `/orders/:orderId` pour une
      //    fiche détail qui n'existe pas encore comme écran dédié. En
      //    attendant, on redirige vers l'écran de suivi existant plutôt que
      //    de laisser ces liens tomber sur "Page introuvable". À remplacer
      //    par un vrai écran de détail de commande si besoin. ──
      GoRoute(
        path: '/orders/:orderId',
        redirect: (context, state) =>
            Routes.orderTrackingPath(state.pathParameters['orderId'] ?? ''),
      ),

      // ── Support ────────────────────────────────────────────────────────
      GoRoute(
        path:        Routes.support,
        pageBuilder: (_, __) => _slidePage(const SupportScreen()),
      ),

      // ── Profile sub-screens ────────────────────────────────────────────
     
      GoRoute(
        path:        Routes.orders,
        pageBuilder: (_, __) => _slidePage(const OrdersScreen()),
      ),
     
     
    
      GoRoute(
        path:        Routes.settings,
        pageBuilder: (_, __) => _slidePage(const SettingsScreen()),
      ),

      // ── Politique de confidentialité (accessible sans connexion,
      //    notamment depuis login_screen.dart) ────────────────────────────
      GoRoute(
        path:        Routes.privacyPolicy,
        pageBuilder: (_, __) => _slidePage(const PrivacyPolicyScreen()),
      ),

      // ── Suppression du compte (accessible sans connexion, notamment
      //    depuis login_screen.dart) ──────────────────────────────────────
      GoRoute(
        path:        Routes.deleteAccount,
        pageBuilder: (_, __) => _slidePage(const DeleteAccountScreen()),
      ),
      
     
      
    ],

    // ── Gestion d'erreur (route inconnue) ──────────────────────────────────
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text('Page introuvable : ${state.uri}',
                style: const TextStyle(fontFamily: 'Cairo')),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => context.go(Routes.home),
              child: const Text('Retour à l\'accueil'),
            ),
          ],
        ),
      ),
    ),
  );

  // ── Custom page transitions ────────────────────────────────────────────────

  /// Fade transition (pour login)
  static Page<void> _fadePage(Widget child) => CustomTransitionPage(
    child: child,
    transitionsBuilder: (_, anim, __, c) =>
        FadeTransition(opacity: anim, child: c),
    transitionDuration: const Duration(milliseconds: 300),
  );

  /// Slide from right (pour les sous-écrans)
  static Page<void> _slidePage(Widget child) => CustomTransitionPage(
    child: child,
    transitionsBuilder: (_, anim, __, c) => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end:   Offset.zero,
      ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: c,
    ),
    transitionDuration: const Duration(milliseconds: 320),
  );
}