// lib/features/home/product_detail_screen.dart
//
// ─────────────────────────────────────────────────────────────────────────────
//  ─────────────────────────────────────────────────────────────────────────
//  NOUVELLES CORRECTIONS (cette révision)
//  ─────────────────────────────────────────────────────────────────────────
//  • BUG : sous les étoiles, le nombre affiché était `reviewCount` (nombre
//    d'avis écrits) au lieu de `ratingCount` (nombre total de notations).
//    Corrigé : on lit désormais `ratingCount` pour ce badge.
//  • BUG : le nombre de ventes utilisait un champ `soldCount` qui n'existe
//    pas dans le document produit. Le vrai champ, cohérent avec les
//    Firestore rules (`salesCount`), est maintenant utilisé et affiché
//    dans un badge dédié, plus lisible.
//  • Les avis (products/{id}/reviews) peuvent ne jamais s'afficher si les
//    Firestore rules ne couvrent pas explicitement cette sous-collection —
//    une règle "read: true" sur /products/{id} ne s'applique PAS à ses
//    sous-collections. Il faut une règle dédiée côté Firestore (voir chat).
//  • `_toggleFavorite` n'avait aucune gestion d'erreur : un refus des
//    Firestore rules (ex. règle manquante) échouait silencieusement sans
//    aucun retour visuel. Ajout d'un try/catch + message explicite.
//  • Bandeau "livraison gratuite / bio" entièrement repensé : nouveau
//    design en 3 badges de confiance, textes en français professionnel,
//    plus proche des standards e-commerce (Shopify/Amazon-like trust bar).
//  • NOUVEAU : dans les avis, le nom d'utilisateur affiché n'est plus
//    "Client" générique. On affiche désormais les 5 premiers caractères
//    du vrai nom d'utilisateur (userName), suivis de points de masquage
//    (ex: "Moham•••"), pour un rendu à la fois personnalisé et discret
//    côté vie privée.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mrbeldi/core/services/local_cart_service.dart';
import 'package:mrbeldi/core/theme/app_colors.dart';

// Couleur "prix" fixe (marqueur orange), indépendante de AppColors.primary
// (qui peut être verte ailleurs dans l'app) — demandée explicitement en
// orange pour le prix, la barre de note/ventes et le soulignement du prix
// barré.
const Color _kPriceOrange = Color(0xFFFF6D00);

