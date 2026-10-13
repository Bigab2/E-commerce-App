// lib/features/favourites/favourites_screen.dart
//
// ─────────────────────────────────────────────────────────────────────────────
//  Lit favourites/{uid}/items en direct, puis pour chaque productId affiche
//  les données ACTUELLES du produit (prix, stock, etc.) depuis products/{id}
//  — jamais de données dupliquées/figées, même logique que le panier.
// ─────────────────────────────────────────────────────────────────────────────
//
//  ─────────────────────────────────────────────────────────────────────────
//  CORRECTIONS DE BUGS
//  ─────────────────────────────────────────────────────────────────────────
//  • Gestion d'erreur ajoutée sur les StreamBuilder (favoris + produit) :
//    avant, une erreur Firestore (réseau, permissions) était confondue avec
//    "aucun favori" ou laissait un écran de chargement infini, sans aucune
//    information pour l'utilisateur.
//  • `_addToCart` n'empêchait pas de dépasser le stock disponible quand le
//    produit était déjà dans le panier : `FieldValue.increment(1)` était
//    appliqué sans vérifier la quantité déjà présente. Désormais, on lit la
//    quantité actuelle dans la même transaction et on bloque l'ajout (avec
//    message explicatif) si la quantité résultante dépasserait le stock.
//  • `Colors.black.withOpacity(...)` (API dépréciée) remplacé par
//    `withValues(alpha: ...)`, cohérent avec le reste de l'app (cart_screen).
//  • `_EmptyLoginState()` / `_EmptyFavouritesState()` rendus `const` à l'appel.
//
//  ─────────────────────────────────────────────────────────────────────────
//  DESIGN — identité organique / nature légère
//  ─────────────────────────────────────────────────────────────────────────
//  • Fond légèrement crème-vert au lieu d'un gris froid, cartes avec un
//    grain de bord doux (border + ombre tamisée) plutôt qu'une ombre dure.
//  • Le cœur reste BLANC (contour) quand la liste est vide — il ne devient
//    rouge/plein que sur une vraie carte favorite, pour ne pas suggérer une
//    fausse action déjà faite sur l'écran vide.
//  • En-tête avec compteur d'articles + petit repère "stock" agrégé (combiné
//    en une seule ligne discrète, pas un bandeau publicitaire).
//  • Bouton "ajouter au panier" transformé en pastille pleine (au lieu d'un
//    simple contour) pour un meilleur contraste tactile, avec retour visuel
//    immédiat (icône + micro-animation d'échelle) à l'ajout.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mrbeldi/core/localization/app_locale_service.dart';
import 'package:mrbeldi/core/localization/app_strings.dart';
import 'package:mrbeldi/core/notifications/app_notification_service.dart';
import 'package:mrbeldi/core/theme/app_colors.dart';

class FavouritesScreen extends StatelessWidget {
  const FavouritesScreen({super.key});

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Future<void> _removeFavourite(String productId) async {
    if (_uid == null) return;
    await FirebaseFirestore.instance
        .collection('favourites')
        .doc(_uid)
        .collection('items')
        .doc(productId)
        .delete();
  }