class ProductDetailScreen extends StatefulWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  int quantity = 1;

  // FIX : "ajouté" n'est plus un état permanent — c'est un flash temporaire
  // qui revient automatiquement à l'état normal après 1.5s.
  bool _justAdded = false;

  bool _showFullDescription = false;

  int _currentImage = 0;
  final PageController _pageController = PageController();

  int? _selectedColorIndex;
  int? _selectedTypeIndex;

  final _reviewsKey = GlobalKey();

  // Nombre maximum de champs imageUrlN à sonder (imageUrl1 ... imageUrl20).
  static const int _maxIndexedImages = 20;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  double _p(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  // Renvoie la liste des images du produit.
  //
  // Schéma principal : imageUrl (1ère image), imageUrl1, imageUrl2,
  // imageUrl3, ... jusqu'à _maxIndexedImages. On s'arrête d'ajouter dès
  // qu'un champ est vide/absent n'est PAS requis : certains produits peuvent
  // avoir des trous, donc on scanne tous les index et on garde ceux qui sont
  // renseignés, dans l'ordre.
  //
  // Compatibilité ascendante : si aucun champ imageUrl* n'est trouvé, on
  // retombe sur l'ancien champ liste "images" (List<String>).
  List<String> _images(Map<String, dynamic> product) {
    final List<String> result = [];

    final first = product['imageUrl']?.toString().trim() ?? '';
    if (first.isNotEmpty) result.add(first);

    for (int i = 1; i <= _maxIndexedImages; i++) {
      final v = product['imageUrl$i']?.toString().trim() ?? '';
      if (v.isNotEmpty) result.add(v);
    }

    if (result.isNotEmpty) return result;

    // Repli sur l'ancien schéma "images" (List) pour les produits existants.
    final raw = product['images'];
    if (raw is List) {
      return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    return [];
  }

  List<String> _stringList(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    return const [];
  }

  Color _parseColor(String value) {
    var hex = value.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length == 8) {
      final n = int.tryParse(hex, radix: 16);
      if (n != null) return Color(n);
    }
    // Pas un code hexadécimal (ex: "Rouge") : couleur neutre de repli.
    return const Color(0xFFBDBDBD);
  }

  String _thousands(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  // Formate un compteur (ventes) de façon compacte et lisible :
  // 1..999 -> "N+", 1000+ -> "1,000+" (arrondi au millier inférieur).
  String _formatSold(int n) {
    if (n <= 0) return '';
    if (n >= 1000) {
      final rounded = (n ~/ 1000) * 1000;
      return '${_thousands(rounded)}+';
    }
    return '$n+';
  }

  Future<void> _toggleFavorite(bool isFav) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showSnack('Connectez-vous pour ajouter aux favoris', isError: true);
      return;
    }
    final ref = FirebaseFirestore.instance
        .collection('favourites')
        .doc(uid)
        .collection('items')
        .doc(widget.productId);
    try {
      if (isFav) {
        await ref.delete();
      } else {
        await ref.set({
          'productId': widget.productId,
          'addedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      // FIX : avant, un refus des Firestore rules (ex. règle manquante
      // pour /favourites) échouait silencieusement, sans aucun retour
      // pour l'utilisateur.
      _showSnack('Impossible de mettre à jour vos favoris', isError: true);
    }
  }

 Future<void> _addToCart(Map<String, dynamic> product) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  final stock = (product['stock'] as num?)?.toInt();
  if (stock != null && stock <= 0) {
    _showSnack('Ce produit est en rupture de stock', isError: true);
    return;
  }

  // ── زائر غير مسجل: نحفظ محلياً بدل Firestore ──
  if (uid == null) {
    await LocalCartService.addItem(widget.productId, qty: quantity);
    if (!mounted) return;
    setState(() => _justAdded = true);
    _showSnack('${product['name'] ?? ''} × $quantity ajouté au panier');
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _justAdded = false);
    });
    return;
  }

  final colors = _stringList(product['colors']);
  final types = _stringList(product['types']);
  final selectedColor = (colors.isNotEmpty && _selectedColorIndex != null)
      ? colors[_selectedColorIndex!]
      : null;
  final selectedType = (types.isNotEmpty && _selectedTypeIndex != null)
      ? types[_selectedTypeIndex!]
      : null;

  try {
    final ref = FirebaseFirestore.instance
        .collection('carts')
        .doc(uid)
        .collection('items')
        .doc(widget.productId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final s = await tx.get(ref);
      final currentQty = s.exists ? ((s.data() as Map)['qty'] as num?)?.toInt() ?? 0 : 0;
      final newQty = currentQty + quantity;
      if (stock != null && newQty > stock) {
        throw Exception('STOCK_LIMIT');
      }
      final data = <String, dynamic>{
        'productId': widget.productId,
        'qty': newQty,
        if (selectedColor != null) 'color': selectedColor,
        if (selectedType != null) 'type': selectedType,
      };
      if (s.exists) {
        tx.update(ref, data);
      } else {
        tx.set(ref, {...data, 'addedAt': FieldValue.serverTimestamp()});
      }
    });

    if (!mounted) return;
    setState(() => _justAdded = true);
    _showSnack('${product['name'] ?? ''} × $quantity ajouté au panier');

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _justAdded = false);
    });
  } catch (e) {
    _showSnack(
      e.toString().contains('STOCK_LIMIT')
          ? 'Stock maximum atteint pour ce produit'
          : 'Erreur, réessayez',
      isError: true,
    );
  }
}

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
      backgroundColor: isError ? const Color(0xFFE53935) : AppColors.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _scrollToReviews() {
    final ctx = _reviewsKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    // FIX (status bar) : on fige la couleur des icônes système (heure,
    // batterie, réseau) en foncé, quel que soit le contenu de l'image
    // affichée derrière elles. Comme la galerie a désormais toujours un
    // fond blanc opaque (voir _ImageGallery), des icônes foncées restent
    // lisibles en permanence — plus de "mélange" avec des photos à fond
    // transparent.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark, // Android
        statusBarBrightness: Brightness.light, // iOS
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          top: true,
          bottom: false,
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('products').doc(widget.productId).snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snap.hasData || !snap.data!.exists) {
                return const _NotFoundView();
              }

              final product = snap.data!.data() as Map<String, dynamic>;
              final price = _p(product['price']);
              final oldPrice = _p(product['oldPrice']);
              final hasDiscount = oldPrice > price && oldPrice > 0;
              final discountPercent = hasDiscount ? (((oldPrice - price) / oldPrice) * 100).round() : 0;
              final stock = (product['stock'] as num?)?.toInt();
              final outOfStock = stock != null && stock <= 0;
              final rating = _p(product['rating']).clamp(0.0, 5.0);
              // FIX : sous les étoiles on doit afficher le nombre de NOTES
              // (ratingCount), pas le nombre d'avis écrits (reviewCount) —
              // ce sont deux compteurs distincts.
              final reviewCount = (product['reviewCount'] as num?)?.toInt() ?? 0;
              final ratingCount = (product['ratingCount'] as num?)?.toInt() ?? 0;
              // FIX : le champ réel du nombre de ventes est "salesCount"
              // (cohérent avec les Firestore rules), pas "soldCount" qui
              // n'existe dans aucun document produit.
              final salesCount = (product['salesCount'] as num?)?.toInt() ?? 0;
              final description = product['description']?.toString() ?? '';
              final category = product['category']?.toString() ?? '';
              final images = _images(product);
              final colors = _stringList(product['colors']);
              final types = _stringList(product['types']);

              return CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // ── Galerie d'images (protégée par SafeArea) ──
                  SliverAppBar(
                    expandedHeight: 380,
                    pinned: true,
                    backgroundColor: Colors.white,
                    surfaceTintColor: Colors.white,
                    leading: _CircleIconBtn(
                      icon: Icons.arrow_back_ios_new_rounded,
                      onTap: () => context.pop(),
                    ),
                    actions: [
                      StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseAuth.instance.currentUser == null
                            ? const Stream.empty()
                            : FirebaseFirestore.instance
                                .collection('favourites')
                                .doc(FirebaseAuth.instance.currentUser!.uid)
                                .collection('items')
                                .doc(widget.productId)
                                .snapshots(),
                        builder: (_, favSnap) {
                          final isFav = favSnap.data?.exists ?? false;
                          return _CircleIconBtn(
                            icon: isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            iconColor: isFav ? const Color(0xFFE53935) : Colors.black,
                            onTap: () => _toggleFavorite(isFav),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                    flexibleSpace: FlexibleSpaceBar(
                      background: Hero(
                        tag: 'product_${widget.productId}',
                        child: _ImageGallery(
                          images: images,
                          controller: _pageController,
                          currentIndex: _currentImage,
                          onPageChanged: (i) => setState(() => _currentImage = i),
                        ),
                      ),
                    ),
                  ),

                  // ── Contenu (protégé par SafeArea pour le bas/côtés) ──
                  SliverSafeArea(
                    top: false,
                    sliver: SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Nouveau bandeau de confiance (livraison,
                            // bio, garantie qualité) — design entièrement
                            // repensé, en français, remplace l'ancien
                            // bandeau crème sous l'image.
                            const _TrustBar(),

                            // ── Aperçu de la description ──
                            if (description.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Text(
                                description,
                                maxLines: _showFullDescription ? null : 2,
                                overflow: _showFullDescription ? TextOverflow.visible : TextOverflow.ellipsis,
                                style: TextStyle(fontFamily: 'Cairo', fontSize: 14, height: 1.5, color: Colors.grey[700]),
                              ),
                              const SizedBox(height: 2),
                              GestureDetector(
                                onTap: () => setState(() => _showFullDescription = !_showFullDescription),
                                behavior: HitTestBehavior.opaque,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _showFullDescription ? 'Réduire' : 'Lire plus',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    AnimatedRotation(
                                      turns: _showFullDescription ? 0.5 : 0,
                                      duration: const Duration(milliseconds: 200),
                                      child: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.primary),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            const SizedBox(height: 14),

                            // ── Prix (orange) à gauche, note ⭐ + ventes à droite ──
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${price.toStringAsFixed(price % 1 == 0 ? 0 : 1)} DH',
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 27,
                                    fontWeight: FontWeight.w900,
                                    color: _kPriceOrange,
                                  ),
                                ),
                                if (hasDiscount) ...[
                                  const SizedBox(width: 10),
                                  Text(
                                    '${oldPrice.toStringAsFixed(oldPrice % 1 == 0 ? 0 : 1)} DH',
                                    style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black87,
                                      decoration: TextDecoration.lineThrough,
                                      decorationColor: _kPriceOrange,
                                      decorationThickness: 3,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: _kPriceOrange, width: 1.4),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      '-$discountPercent%',
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: _kPriceOrange,
                                      ),
                                    ),
                                  ),
                                ],
                                const Spacer(),
                                // ── Note + nombre de notations, et badge
                                // "ventes" séparé et plus visible. ──
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (rating > 0)
                                      GestureDetector(
                                        onTap: _scrollToReviews,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.star_rounded, size: 15, color: Color(0xFFFFC107)),
                                            const SizedBox(width: 2),
                                            Text(
                                              rating.toStringAsFixed(1),
                                              style: const TextStyle(
                                                fontFamily: 'Cairo',
                                                fontSize: 14,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF1A1A1A),
                                              ),
                                            ),
                                            if (ratingCount > 0)
                                              Text(
                                                ' ($ratingCount)',
                                                style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, color: Colors.grey[600]),
                                              ),
                                          ],
                                        ),
                                      ),
                                    if (salesCount > 0) ...[
                                      if (rating > 0) const SizedBox(height: 4),
                                      _SalesBadge(label: '${_formatSold(salesCount)} vendus'),
                                    ],
                                  ],
                                ),
                              ],
                            ),

                            if (outOfStock) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE53935).withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Center(
                                  child: Text(
                                    'Rupture de stock',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFE53935),
                                    ),
                                  ),
                                ),
                              ),
                            ],

                            const Divider(height: 32),

                            // ── Quantité ──
                            if (!outOfStock) ...[
                              const Text(
                                'Quantité',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1A1A1A),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  _qtyBtn(Icons.remove_rounded, () {
                                    if (quantity > 1) setState(() => quantity--);
                                  }),
                                  Container(
                                    width: 48,
                                    alignment: Alignment.center,
                                    child: Text(
                                      '$quantity',
                                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 18, fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                  _qtyBtn(Icons.add_rounded, () {
                                    if (stock == null || quantity < stock) {
                                      setState(() => quantity++);
                                    }
                                  }),
                                ],
                              ),
                              const SizedBox(height: 24),
                            ],

                            // ── Couleur (si dispo dans Firestore) ──
                            if (colors.isNotEmpty) ...[
                              const Text(
                                'Couleur',
                                style: TextStyle(fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: List.generate(colors.length, (i) {
                                  final selected = (_selectedColorIndex ?? 0) == i;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: GestureDetector(
                                      onTap: () => setState(() => _selectedColorIndex = i),
                                      child: Container(
                                        width: 34,
                                        height: 34,
                                        decoration: BoxDecoration(
                                          color: _parseColor(colors[i]),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: selected ? AppColors.primary : Colors.grey[300]!,
                                            width: selected ? 3 : 1,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                              const SizedBox(height: 22),
                            ],

                            // ── Type / variante (si dispo dans Firestore) ──
                            if (types.isNotEmpty) ...[
                              const Text(
                                'Type',
                                style: TextStyle(fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: List.generate(types.length, (i) {
                                  final selected = (_selectedTypeIndex ?? 0) == i;
                                  return GestureDetector(
                                    onTap: () => setState(() => _selectedTypeIndex = i),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: selected ? AppColors.primary : Colors.white,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: selected ? AppColors.primary : const Color(0xFFE0E0E0)),
                                      ),
                                      child: Text(
                                        types[i],
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: selected ? Colors.white : const Color(0xFF424242),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ── Section avis réels (3 derniers + "voir plus") ──
                  SliverSafeArea(
                    top: false,
                    sliver: SliverToBoxAdapter(
                      key: _reviewsKey,
                      child: _ReviewsSection(productId: widget.productId, rating: rating, reviewCount: reviewCount),
                    ),
                  ),

                  // ── Produits similaires (même catégorie, produit actuel exclu) ──
                  if (category.isNotEmpty)
                    SliverSafeArea(
                      top: false,
                      sliver: SliverToBoxAdapter(
                        child: _SimilarProductsSection(category: category, excludeProductId: widget.productId),
                      ),
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              );
            },
          ),
        ),
        bottomNavigationBar: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('products').doc(widget.productId).snapshots(),
            builder: (context, snap) {
              if (!snap.hasData || !snap.data!.exists) return const SizedBox();
              final product = snap.data!.data() as Map<String, dynamic>;
              final price = _p(product['price']);
              final stock = (product['stock'] as num?)?.toInt();
              final outOfStock = stock != null && stock <= 0;

              return SafeArea(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, -4)),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Total', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.grey[600])),
                            Text(
                              '${(price * quantity).toStringAsFixed((price * quantity) % 1 == 0 ? 0 : 1)} DH',
                              style: const TextStyle(fontFamily: 'Cairo', fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 200,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: outOfStock ? null : () => _addToCart(product),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            disabledBackgroundColor: Colors.grey[300],
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                          icon: Icon(_justAdded ? Icons.check_rounded : Icons.add_shopping_cart_rounded, size: 19),
                          label: Text(
                            outOfStock ? 'Indisponible' : 'Ajouter au panier',
                            style: const TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ),
    );
  }


  Widget _qtyBtn(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE0E0E0)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: const Color(0xFF424242), size: 18),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  BADGE VENTES — pastille compacte et professionnelle pour salesCount.
// ─────────────────────────────────────────────────────────────────────────────
class _SalesBadge extends StatelessWidget {
  final String label;
  const _SalesBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFE0B2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department_rounded, size: 12, color: _kPriceOrange),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFFE65100),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  BARRE "LIVRAISON / BIO / GARANTIE" — v2, nouveau design.
//  Ancien style (3 colonnes avec icônes en cercle + séparateurs verticaux)
//  remplacé par un ruban compact en dégradé, une seule ligne, avec
//  puces • entre chaque item — plus discret, plus proche d'un bandeau de
//  réassurance e-commerce (type "checkout trust ribbon").
// ─────────────────────────────────────────────────────────────────────────────
class _TrustBar extends StatelessWidget {
  const _TrustBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.78)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(child: _TrustChip(icon: Icons.local_shipping_outlined, label: 'Livraison gratuite')),
          _TrustDot(),
          Flexible(child: _TrustChip(icon: Icons.eco_outlined, label: '100% Bio')),
          _TrustDot(),
          Flexible(child: _TrustChip(icon: Icons.verified_outlined, label: 'Qualité garantie')),
        ],
      ),
    );
  }
}

class _TrustChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _TrustChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _TrustDot extends StatelessWidget {
  const _TrustDot();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Container(
        width: 3,
        height: 3,
        decoration: const BoxDecoration(color: Colors.white70, shape: BoxShape.circle),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  GALERIE D'IMAGES — PageView avec dégradé haut (contraste barre système),
//  indicateurs à points et flèches latérales indiquant qu'on peut glisser.
//  Chaque image reçoit un fond blanc opaque : les photos à fond transparent
//  ne "fuitent" plus derrière les icônes système lors du scroll.
// ─────────────────────────────────────────────────────────────────────────────
class _ImageGallery extends StatelessWidget {
  final List<String> images;
  final PageController controller;
  final int currentIndex;
  final ValueChanged<int> onPageChanged;

  const _ImageGallery({
    required this.images,
    required this.controller,
    required this.currentIndex,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return Container(
        color: Colors.grey[200],
        child: const Icon(Icons.image_not_supported_rounded, size: 80, color: Colors.grey),
      );
    }

    return Container(
      // Fond blanc opaque systématique derrière toute la galerie : les
      // images à fond transparent gardent un rendu propre et cohérent,
      // et les icônes système (foncées) restent toujours lisibles.
      color: Colors.white,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: controller,
            itemCount: images.length,
            onPageChanged: onPageChanged,
            itemBuilder: (_, i) => Container(
              color: Colors.white,
              child: CachedNetworkImage(
                imageUrl: images[i],
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: const Color(0xFFF0F0F0),
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: Colors.grey[200],
                  child: const Icon(Icons.image_not_supported_rounded, size: 80, color: Colors.grey),
                ),
              ),
            ),
          ),

          if (images.length > 1) ...[
            // Flèches latérales : indiquent explicitement qu'on peut glisser.
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _GalleryArrow(
                  icon: Icons.chevron_left_rounded,
                  visible: currentIndex > 0,
                  onTap: () => controller.previousPage(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOut,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _GalleryArrow(
                  icon: Icons.chevron_right_rounded,
                  visible: currentIndex < images.length - 1,
                  onTap: () => controller.nextPage(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOut,
                  ),
                ),
              ),
            ),

            // Indicateurs à points en bas de l'image.
            Positioned(
              bottom: 14,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(images.length, (i) {
                  final active = i == currentIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active ? AppColors.primary : Colors.black.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GalleryArrow extends StatelessWidget {
  final IconData icon;
  final bool visible;
  final VoidCallback onTap;
  const _GalleryArrow({required this.icon, required this.visible, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: visible ? 1 : 0.25,
      child: GestureDetector(
        onTap: visible ? onTap : null,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.28),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  CIRCLE ICON BUTTON
// ─────────────────────────────────────────────────────────────────────────────
class _CircleIconBtn extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  const _CircleIconBtn({required this.icon, required this.onTap, this.iconColor = Colors.black});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(6),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6)],
            ),
            child: Icon(icon, size: 17, color: iconColor),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  NOT FOUND VIEW
// ─────────────────────────────────────────────────────────────────────────────
class _NotFoundView extends StatelessWidget {
  const _NotFoundView();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black),
            onPressed: () => context.pop(),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('😕', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 12),
                const Text(
                  'Produit introuvable',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  REVIEWS SECTION — lit les avis réels depuis la sous-collection Firestore
//  products/{productId}/reviews (ex: products/{id}/reviews/APWdbg7SAHSBzSSI53vD).
//  N'affiche que les 3 derniers avis avec un bouton "Voir plus".
//
//  ⚠️ Si cette section reste vide malgré des avis existants en base, la
//  cause la plus probable est une Firestore rule manquante pour cette
//  sous-collection : une règle "allow read: if true" sur /products/{id}
//  ne s'applique PAS automatiquement à /products/{id}/reviews. Il faut une
//  règle dédiée, ex. :
//    match /products/{productId}/reviews/{reviewId} {
//      allow read: if true;
//      allow write: if false;
//    }
// ─────────────────────────────────────────────────────────────────────────────
class _ReviewsSection extends StatelessWidget {
  final String productId;
  final double rating;
  final int reviewCount;
  const _ReviewsSection({required this.productId, required this.rating, required this.reviewCount});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Avis clients',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A)),
              ),
              const SizedBox(width: 8),
              if (reviewCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    '★ ${rating.toStringAsFixed(1)}',
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFFFF8F00)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('products')
                .doc(productId)
                .collection('reviews')
                .orderBy('createdAt', descending: true)
                .limit(50)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              if (snap.hasError) {
                // Distingue clairement une erreur (souvent des Firestore
                // rules manquantes) d'une absence réelle d'avis.
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'Impossible de charger les avis',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.grey[500]),
                    ),
                  ),
                );
              }
              if (!snap.hasData || snap.data!.docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text('Aucun avis pour le moment', style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.grey[500])),
                  ),
                );
              }
              return _ReviewsList(docs: snap.data!.docs);
            },
          ),
        ],
      ),
    );
  }
}

class _ReviewsList extends StatefulWidget {
  final List<QueryDocumentSnapshot> docs;
  const _ReviewsList({required this.docs});

  @override
  State<_ReviewsList> createState() => _ReviewsListState();
}

class _ReviewsListState extends State<_ReviewsList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final docs = widget.docs;
    final visible = _expanded ? docs : docs.take(3).toList();

    return Column(
      children: [
        ...visible.map((doc) => _ReviewTile(review: doc.data() as Map<String, dynamic>)),
        if (docs.length > 3)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(
                _expanded ? 'Voir moins' : 'Voir plus (${docs.length - 3})',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  NOM AFFICHÉ — le champ "userName" est désormais écrit directement sur
//  chaque review au moment de sa création (voir review_dialog.dart :
//  _OrderReviewDialogState._submit / _applyProductRating), en copiant le
//  "fullname" du client depuis SA PROPRE commande, à l'instant précis où
//  les security rules l'y autorisent encore. On n'a donc plus besoin ici
//  de requête Firestore supplémentaire ni d'index composite : on lit
//  simplement "userName" sur le document déjà chargé, et on l'affiche
//  masqué (5 premiers caractères + points, ex: "Moham•••").
//
//  Pour les avis créés AVANT ce changement (qui n'ont donc pas de
//  "userName" enregistré), l'affichage retombe simplement sur "Client".
// ─────────────────────────────────────────────────────────────────────────────
class _ReviewTile extends StatelessWidget {
  final Map<String, dynamic> review;
  const _ReviewTile({required this.review});

  // Garde les 5 premiers caractères du nom et masque le reste avec des
  // points, façon "Moham•••" — rendu personnalisé sans exposer le nom
  // complet.
  String _maskUserName(String rawName) {
    final name = rawName.trim();
    if (name.isEmpty) return 'Client';
    if (name.length <= 5) return name;
    final visible = name.substring(0, 5);
    final hiddenCount = name.length - 5;
    final dots = '•' * hiddenCount.clamp(3, 6);
    return '$visible$dots';
  }

  @override
  Widget build(BuildContext context) {
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final comment = review['comment']?.toString() ?? '';
    final rawName = review['userName']?.toString() ?? '';
    final displayName = _maskUserName(rawName);
    final photoUrl = review['userPhotoUrl']?.toString() ?? '';
    final photos = (review['images'] as List?)?.cast<String>() ?? [];
    final createdAt = (review['createdAt'] as Timestamp?)?.toDate();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFF7F8F7), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipOval(
                child: photoUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: photoUrl,
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _initialAvatar(displayName),
                      )
                    : _initialAvatar(displayName),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName, style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.w700)),
                    if (createdAt != null)
                      Text(_relativeDate(createdAt), style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.grey[500])),
                  ],
                ),
              ),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < rating ? Icons.star_rounded : Icons.star_border_rounded,
                    size: 13,
                    color: const Color(0xFFFFC107),
                  ),
                ),
              ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(comment, style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.grey[800], height: 1.4)),
          ],
          if (photos.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: photos[i],
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(width: 64, height: 64, color: Colors.grey[300]),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _initialAvatar(String name) => Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.15), shape: BoxShape.circle),
        child: Center(
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary),
          ),
        ),
      );

  String _relativeDate(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays > 30) return '${(diff.inDays / 30).floor()} mois';
    if (diff.inDays > 0) return '${diff.inDays}j';
    if (diff.inHours > 0) return '${diff.inHours}h';
    return 'À l\'instant';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SIMILAR PRODUCTS SECTION — même catégorie, produit actuel exclu