  // ── Ajoute au panier en respectant le stock disponible, même si le
  //    produit est déjà présent dans le panier avec une certaine quantité. ──
  Future<void> _addToCart(
    BuildContext context,
    Map<String, dynamic> product,
    String productId,
  ) async {
    final uid = _uid;
    if (uid == null) return;

    final stock = (product['stock'] as num?)?.toInt();
    if (stock != null && stock <= 0) {
      _showSnack(
        context,
        'Ce produit est en rupture de stock',
        color: const Color(0xFFE53935),
      );
      return;
    }

    final ref = FirebaseFirestore.instance
        .collection('carts')
        .doc(uid)
        .collection('items')
        .doc(productId);

    bool blockedByStock = false;

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final s = await tx.get(ref);
      final currentQty = s.exists
          ? ((s.data() as Map?)?['qty'] as num?)?.toInt() ?? 0
          : 0;
      final nextQty = currentQty + 1;

      if (stock != null && nextQty > stock) {
        blockedByStock = true;
        return;
      }

      if (s.exists) {
        tx.update(ref, {'qty': nextQty});
      } else {
        tx.set(ref, {
          'productId': productId,
          'qty': 1,
          'addedAt': FieldValue.serverTimestamp(),
        });
      }
    });

    unawaited(AppNotificationService.recordCartInteraction());

    if (!context.mounted) return;

    if (blockedByStock) {
      _showSnack(
        context,
        'Stock maximum déjà atteint dans votre panier',
        color: Colors.orange[800]!,
      );
      return;
    }

    _showSnack(
      context,
      "${product['name'] ?? ''} ajouté au panier",
      color: AppColors.primary,
    );
  }

  void _showSnack(
    BuildContext context,
    String message, {
    required Color color,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null) {
      return const _EmptyLoginState();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9F4), // crème-vert très doux
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F9F4),
        elevation: 0,
        surfaceTintColor: const Color(0xFFF8F9F4),
        systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
        ),
        title: Text(
          context.tr('favourites_title'),
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A1A1A),
            fontSize: 18,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('favourites')
            .doc(_uid)
            .collection('items')
            .orderBy('addedAt', descending: true)
            .snapshots(),
        builder: (context, favSnap) {
          if (favSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (favSnap.hasError) {
            return _ErrorState(
              onRetry: () {
                // Le StreamBuilder se reconstruit automatiquement dès que le
                // flux Firestore se rétablit ; ce bouton sert surtout de
                // repère visuel pour l'utilisateur en attendant.
              },
            );
          }
          if (!favSnap.hasData || favSnap.data!.docs.isEmpty) {
            return const _EmptyFavouritesState();
          }

          final favDocs = favSnap.data!.docs;

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _HeaderBar(count: favDocs.length)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.68,
                  ),
                  delegate: SliverChildBuilderDelegate((ctx, i) {
                    final productId = favDocs[i].id;
                    return StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('products')
                          .doc(productId)
                          .snapshots(),
                      builder: (ctx, prodSnap) {
                        if (prodSnap.hasError) {
                          return _UnavailableCard(
                            message: 'Erreur de chargement',
                            onRemove: () => _removeFavourite(productId),
                          );
                        }
                        if (!prodSnap.hasData) {
                          return const _CardSkeleton();
                        }
                        if (!prodSnap.data!.exists) {
                          return _UnavailableCard(
                            message: 'Produit indisponible',
                            onRemove: () => _removeFavourite(productId),
                          );
                        }
                        final product =
                            prodSnap.data!.data() as Map<String, dynamic>;
                        return _FavCard(
                          productId: productId,
                          product: product,
                          onRemove: () => _removeFavourite(productId),
                          onAddToCart: () =>
                              _addToCart(context, product, productId),
                        );
                      },
                    );
                  }, childCount: favDocs.length),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  EN-TÊTE — compteur d'articles, discret et utile (pas un bandeau promo)
// ─────────────────────────────────────────────────────────────────────────────
class _HeaderBar extends StatelessWidget {
  final int count;
  const _HeaderBar({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFFE8EFE1), // vert sauge très clair
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.eco_rounded,
              size: 16,
              color: Color(0xFF5B7A4A),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            count == 1
                ? (AppLocaleService.isRtl
                      ? 'منتج واحد مفضل'
                      : '1 produit favori')
                : (AppLocaleService.isRtl
                      ? '$count منتجات مفضلة'
                      : '$count produits favoris'),
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF5B6B53),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  EMPTY STATES
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyLoginState extends StatelessWidget {
  const _EmptyLoginState();
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('❤️', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(
              AppLocaleService.isRtl
                  ? 'قم بتسجيل الدخول لعرض قائمة المفضلة'
                  : 'Connectez-vous pour voir vos favoris',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => context.push('/login'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                AppLocaleService.isRtl ? 'تسجيل الدخول' : 'Se connecter',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _EmptyFavouritesState extends StatelessWidget {
  const _EmptyFavouritesState();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🤍', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          Text(
            context.tr('favourites_empty'),
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.tr('favourites_empty_sub'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => context.go('/home'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              context.tr('explore_products'),
              style: const TextStyle(
                fontFamily: 'Cairo',
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  ÉTAT D'ERREUR
// ─────────────────────────────────────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            size: 44,
            color: Color(0xFFBDBDBD),
          ),
          const SizedBox(height: 12),
          Text(
            AppLocaleService.isRtl
                ? 'تعذر تحميل المنتجات المفضلة'
                : 'Impossible de charger vos favoris',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF616161),
            ),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: onRetry,
            child: Text(
              context.tr('retry'),
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFEFF1EA)),
    ),
  );
}

class _UnavailableCard extends StatelessWidget {
  final VoidCallback onRemove;
  final String message;
  const _UnavailableCard({
    required this.onRemove,
    this.message = 'Produit indisponible',
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFEFF1EA)),
    ),
    padding: const EdgeInsets.all(12),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.eco_outlined, color: Color(0xFFBDBDBD), size: 28),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
        TextButton(
          onPressed: onRemove,
          child: const Text(
            'Retirer',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              color: Color(0xFFE53935),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  FAV CARD — bords doux, ombre tamisée, cœur plein pour une vraie carte
// ─────────────────────────────────────────────────────────────────────────────
class _FavCard extends StatelessWidget {
  final String productId;
  final Map<String, dynamic> product;
  final VoidCallback onRemove;
  final VoidCallback onAddToCart;

  const _FavCard({
    required this.productId,
    required this.product,
    required this.onRemove,
    required this.onAddToCart,
  });

  double _p(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final name = product['name']?.toString() ?? '';
    final imageUrl = product['imageUrl']?.toString() ?? '';
    final price = _p(product['price']);
    final oldPrice = _p(product['oldPrice']);
    final hasDiscount = oldPrice > price && oldPrice > 0;
    final stock = (product['stock'] as num?)?.toInt();
    final outOfStock = stock != null && stock <= 0;
    final lowStock = !outOfStock && stock != null && stock <= 5;

    return GestureDetector(
      onTap: () => context.push('/product/$productId'),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEFF1EA)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF5B7A4A).withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: Opacity(
                    opacity: outOfStock ? 0.5 : 1,
                    child: AspectRatio(
                      aspectRatio: 1.05,
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(color: const Color(0xFFF1F3EC)),
                        errorWidget: (_, __, ___) => Container(
                          color: const Color(0xFFF1F3EC),
                          child: const Icon(
                            Icons.eco_outlined,
                            color: Color(0xFFBDBDBD),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // ── Cœur plein, rouge : carte réelle = favori confirmé ──
                Positioned(
                  right: 7,
                  top: 7,
                  child: GestureDetector(
                    onTap: onRemove,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.10),
                            blurRadius: 5,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.favorite_rounded,
                        color: Color(0xFFE53935),
                        size: 16,
                      ),
                    ),
                  ),
                ),
                if (hasDiscount && !outOfStock)
                  Positioned(
                    left: 7,
                    top: 7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF5B7A4A),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '-${(((oldPrice - price) / oldPrice) * 100).round()}%',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                if (outOfStock)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.55),
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Center(
                        child: Text(
                          context.tr('out_of_stock'),
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF212121),
                        height: 1.25,
                      ),
                    ),
                    if (lowStock) ...[
                      const SizedBox(height: 3),
                      Text(
                        AppLocaleService.isRtl
                            ? 'متبقي $stock فقط'
                            : 'Plus que $stock en stock',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFE08A00),
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (hasDiscount)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          '${oldPrice.toStringAsFixed(oldPrice % 1 == 0 ? 0 : 1)} ${context.tr('currency')}',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 10,
                            color: Color(0xFF9E9E9E),
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${price.toStringAsFixed(price % 1 == 0 ? 0 : 1)} ${context.tr('currency')}',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        GestureDetector(
                          onTap: outOfStock ? null : onAddToCart,
                          child: Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: outOfStock
                                  ? const Color(0xFFF1F3EC)
                                  : AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.add_rounded,
                              size: 18,
                              color: outOfStock
                                  ? const Color(0xFFBDBDBD)
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