// ─────────────────────────────────────────────────────────────────────────────
class _SimilarProductsSection extends StatelessWidget {
  final String category;
  final String excludeProductId;
  const _SimilarProductsSection({required this.category, required this.excludeProductId});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 16),
            child: Text(
              'Produits similaires',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A)),
            ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('products')
                .where('category', isEqualTo: category)
                .where('isAvailable', isEqualTo: true)
                .limit(10)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              if (!snap.hasData) {
                return const SizedBox(height: 8);
              }

              final docs = snap.data!.docs.where((d) => d.id != excludeProductId).toList();

              if (docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(right: 16, bottom: 8),
                  child: Text(
                    'Aucun autre produit dans cette catégorie',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.grey[500]),
                  ),
                );
              }

              return SizedBox(
                height: 235,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(right: 16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    return _SimilarProductCard(productId: docs[i].id, data: data);
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SimilarProductCard extends StatelessWidget {
  final String productId;
  final Map<String, dynamic> data;
  const _SimilarProductCard({required this.productId, required this.data});

  double _p(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final price = _p(data['price']);
    final oldPrice = _p(data['oldPrice']);
    final hasDiscount = oldPrice > price && oldPrice > 0;
    final name = data['name']?.toString() ?? '';
    final imageUrl = data['imageUrl']?.toString() ?? '';
    final stock = (data['stock'] as num?)?.toInt();
    final outOfStock = stock != null && stock <= 0;

    return GestureDetector(
      onTap: () {
        context.pushReplacement('/product/$productId');
      },
      child: Container(
        width: 150,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEDEDED)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(height: 120, color: const Color(0xFFF0F0F0)),
                    errorWidget: (_, __, ___) => Container(
                      height: 120,
                      color: Colors.grey[200],
                      child: const Icon(Icons.image_not_supported_rounded, color: Colors.grey),
                    ),
                  ),
                ),
                if (outOfStock)
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Indisponible',
                        style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '${price.toStringAsFixed(price % 1 == 0 ? 0 : 1)} DH',
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black),
                      ),
                      if (hasDiscount) ...[
                        const SizedBox(width: 6),
                        Text(
                          '${oldPrice.toStringAsFixed(oldPrice % 1 == 0 ? 0 : 1)} DH',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            color: Color(0xFF9E9E9E),
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}