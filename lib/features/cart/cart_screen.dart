// TODO Implement this library.// TODO Implement this library.// lib/features/cart/cart_screen.dart
//
// ─────────────────────────────────────────────────────────────────────────────
//  SCHÉMA FIRESTORE UTILISÉ ICI (contrat partagé avec le dashboard admin)
// ─────────────────────────────────────────────────────────────────────────────
//
//  carts/{uid}/items/{productId}
//      productId : String
//      qty       : int
//      addedAt   : Timestamp
//      (le prix et le nom NE SONT JAMAIS stockés ici — toujours lus en live
//       depuis products/{id} pour éviter un prix obsolète)
//
//  carts/{uid}/items/{formuleId}   (type: 'formule' — voir formules_screen.dart)
//      type                 : 'formule'
//      formuleId            : String  (ex: "formulesBeldi")
//      formuleTitle         : String
//      formuleImageUrl      : String
//      unitPrice            : num     // prix actuel de la formule (tient compte
//                                     //  des produits que le client a retirés)
//      originalPrice        : num     // somme des prix individuels d'origine
//      includedProductIds   : List<String>
//      removedProductIds    : List<String>  // 2 max, retirés par le client
//      quantity             : int
//      addedAt              : Timestamp
//
//  products/{id}
//      name, price, oldPrice, imageUrl, stock (int), salesCount (int),
//      category (String)   // utilisé pour les recommandations "produits similaires"
//
//  orders/{orderId}
//      userId          : String
//      items           : List<Map>  [{productId,name,price,qty,imageUrl,subtotal}]
//      subtotal        : double
//      deliveryFee     : double        // ✏️ toujours 0.0 désormais (livraison gratuite)
//      redeemedPoints  : int           // ✏️ NOUVEAU — points Graine échangés sur cette commande
//      pointsDiscount  : double        // ✏️ NOUVEAU — montant DH de la réduction correspondante
//      total           : double        // = subtotal - pointsDiscount + deliveryFee
//      paymentMethod   : "cod"                       // fixe (paiement à la livraison)
//      status          : pending|confirmed|preparing|shipped|delivered|cancelled
//      statusHistory   : List<Map> [{status, at}]     // écrit par le dashboard admin
//      deliveryAddress : {fullName, phone, city, address, notes}
//      createdAt       : Timestamp
//      updatedAt       : Timestamp
//
//  users/{uid}
//      points          : int      // système de points "Graine"
//      negativePoints  : int      // ✏️ NOUVEAU — cumul HISTORIQUE (jamais décrémenté) de tous
//                                 //    les points déjà échangés contre une réduction, tous temps
//                                 //    confondus. Sert de compteur analytique côté dashboard admin
//                                 //    (ex. "combien de points ont été dépensés en réductions au
//                                 //    total"), à ne pas confondre avec `points` qui, lui, diminue
//                                 //    à chaque échange. Ex. un client échange 5 points sur une
//                                 //    commande : `points -= 5` ET `negativePoints += 5`.
//      hasUnlockedTree : bool
//
//  ⚠️ RÈGLE D'OR : cette app n'écrit JAMAIS `status` après création de la
//  commande (sauf passage à "cancelled" si l'utilisateur annule). Le champ
//  est piloté exclusivement par le dashboard admin (autre application),
//  et cette app se contente d'écouter (snapshots) pour refléter le changement
//  en temps réel.
//
//  ⚠️ IMPORTANT POUR L'ÉCRAN CHECKOUT : lorsque `redeemedPoints > 0` est
//  transmis via `context.push('/checkout', extra: {...})`, l'écran de
//  checkout est responsable de :
//    1) décrémenter `users/{uid}.points` de `redeemedPoints` au moment de
//       la création effective de la commande (transaction Firestore
//       recommandée pour éviter une double dépense en cas de double tap) ;
//    2) INCRÉMENTER `users/{uid}.negativePoints` de `redeemedPoints` dans
//       la MÊME transaction (cumul historique, ne diminue jamais) ;
//    3) stocker `redeemedPoints` et `pointsDiscount` sur le document
//       `orders/{orderId}` pour traçabilité.
//  Cet écran (cart_screen.dart) ne fait QUE calculer et proposer la
//  réduction — il n'écrit jamais dans `users/{uid}.points` ni
//  `users/{uid}.negativePoints`.
//
//  ─────────────────────────────────────────────────────────────────────────
//  NOUVEAU DANS CETTE VERSION
//  ─────────────────────────────────────────────────────────────────────────
//  • AFFICHAGE DES FORMULES DANS LE PANIER : un article de type 'formule'
//    (ajouté depuis formules_screen.dart) s'affiche désormais comme UNE
//    seule carte "Formule {Titre} · +N produits", avec un badge coloré
//    reprenant l'identité de la formule (Beldi / Healthy / Saison). Un tap
//    sur la carte ouvre une popup centrée listant tous les produits inclus,
//    avec une case à cocher par produit (max 2 retraits, comme sur l'écran
//    Formules) et un bouton "✕" en haut pour fermer.
//  • Livraison désormais TOUJOURS gratuite (`deliveryFee` fixé à 0.0). Tout
//    l'ancien mécanisme de "livraison gratuite dès X DH" (barre de
//    progression, comparaison au seuil) a été retiré.
//  • Ajout d'un MONTANT MINIMUM DE COMMANDE (`minOrderAmount` = 99 DH) : le
//    bouton "Commander" reste désactivé et un message + barre de progression
//    informent l'utilisateur du montant restant à ajouter tant que le
//    sous-total sélectionné est inférieur à ce seuil.
//  • Ajout du SYSTÈME D'ÉCHANGE DE POINTS GRAINE CONTRE UNE RÉDUCTION :
//      - 1 point Graine = 1.5 DH de réduction (seedValueDh).
//      - Le bouton n'apparaît QUE si le solde de l'utilisateur dépasse
//        l'équivalent de 20 DH (soit ≥ 14 points), pour éviter un usage
//        dérisoire / une mauvaise expérience.
//      - (v4) DOUBLE PLAFOND sur la réduction, appliqué de façon cumulée :
//          a) jamais plus de 30% du sous-total de la sélection en cours,
//             quel que soit le solde de points détenu ;
//          b) le prix final après réduction ne peut JAMAIS descendre en
//             dessous du montant minimum de commande (`minOrderAmount`,
//             99 DH) — la réduction ne doit jamais permettre de contourner
//             ce seuil.
//        Le plafond retenu est le plus restrictif des deux (voir
//        `_maxDiscountAllowed`), et le slider du bottom sheet est borné en
//        conséquence.
//      - (v4) Bottom sheet REFAIT : le slider représente désormais
//        directement le PRIX DE LA COMMANDE (piste orange). Le client "tire
//        la piste vers l'arrière" (vers la gauche) pour faire baisser le
//        prix, qui s'affiche en direct au-dessus du curseur (bulle de
//        valeur) et en grand au-dessus du slider. Le curseur ne peut pas
//        descendre plus bas que le prix plancher autorisé par le double
//        plafond ci-dessus : arrivé à l'extrémité gauche, la réduction
//        maximale est atteinte et il est physiquement impossible d'aller
//        plus loin.
//      - (v4) Le bouton d'accès à l'échange est désormais un bouton
//        "Offre spéciale" pulsant (fond blanc, contour et texte orange,
//        fines rayures façon confettis en fond) pour capter l'attention,
//        au lieu d'un simple texte "Utiliser".
//  • REFONTE VISUELLE DU SYSTÈME DE POINTS (v2) : l'icône de la pièce
//    "Graine" est désormais l'image `assets/images/coins.png`
//    (au lieu du CustomPainter dessiné à la main), posée sur un médaillon
//    doré en dégradé pour lui donner du relief. Un compteur animé
//    (`_AnimatedSeedCount`) avec un petit effet de "burst" façon jeu vidéo
//    (particules + label "+N" flottant) joue automatiquement dès que le
//    solde de points de l'utilisateur augmente (ex. commande livrée).
//  • (v3) ÉCRAN PANIER VIDE : ajout d'un bandeau `_CompactOrdersBanner`
//    discret (une seule ligne, pas de carrousel) qui informe l'utilisateur
//    s'il a des commandes en cours — sans jamais monopoliser l'écran, dont
//    l'objectif reste d'inciter à un nouvel achat. Corrige aussi un bug où
//    `_EmptyCartState` recevait toujours un `uid` vide (`''`), rendant toute
//    requête utilisateur sur cet écran impossible.
//  • (v5) ÉCRAN PANIER — VISITEUR : le bandeau informatif neutre a été
//    remplacé par `_GuestLoginTeaserBanner` (message orienté "perte
//    potentielle" + effets shimmer/pulse) et le bouton de connexion en bas
//    par `_GuestLoginGiftButton` ("Se connecter" → "Recevez vos cadeaux"),
//    tous deux conçus pour inciter psychologiquement à la connexion.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mrbeldi/core/services/local_cart_service.dart';
import 'package:mrbeldi/core/theme/app_colors.dart';

/// Parse robuste : certains champs numériques peuvent être stockés côté
/// Firestore comme String au lieu d'un number. N'échoue jamais.
double _parsePrice(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim().replaceAll(',', '.')) ?? 0;
  return 0;
}

int? _parseIntOrNull(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

int _parseInt(dynamic v) => _parseIntOrNull(v) ?? 0;

/// Habillage couleur/emoji par formule — même logique que dans
/// formules_screen.dart (dupliquée ici volontairement pour ne pas coupler
/// les deux écrans ; garde les mêmes mots-clés si tu ajoutes une formule).
Color formuleAccentColor(String idOrTitle) {
  final t = idOrTitle.toLowerCase();
  if (t.contains('beldi')) return const Color(0xFF8B4513);
  if (t.contains('healthy') || t.contains('sain') || t.contains('helthy')) {
    return const Color(0xFF2E7D32);
  }
  if (t.contains('saison')) return const Color(0xFF7B1E3D);
  return AppColors.primaryDark;
}

String formuleEmoji(String idOrTitle) {
  final t = idOrTitle.toLowerCase();
  if (t.contains('beldi')) return '🌾';
  if (t.contains('healthy') || t.contains('sain') || t.contains('helthy')) {
    return '🥗';
  }
  if (t.contains('saison')) return '🍂';
  return '🌿';
}

// ─────────────────────────────────────────────────────────────────────────────
//  CART SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class CartScreen extends StatefulWidget {
  const CartScreen({super.key});
  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  // ✏️ Montant minimum de commande (livraison étant désormais toujours
  //    gratuite, ce seuil remplace l'ancien seuil de "livraison gratuite").
  static const double minOrderAmount = 99.0;

  // Sélection multiple pour suppression / commande partielle
  final Set<String> _selectedIds = {};
  bool _selectAll = true;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  CollectionReference get _itemsRef => FirebaseFirestore.instance
      .collection('carts')
      .doc(_uid)
      .collection('items');

  // ── Mettre à jour la quantité (article produit standard) ──
  Future<void> _updateQty(String productId, int newQty) async {
    if (_uid == null) return;
    if (newQty <= 0) {
      await _itemsRef.doc(productId).delete();
      setState(() => _selectedIds.remove(productId));
    } else {
      await _itemsRef.doc(productId).update({'qty': newQty});
    }
  }

  // ── Mettre à jour la quantité d'une FORMULE (champ 'quantity', pas 'qty') ──
  Future<void> _updateFormuleQty(String cartItemId, int newQty) async {
    if (_uid == null) return;
    if (newQty <= 0) {
      await _itemsRef.doc(cartItemId).delete();
      setState(() => _selectedIds.remove(cartItemId));
    } else {
      await _itemsRef.doc(cartItemId).update({'quantity': newQty});
    }
  }

  Future<void> _removeItem(String productId) async {
    if (_uid == null) return;
    HapticFeedback.lightImpact();
    await _itemsRef.doc(productId).delete();
    if (mounted) setState(() => _selectedIds.remove(productId));
  }

  void _confirmRemove(String productId, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Retirer cet article ?',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
        content: Text('« $name » sera retiré de votre panier.',
            style: const TextStyle(fontFamily: 'Cairo', fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler',
                style: TextStyle(fontFamily: 'Cairo', color: Color(0xFF757575))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _removeItem(productId);
            },
            child: const Text('Retirer',
                style: TextStyle(fontFamily: 'Cairo', color: Color(0xFFE53935),
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _toggleSelectAll(List<String> allIds) {
    setState(() {
      if (_selectAll) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(allIds);
      }
      _selectAll = !_selectAll;
    });
  }

  @override
  Widget build(BuildContext context) {
     if (_uid == null) {
    return const _GuestCartScreen(); // ✏️ بدل const _EmptyLoginState()
  }
  return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        centerTitle: false,
        title: const Text('Mon panier',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A1A), fontSize: 18)),
        actions: [
          TextButton(
            onPressed: () => context.push('/orders'),
            child: Text('Mes commandes',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600,
                    color: AppColors.primary, fontSize: 13)),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _itemsRef.orderBy('addedAt', descending: true).snapshots(),
        builder: (context, cartSnap) {
          if (cartSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (cartSnap.hasError) {
            return _ErrorState(
              message: 'Impossible de charger votre panier.',
              onRetry: () => setState(() {}),
            );
          }
          if (!cartSnap.hasData || cartSnap.data!.docs.isEmpty) {
            // Panier vide : on affiche quand même un écran utile
            // (bandeau discret "commandes en cours" si applicable, badges de
            // confiance + meilleures ventes) au lieu d'un écran "mort" sans
            // information ni suggestion.
            return _EmptyCartState(uid: _uid!);
          }

          final cartDocs = cartSnap.data!.docs;
          final productIds = cartDocs.map((d) => d.id).toList();

          // Sélectionner tout par défaut au premier rendu uniquement,
          // et nettoyer les ids sélectionnés qui ne sont plus dans le panier.
          if (_selectAll) {
            _selectedIds
              ..removeWhere((id) => !productIds.contains(id))
              ..addAll(productIds);
          } else {
            _selectedIds.removeWhere((id) => !productIds.contains(id));
          }

          return Column(
            children: [
              Expanded(
                child: _CartBody(
                  uid: _uid!,
                  cartDocs: cartDocs,
                  selectedIds: _selectedIds,
                  onToggleSelect: (id, val) {
                    setState(() {
                      if (val) {
                        _selectedIds.add(id);
                      } else {
                        _selectedIds.remove(id);
                        _selectAll = productIds.isNotEmpty &&
                productIds.every(_selectedIds.contains);
         
                      }
                    });
                  },
                  onToggleSelectAll: () => _toggleSelectAll(productIds),
                  allSelected: productIds.isNotEmpty &&
                      productIds.every(_selectedIds.contains),
                  onUpdateQty: _updateQty,
                  onUpdateFormuleQty: _updateFormuleQty,
                  onRemove: _confirmRemove,
                ),
              ),
              // ── Barre de résumé fixée en bas (toujours visible) ──
              _CartSummaryBar(
                uid: _uid!,
                cartDocs: cartDocs,
                selectedIds: _selectedIds,
                minOrderAmount: minOrderAmount,
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ÉTAT D'ERREUR GÉNÉRIQUE — réutilisable pour tout StreamBuilder critique
// ─────────────────────────────────────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const _ErrorState({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.wifi_off_rounded, size: 44, color: Color(0xFFBDBDBD)),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13,
                    fontWeight: FontWeight.w700, color: Color(0xFF616161))),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              TextButton(
                onPressed: onRetry,
                child: const Text('Réessayer',
                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
              ),
            ],
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  EMPTY STATES
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
//  ÉCRAN PANIER VIDE — refait pour ne plus être un cul-de-sac.
//  Affiche : message + bouton, badges de confiance, et une section
//  "Nos meilleures ventes" (tri par salesCount) pour donner tout de suite
//  à l'utilisateur des produits pertinents à découvrir.
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyCartState extends StatelessWidget {
  final String uid;
  const _EmptyCartState({required this.uid});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('🌱', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 16),
              const Text('Votre panier est vide',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 16,
                      fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
              const SizedBox(height: 6),
              Text('Découvrez nos produits frais de la ferme',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 13,
                      color: Colors.grey[600])),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => context.go('/home'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Voir les produits',
                    style: TextStyle(fontFamily: 'Cairo', color: Colors.white,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ),

        // ── Bandeau discret "commandes en cours" — n'apparaît QUE s'il y en
        //    a réellement, et reste minimaliste (une seule ligne, pas de
        //    carrousel) pour ne pas monopoliser l'attention sur un écran
        //    qui a pour but principal de pousser vers de nouveaux achats ──
        SliverToBoxAdapter(child: _CompactOrdersBanner(uid: uid)),

        // ── Badges de confiance : même valeur informative qu'un panier plein ──
        const SliverToBoxAdapter(child: _TrustBadgesRow()),

        // ── Meilleures ventes : pour qu'il y ait toujours des suggestions,
        //    même sans historique de commandes ni panier ──
        const SliverToBoxAdapter(child: _BestSellersSection()),

        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  BANDEAU DISCRET "COMMANDES EN COURS" — pour l'écran panier vide.
//  Contrairement à _OrdersInProgressSection (carrousel de cartes détaillées,
//  utilisé quand le panier est plein), ce bandeau reste volontairement
//  minimaliste : une seule ligne compacte, un icône, un compte, une flèche.
//  Il ne s'affiche QUE s'il existe au moins une commande active, et ne prend
//  jamais toute l'attention de l'écran — le but reste d'inciter à racheter.
// ─────────────────────────────────────────────────────────────────────────────
class _CompactOrdersBanner extends StatelessWidget {
  final String uid;
  const _CompactOrdersBanner({required this.uid});

  static const _statusColors = {
    'pending': Color(0xFFFFA000),
    'confirmed': Color(0xFF1565C0),
    'preparing': Color(0xFF7B61FF),
    'shipped': AppColors.primary,
  };

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('userId', isEqualTo: uid)
          .where('status', whereIn: ['pending', 'confirmed', 'preparing', 'shipped'])
          .orderBy('createdAt', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snap) {
        // Silencieux en cas d'erreur (ex. index composite manquant) — ce
        // bandeau est un bonus discret, jamais un écran d'erreur.
        if (snap.hasError || !snap.hasData || snap.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final docs = snap.data!.docs;
        final count = docs.length;
        final atLimit = count >= 5;
        final latestStatus =
            (docs.first.data() as Map<String, dynamic>)['status']?.toString() ??
                'pending';
        final dotColor = _statusColors[latestStatus] ?? Colors.grey;
        final label = count == 1
            ? 'Vous avez 1 commande en cours'
            : 'Vous avez ${atLimit ? '$count+' : '$count'} commandes en cours';

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: GestureDetector(
            onTap: () => context.push('/orders'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
                ),
                const SizedBox(width: 10),
                Icon(Icons.local_shipping_outlined, size: 15, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label,
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12,
                          fontWeight: FontWeight.w700, color: Color(0xFF424242))),
                ),
                Icon(Icons.chevron_right_rounded, size: 17, color: Colors.grey[400]),
              ]),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  CART BODY — lit le prix EN DIRECT depuis `products` pour chaque item
//  (sauf pour les FORMULES, dont le prix est déjà figé sur le document —
//  voir `unitPrice` dans le schéma en haut de fichier).
// ─────────────────────────────────────────────────────────────────────────────
class _CartBody extends StatelessWidget {
  final String uid;
  final List<QueryDocumentSnapshot> cartDocs;
  final Set<String> selectedIds;
  final void Function(String id, bool value) onToggleSelect;
  final VoidCallback onToggleSelectAll;
  final bool allSelected;
  final Future<void> Function(String productId, int newQty) onUpdateQty;
  final Future<void> Function(String cartItemId, int newQty) onUpdateFormuleQty;
  final void Function(String productId, String name) onRemove;

  const _CartBody({
    required this.uid,
    required this.cartDocs,
    required this.selectedIds,
    required this.onToggleSelect,
    required this.onToggleSelectAll,
    required this.allSelected,
    required this.onUpdateQty,
    required this.onUpdateFormuleQty,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final productIds = cartDocs.map((d) => d.id).toList();

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ── Tout sélectionner ──
        SliverToBoxAdapter(
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(children: [
              GestureDetector(
                onTap: onToggleSelectAll,
                child: Row(children: [
                  _CheckCircle(checked: allSelected),
                  const SizedBox(width: 8),
                  Text('Tout sélectionner (${cartDocs.length})',
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 13,
                          fontWeight: FontWeight.w600, color: Color(0xFF424242))),
                ]),
              ),
            ]),
          ),
        ),
        SliverToBoxAdapter(child: Container(height: 1, color: const Color(0xFFEEEEEE))),

        // ── Liste des items ──
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final cartDoc = cartDocs[i];
                final cartData = cartDoc.data() as Map<String, dynamic>;
                final isFormule = cartData['type'] == 'formule';

                // ── Article de type FORMULE : une seule carte, pas de
                //    lecture produit par produit (prix déjà figé). ──
                if (isFormule) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _FormuleCartItemCard(
                      cartItemId: cartDoc.id,
                      data: cartData,
                      isSelected: selectedIds.contains(cartDoc.id),
                      onSelect: (v) => onToggleSelect(cartDoc.id, v),
                      onQtyChange: (newQty) => onUpdateFormuleQty(cartDoc.id, newQty),
                      onRemove: () => onRemove(
                          cartDoc.id, cartData['formuleTitle']?.toString() ?? 'cette formule'),
                    ),
                  );
                }

                final productId = cartDoc.id;
                final qty = _parseInt(cartData['qty']);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('products').doc(productId).snapshots(),
                    builder: (ctx, prodSnap) {
                      if (prodSnap.hasError) {
                        return _CartItemUnavailable(
                          productId: productId,
                          message: 'Erreur de chargement de ce produit',
                          onRemove: () => onRemove(productId, 'ce produit'),
                        );
                      }
                      if (!prodSnap.hasData) {
                        return const _CartItemSkeleton();
                      }
                      if (!prodSnap.data!.exists) {
                        return _CartItemUnavailable(
                          productId: productId,
                          message: "Ce produit n'est plus disponible",
                          onRemove: () => onRemove(productId, 'ce produit'),
                        );
                      }
                      final p = prodSnap.data!.data() as Map<String, dynamic>;
                      final stock = _parseIntOrNull(p['stock']);
                      final outOfStock = stock != null && stock <= 0;

                      return _CartItemCard(
                        productId: productId,
                        product: p,
                        qty: qty,
                        isSelected: selectedIds.contains(productId),
                        outOfStock: outOfStock,
                        maxStock: stock,
                        onSelect: (v) => onToggleSelect(productId, v),
                        onQtyChange: (newQty) => onUpdateQty(productId, newQty),
                        onRemove: () => onRemove(
                            productId, p['name']?.toString() ?? 'ce produit'),
                      );
                    },
                  ),
                );
              },
              childCount: cartDocs.length,
            ),
          ),
        ),

        // ── Bandeau teaser points Graine (discret, varie selon le panier) ──
        SliverToBoxAdapter(
          child: _LoyaltyTeaser(uid: uid, cartDocs: cartDocs, productIds: productIds),
        ),

        // ── Badges de confiance ──
        const SliverToBoxAdapter(child: _TrustBadgesRow()),

        // ── Commandes en cours ──
        SliverToBoxAdapter(child: _OrdersInProgressSection(uid: uid)),

        // ── Produits recommandés (même catégorie) ──
        SliverToBoxAdapter(
          child: _RecommendedProductsSection(
            uid: uid,
            cartProductIds: productIds,
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 4)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  CARTE ARTICLE "FORMULE" — affichée comme un produit unique
//  ("Formule Healthy · +4 produits"), tap → popup avec le détail.
// ─────────────────────────────────────────────────────────────────────────────
class _FormuleCartItemCard extends StatelessWidget {
  final String cartItemId;
  final Map<String, dynamic> data;
  final bool isSelected;
  final ValueChanged<bool> onSelect;
  final ValueChanged<int> onQtyChange;
  final VoidCallback onRemove;

  const _FormuleCartItemCard({
    required this.cartItemId,
    required this.data,
    required this.isSelected,
    required this.onSelect,
    required this.onQtyChange,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final title = data['formuleTitle']?.toString() ?? 'Formule';
    final formuleId = data['formuleId']?.toString() ?? title;
    final imageUrl = data['formuleImageUrl']?.toString() ?? '';
    final unitPrice = _parsePrice(data['unitPrice']);
    final originalPrice = _parsePrice(data['originalPrice']);
    final includedIds = (data['includedProductIds'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final removedIds = (data['removedProductIds'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final qty = _parseInt(data['quantity']);
    final accent = formuleAccentColor(formuleId);
    final emoji = formuleEmoji(formuleId);
    final hasDiscount = originalPrice > unitPrice && originalPrice > 0;

    return GestureDetector(
      onTap: () => showFormuleContentsDialog(
        context: context,
        cartItemId: cartItemId,
        title: title,
        accent: accent,
        emoji: emoji,
        initialIncluded: includedIds,
        initialRemoved: removedIds,
        initialUnitPrice: unitPrice,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.25)),
          boxShadow: [BoxShadow(
              color: AppColors.shadow, blurRadius: 8, offset: const Offset(0, 3))],
        ),
        padding: const EdgeInsets.all(10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Sélection ──
          GestureDetector(
            onTap: () => onSelect(!isSelected),
            child: Padding(
              padding: const EdgeInsets.only(top: 28, right: 8),
              child: _CheckCircle(checked: isSelected),
            ),
          ),

          // ── Image ──
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: imageUrl, width: 72, height: 72, fit: BoxFit.cover,
              placeholder: (_, __) => Container(width: 72, height: 72,
                  color: accent.withValues(alpha: 0.08)),
              errorWidget: (_, __, ___) => Container(width: 72, height: 72,
                  color: accent.withValues(alpha: 0.08),
                  child: Center(child: Text(emoji, style: const TextStyle(fontSize: 26)))),
            ),
          ),
          const SizedBox(width: 10),

          // ── Infos ──
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration:
                        BoxDecoration(color: accent, borderRadius: BorderRadius.circular(6)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(emoji, style: const TextStyle(fontSize: 10)),
                      const SizedBox(width: 3),
                      const Text('Formule',
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 9.5,
                              fontWeight: FontWeight.w800, color: Colors.white)),
                    ]),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 13,
                            fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                  ),
                  GestureDetector(
                    onTap: onRemove,
                    child: Container(
                      width: 26, height: 26,
                      margin: const EdgeInsets.only(left: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.delete_outline_rounded,
                          size: 15, color: AppColors.error),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Row(children: [
                Icon(Icons.inventory_2_outlined, size: 12, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text('+${includedIds.length} produits inclus',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 11,
                        fontWeight: FontWeight.w600, color: Colors.grey[600])),
                const Spacer(),
                Icon(Icons.touch_app_outlined, size: 12, color: accent),
                const SizedBox(width: 2),
                Text('Voir le contenu',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 10.5,
                        fontWeight: FontWeight.w700, color: accent)),
              ]),

              if (hasDiscount) ...[
                const SizedBox(height: 4),
                Row(children: [
                  Text('${originalPrice.toStringAsFixed(originalPrice % 1 == 0 ? 0 : 1)} DH',
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 11,
                          color: Color(0xFF9E9E9E),
                          decoration: TextDecoration.lineThrough)),
                  const SizedBox(width: 5),
                  Text(
                      '-${(originalPrice - unitPrice).toStringAsFixed((originalPrice - unitPrice) % 1 == 0 ? 0 : 1)} DH',
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 10,
                          fontWeight: FontWeight.w700, color: Color(0xFF43A047))),
                ]),
              ],

              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${unitPrice.toStringAsFixed(unitPrice % 1 == 0 ? 0 : 1)} DH',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 15,
                          fontWeight: FontWeight.w800, color: accent)),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE0E0E0)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _StepperBtn(
                        icon: Icons.remove_rounded,
                        onTap: () => onQtyChange(qty - 1),
                      ),
                      Container(
                        constraints: const BoxConstraints(minWidth: 28),
                        alignment: Alignment.center,
                        child: Text('$qty',
                            style: const TextStyle(fontFamily: 'Cairo',
                                fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                      _StepperBtn(
                        icon: Icons.add_rounded,
                        onTap: () => onQtyChange(qty + 1),
                      ),
                    ]),
                  ),
                ],
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  POPUP "CONTENU DE LA FORMULE" — centrée, fond assombri, croix pour
//  fermer. Liste tous les produits inclus avec une case à cocher (max 2
//  retraits au total, comme sur formules_screen.dart) ; chaque changement
//  est enregistré immédiatement sur le document du panier.
// ─────────────────────────────────────────────────────────────────────────────
void showFormuleContentsDialog({
  required BuildContext context,
  required String cartItemId,
  required String title,
  required Color accent,
  required String emoji,
  required List<String> initialIncluded,
  required List<String> initialRemoved,
  required double initialUnitPrice,
}) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Fermer',
    barrierColor: Colors.black.withValues(alpha: 0.5),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, __, ___) => _FormuleContentsSheet(
      cartItemId: cartItemId,
      title: title,
      accent: accent,
      emoji: emoji,
      initialIncluded: initialIncluded,
      initialRemoved: initialRemoved,
      initialUnitPrice: initialUnitPrice,
    ),
    transitionBuilder: (ctx, anim, __, child) => ScaleTransition(
      scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
      child: FadeTransition(opacity: anim, child: child),
    ),
  );
}

class _FormuleContentsSheet extends StatefulWidget {
  final String cartItemId;
  final String title;
  final Color accent;
  final String emoji;
  final List<String> initialIncluded;
  final List<String> initialRemoved;
  final double initialUnitPrice;

  const _FormuleContentsSheet({
    required this.cartItemId,
    required this.title,
    required this.accent,
    required this.emoji,
    required this.initialIncluded,
    required this.initialRemoved,
    required this.initialUnitPrice,
  });

  @override
  State<_FormuleContentsSheet> createState() => _FormuleContentsSheetState();
}

class _FormuleContentsSheetState extends State<_FormuleContentsSheet> {
  static const int kMaxTotalRemovals = 2;

  late final Set<String> _included = widget.initialIncluded.toSet();
  late final Set<String> _removed = widget.initialRemoved.toSet();
  bool _saving = false;
  double? _ratio; // prix formule ÷ somme des prix des produits inclus

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Future<void> _toggle(String productId, bool checked, Map<String, double> livePrices) async {
    if (!checked &&
        _removed.length >= kMaxTotalRemovals &&
        !_removed.contains(productId)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Vous pouvez retirer au maximum 2 produits de cette formule.',
            style: TextStyle(fontFamily: 'Cairo')),
      ));
      return;
    }

    setState(() {
      if (checked) {
        _included.add(productId);
        _removed.remove(productId);
      } else {
        _included.remove(productId);
        _removed.add(productId);
      }
    });

    if (_uid == null) return;
    setState(() => _saving = true);
    try {
      final ratio = _ratio ?? 1.0;
      final newIncludedSum =
          _included.fold<double>(0, (s, id) => s + (livePrices[id] ?? 0));
      final newUnitPrice = newIncludedSum * ratio;

      await FirebaseFirestore.instance
          .collection('carts')
          .doc(_uid)
          .collection('items')
          .doc(widget.cartItemId)
          .update({
        'includedProductIds': _included.toList(),
        'removedProductIds': _removed.toList(),
        'unitPrice': newUnitPrice,
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: AppColors.error,
          content: Text('Erreur lors de la mise à jour de la formule',
              style: TextStyle(fontFamily: 'Cairo')),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allIds = <String>{..._included, ..._removed}.toList();

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          constraints: const BoxConstraints(maxHeight: 540, maxWidth: 420),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 24, offset: const Offset(0, 12))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // ── En-tête coloré + croix de fermeture ──
            Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 10, 14),
              decoration: BoxDecoration(
                color: widget.accent,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(children: [
                Text(widget.emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Formule ${widget.title}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 15,
                          fontWeight: FontWeight.w800, color: Colors.white)),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        shape: BoxShape.circle),
                    child: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
                  ),
                ),
              ]),
            ),

            // ── Liste des produits ──
            Flexible(
              child: FutureBuilder<List<DocumentSnapshot>>(
                future: Future.wait(allIds.map(
                  (id) => FirebaseFirestore.instance.collection('products').doc(id).get(),
                )),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final docs = snap.data!.where((d) => d.exists).toList();
                  final livePrices = <String, double>{
                    for (final d in docs) d.id: _parsePrice((d.data() as Map)['price']),
                  };

                  // Ratio calculé une seule fois (à partir de l'état initial
                  // reçu de Firestore), puis réutilisé pour tous les
                  // recalculs suivants.
                  if (_ratio == null) {
                    final includedSum = widget.initialIncluded
                        .fold<double>(0, (s, id) => s + (livePrices[id] ?? 0));
                    _ratio = includedSum > 0
                        ? (widget.initialUnitPrice / includedSum).clamp(0, 1)
                        : 1.0;
                  }

                  if (docs.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Aucun produit trouvé pour cette formule.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: 'Cairo', color: Colors.grey[500])),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(14),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final d = docs[i];
                      final p = d.data() as Map<String, dynamic>;
                      final name = p['name']?.toString() ?? '';
                      final imageUrl = p['imageUrl']?.toString() ?? '';
                      final price = _parsePrice(p['price']);
                      final checked = _included.contains(d.id);

                      return Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: checked
                              ? widget.accent.withValues(alpha: 0.05)
                              : Colors.grey.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: checked
                                  ? widget.accent.withValues(alpha: 0.28)
                                  : Colors.grey.withValues(alpha: 0.18)),
                        ),
                        child: Row(children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: imageUrl, width: 48, height: 48, fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(
                                  width: 48, height: 48, color: Colors.grey[200],
                                  child: const Icon(Icons.image_not_supported_outlined,
                                      size: 18, color: Colors.grey)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5,
                                        fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                                const SizedBox(height: 2),
                                Text('${price.toStringAsFixed(price % 1 == 0 ? 0 : 1)} DH',
                                    style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5,
                                        fontWeight: FontWeight.w700, color: widget.accent)),
                              ],
                            ),
                          ),
                          Checkbox(
                            value: checked,
                            activeColor: widget.accent,
                            onChanged: _saving
                                ? null
                                : (v) => _toggle(d.id, v ?? false, livePrices),
                          ),
                        ]),
                      );
                    },
                  );
                },
              ),
            ),

            // ── Pied : info limite de retrait ──
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: Text(
                _removed.length >= kMaxTotalRemovals
                    ? 'Limite de retrait atteinte (2 produits max)'
                    : 'Vous pouvez encore retirer ${kMaxTotalRemovals - _removed.length} produit(s) si besoin',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Cairo', fontSize: 10.5, color: Colors.grey[500]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  CHECK CIRCLE — case à cocher custom
// ─────────────────────────────────────────────────────────────────────────────
class _CheckCircle extends StatelessWidget {
  final bool checked;
  const _CheckCircle({required this.checked});
  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 20, height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: checked ? AppColors.primary : Colors.white,
          border: Border.all(
              color: checked ? AppColors.primary : const Color(0xFFBDBDBD),
              width: 1.5),
        ),
        child: checked
            ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
            : null,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  PIÈCE "GRAINE" — icône du programme de fidélité.
//  v2 : utilise désormais l'image `assets/images/coins.png`
//  (fournie par le design), posée sur un médaillon doré en dégradé pour
//  lui donner du volume et l'harmoniser avec le reste de la palette
//  (vert "Graine" + or "pièce"). Remplace l'ancien CustomPainter.
//
//  ⚠️ Ne pas oublier de déclarer l'asset dans pubspec.yaml :
//    flutter:
//      assets:
//        - assets/images/coins.png
// ─────────────────────────────────────────────────────────────────────────────
class _SeedCoinIcon extends StatelessWidget {
  final double size;
  const _SeedCoinIcon({this.size = 22});

  static const String _assetPath = 'images/coins-removebg-preview.png';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => Icon(
        Icons.eco_rounded,
        size: size * 0.6,
        color: const Color(0xFF33691E),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
//  COMPTEUR ANIMÉ DE POINTS GRAINE — façon jeu vidéo.
//  Dès que `value` augmente (ex. le solde `users/{uid}.points` grimpe suite
//  à une commande livrée), la pièce fait un petit "rebond" élastique, un
//  éclat de particules dorées jaillit autour d'elle et un label "+N"
//  s'envole brièvement au-dessus du compteur. Si `value` diminue (points
//  dépensés), on se contente de mettre à jour le chiffre sans effet, pour
//  ne pas laisser croire à un gain.
// ─────────────────────────────────────────────────────────────────────────────
class _AnimatedSeedCount extends StatefulWidget {
  final int value;
  final TextStyle style;
  final double coinSize;
  const _AnimatedSeedCount({
    required this.value,
    required this.style,
    this.coinSize = 16,
  });

  @override
  State<_AnimatedSeedCount> createState() => _AnimatedSeedCountState();
}

class _AnimatedSeedCountState extends State<_AnimatedSeedCount>
    with TickerProviderStateMixin {
  late int _displayValue = widget.value;
  late final AnimationController _bounceCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 420));
  late final AnimationController _burstCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 750));
  int _delta = 0;

  @override
  void didUpdateWidget(covariant _AnimatedSeedCount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _delta = widget.value - oldWidget.value;
      setState(() => _displayValue = widget.value);
      _bounceCtrl.forward(from: 0);
      if (_delta > 0) _burstCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    _burstCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scaleAnim = Tween<double>(begin: 1, end: 1.32)
        .chain(CurveTween(curve: Curves.elasticOut))
        .animate(_bounceCtrl);

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          AnimatedBuilder(
            animation: scaleAnim,
            builder: (_, child) =>
                Transform.scale(scale: scaleAnim.value, child: child),
            child: _SeedCoinIcon(size: widget.coinSize),
          ),
          const SizedBox(width: 5),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: Text('$_displayValue',
                key: ValueKey(_displayValue), style: widget.style),
          ),
        ]),

        // ── Éclat de particules dorées (uniquement si gain) ──
        AnimatedBuilder(
          animation: _burstCtrl,
          builder: (context, _) {
            if (_burstCtrl.isDismissed || _burstCtrl.isCompleted) {
              return const SizedBox.shrink();
            }
            return IgnorePointer(
              child: _SeedCoinSparkles(progress: _burstCtrl.value),
            );
          },
        ),

        // ── Label "+N" flottant ──
        if (_delta > 0)
          AnimatedBuilder(
            animation: _burstCtrl,
            builder: (context, _) {
              if (_burstCtrl.isDismissed || _burstCtrl.isCompleted) {
                return const SizedBox.shrink();
              }
              final t = _burstCtrl.value;
              return Positioned(
                top: -16 - (t * 16),
                child: Opacity(
                  opacity: (1 - t).clamp(0.0, 1.0),
                  child: Text('+$_delta',
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 11.5,
                          fontWeight: FontWeight.w800, color: Color(0xFFE0AF3E))),
                ),
              );
            },
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PARTICULES DORÉES — petit "burst" façon pièces de jeu vidéo qui jaillissent
//  puis s'estompent en s'éloignant du centre.
// ─────────────────────────────────────────────────────────────────────────────
class _SeedCoinSparkles extends StatelessWidget {
  final double progress; // 0 → 1
  const _SeedCoinSparkles({required this.progress});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56, height: 56,
      child: CustomPaint(painter: _SeedCoinSparklesPainter(progress: progress)),
    );
  }
}

class _SeedCoinSparklesPainter extends CustomPainter {
  final double progress;
  _SeedCoinSparklesPainter({required this.progress});

  static const _colors = [Color(0xFFE0AF3E), Color(0xFFFFF3C4), Color(0xFF7CB342)];

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final center = Offset(size.width / 2, size.height / 2);
    final fade = (1 - progress).clamp(0.0, 1.0);
    const particleCount = 7;

    for (int i = 0; i < particleCount; i++) {
      final angle = (2 * pi / particleCount) * i + (progress * 0.6);
      final dist = progress * (size.width / 2.1);
      final pos = center + Offset(cos(angle), sin(angle)) * dist;
      final radius = 2.6 * fade + 0.6;
      final paint = Paint()
        ..color = _colors[i % _colors.length].withValues(alpha: fade);
      canvas.drawCircle(pos, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SeedCoinSparklesPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
//  CART ITEM CARD
// ─────────────────────────────────────────────────────────────────────────────
class _CartItemCard extends StatelessWidget {
  final String productId;
  final Map<String, dynamic> product;
  final int qty;
  final bool isSelected;
  final bool outOfStock;
  final int? maxStock;
  final ValueChanged<bool> onSelect;
  final ValueChanged<int> onQtyChange;
  final VoidCallback onRemove;
  final bool showCheckbox; // ✏️ جديد، افتراضياً true

  const _CartItemCard({
    required this.productId,
    required this.product,
    required this.qty,
    required this.isSelected,
    required this.outOfStock,
    required this.maxStock,
    required this.onSelect,
    required this.onQtyChange,
    required this.onRemove,
    this.showCheckbox = true, // ✏️ جديد
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
    final atMaxStock = maxStock != null && qty >= maxStock!;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: outOfStock
              ? const Color(0xFFE53935).withValues(alpha: 0.3)
              : AppColors.border,
        ),
        boxShadow: [BoxShadow(
            color: AppColors.shadow, blurRadius: 8, offset: const Offset(0, 3))],
      ),
      padding: const EdgeInsets.all(10),
      child: Opacity(
        opacity: outOfStock ? 0.55 : 1,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Sélection ──
         if (showCheckbox)
  GestureDetector(
    onTap: outOfStock ? null : () => onSelect(!isSelected),
    child: Padding(
      padding: const EdgeInsets.only(top: 28, right: 8),
      child: _CheckCircle(checked: isSelected && !outOfStock),
    ),
  ),

          // ── Image ──
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: imageUrl, width: 72, height: 72, fit: BoxFit.cover,
              placeholder: (_, __) => Container(width: 72, height: 72,
                  color: const Color(0xFFF0F0F0)),
              errorWidget: (_, __, ___) => Container(width: 72, height: 72,
                  color: Colors.grey[200],
                  child: const Icon(Icons.image_not_supported_rounded,
                      color: Colors.grey)),
            ),
          ),
          const SizedBox(width: 10),

          // ── Infos ──
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 13,
                            fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                  ),
                  // ── Bouton supprimer (cohérent avec le design) ──
                  GestureDetector(
                    onTap: onRemove,
                    child: Container(
                      width: 26, height: 26,
                      margin: const EdgeInsets.only(left: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.delete_outline_rounded,
                          size: 15, color: AppColors.error),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              if (outOfStock)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: const Color(0xFFE53935).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4)),
                  child: const Text('Rupture de stock',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 10,
                          fontWeight: FontWeight.w700, color: Color(0xFFE53935))),
                )
              else if (hasDiscount)
                Row(children: [
                  Text('${oldPrice.toStringAsFixed(oldPrice % 1 == 0 ? 0 : 1)} DH',
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 11,
                          color: Color(0xFF9E9E9E),
                          decoration: TextDecoration.lineThrough)),
                  const SizedBox(width: 5),
                  Text('-${(oldPrice - price).toStringAsFixed((oldPrice-price) % 1 == 0 ? 0 : 1)} DH',
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 10,
                          fontWeight: FontWeight.w700, color: Color(0xFF43A047))),
                ]),

              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${price.toStringAsFixed(price % 1 == 0 ? 0 : 1)} DH',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 15,
                          fontWeight: FontWeight.w800, color: Colors.black)),

                  // ── Stepper quantité ──
                  if (!outOfStock)
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE0E0E0)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        _StepperBtn(
                          icon: Icons.remove_rounded,
                          onTap: () => onQtyChange(qty - 1),
                        ),
                        Container(
                          constraints: const BoxConstraints(minWidth: 28),
                          alignment: Alignment.center,
                          child: Text('$qty',
                              style: const TextStyle(fontFamily: 'Cairo',
                                  fontSize: 13, fontWeight: FontWeight.w700)),
                        ),
                        _StepperBtn(
                          icon: Icons.add_rounded,
                          onTap: atMaxStock ? null : () => onQtyChange(qty + 1),
                        ),
                      ]),
                    ),
                ],
              ),
              if (atMaxStock && !outOfStock)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text('Stock max atteint ($maxStock)',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 9,
                          color: Colors.orange[700])),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _StepperBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepperBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 26, height: 26,
          alignment: Alignment.center,
          child: Icon(icon, size: 15,
              color: onTap == null ? Colors.grey[400] : const Color(0xFF424242)),
        ),
      );
}

class _CartItemSkeleton extends StatelessWidget {
  const _CartItemSkeleton();
  @override
  Widget build(BuildContext context) => Container(
        height: 92,
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(14)),
      );
}

class _CartItemUnavailable extends StatelessWidget {
  final String productId;
  final String message;
  final VoidCallback onRemove;
  const _CartItemUnavailable({
    required this.productId,
    required this.onRemove,
    this.message = "Ce produit n'est plus disponible",
  });
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded, color: Colors.grey),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12,
                    color: Color(0xFF757575))),
          ),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: const [
                Icon(Icons.delete_outline_rounded, size: 14, color: AppColors.error),
                SizedBox(width: 4),
                Text('Retirer',
                    style: TextStyle(fontFamily: 'Cairo', color: AppColors.error,
                        fontWeight: FontWeight.w700, fontSize: 12)),
              ]),
            ),
          ),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  ZIPPER GÉNÉRIQUE — combine plusieurs streams de documents Firestore en un
//  seul Map<docId, DocumentSnapshot>, avec gestion propre du cycle de vie
//  (annulation de toutes les subscriptions au dispose). Remplace les anciens
//  helpers `_zip` / `_zipStreams` qui fuyaient des StreamSubscription et qui
//  associaient les résultats par INDEX (source de bugs si l'ordre ou le
//  nombre d'éléments changeait entre deux builds).
// ─────────────────────────────────────────────────────────────────────────────
class _DocsMapZipper extends StatefulWidget {
  final List<String> docIds;
  final CollectionReference Function() collection;
  final Widget Function(BuildContext context, Map<String, DocumentSnapshot> docs,
      bool hasError) builder;

  const _DocsMapZipper({
    required this.docIds,
    required this.collection,
    required this.builder,
  });

  @override
  State<_DocsMapZipper> createState() => _DocsMapZipperState();
}

class _DocsMapZipperState extends State<_DocsMapZipper> {
  final Map<String, DocumentSnapshot> _docs = {};
  final Map<String, StreamSubscription<DocumentSnapshot>> _subs = {};
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _subscribeAll();
  }

  @override
  void didUpdateWidget(_DocsMapZipper oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIds = oldWidget.docIds.toSet();
    final newIds = widget.docIds.toSet();
    if (oldIds.length != newIds.length || !oldIds.containsAll(newIds)) {
      _unsubscribeAll();
      _docs.removeWhere((id, _) => !newIds.contains(id));
      _subscribeAll();
    }
  }

  void _subscribeAll() {
    for (final id in widget.docIds) {
      if (_subs.containsKey(id)) continue;
      _subs[id] = widget.collection().doc(id).snapshots().listen(
        (doc) {
          if (!mounted) return;
          setState(() => _docs[id] = doc);
        },
        onError: (_) {
          if (!mounted) return;
          setState(() => _hasError = true);
        },
      );
    }
  }

  void _unsubscribeAll() {
    for (final sub in _subs.values) {
      sub.cancel();
    }
    _subs.clear();
  }

  @override
  void dispose() {
    _unsubscribeAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // On ne considère "prêt" que si on a reçu au moins un évènement pour
    // chaque id demandé — sinon on laisse le builder gérer l'état partiel.
    return widget.builder(context, _docs, _hasError);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  TEASER POINTS GRAINE — discret, varie selon le sous-total sélectionné,
//  pour éviter la répétition et l'effet "publicité intrusive". Informe
//  l'utilisateur du nombre de points qu'il POSSÈDE et de ceux qu'il GAGNERA.
//  (Le fait d'ÉCHANGER des points contre une réduction se fait dans la
//  barre de résumé en bas — voir _CartSummaryBar.)
// ─────────────────────────────────────────────────────────────────────────────
class _LoyaltyTeaser extends StatelessWidget {
  final String uid;
  final List<QueryDocumentSnapshot> cartDocs;
  final List<String> productIds;
  const _LoyaltyTeaser({
    required this.uid,
    required this.cartDocs,
    required this.productIds,
  });

  double _p(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    if (productIds.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, userSnap) {
        final points = (userSnap.hasData && userSnap.data!.exists)
            ? _parseInt((userSnap.data!.data() as Map)['points'])
            : 0;

        return _DocsMapZipper(
          docIds: productIds,
          collection: () => FirebaseFirestore.instance.collection('products'),
          builder: (context, productsById, hasError) {
            if (hasError || productsById.length < productIds.length) {
              return const SizedBox.shrink();
            }

            double subtotal = 0;
            for (final cartDoc in cartDocs) {
              final doc = productsById[cartDoc.id];
              if (doc == null || !doc.exists) continue;
              final p = doc.data() as Map<String, dynamic>;
              final stock = (p['stock'] as num?)?.toInt();
              if (stock != null && stock <= 0) continue;
              final qty = ((cartDoc.data() as Map)['qty'] as num?)?.toInt() ?? 1;
              subtotal += _p(p['price']) * qty;
            }
            if (subtotal <= 0) return const SizedBox.shrink();

            // points qu'apportera cette commande une fois "livrée"
            int earnable;
            if (subtotal <= 500) {
              earnable = (subtotal / 60).floor();
            } else {
              earnable = (500 / 60).floor() + (((subtotal - 500) / 60) * 2).floor();
            }

            // message varié pour éviter la lassitude — choisi de façon
            // déterministe selon un mélange points+sous-total (stable tant
            // que le panier ne change pas, mais change si le panier change)
            final variantSeed = (points + subtotal.round()) % 3;
            final messages = [
              'Cette commande vous rapportera environ $earnable points Graine une fois livrée.',
              'Vous avez déjà $points points Graine — chaque commande livrée vous en rapporte plus.',
              '+$earnable points dès que cette commande sera marquée comme livrée.',
            ];
            final msg = messages[variantSeed.abs() % messages.length];

            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF1F8E9), Color(0xFFE3F2D9)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFAED581).withValues(alpha: 0.6)),
                ),
                child: Row(children: [
                  const _SeedCoinIcon(size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(msg,
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 11.5,
                            fontWeight: FontWeight.w600, color: Color(0xFF33691E),
                            height: 1.35)),
                  ),
                ]),
              ),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  BADGES DE CONFIANCE — version simplifiée : 3 repères seulement
//  (Certifié ONSSA / 100% Bio / Livraison gratuite), sans carte ni ombre —
//  juste une icône verte et son libellé, sur une seule ligne qui tient
//  toujours entièrement à l'écran (pas de défilement horizontal).
//  Le 4e badge ("Points Graines") a été retiré : il fait doublon avec le
//  bandeau points Graine déjà affiché juste au-dessus.
// ─────────────────────────────────────────────────────────────────────────────
class _TrustBadgesRow extends StatelessWidget {
  const _TrustBadgesRow();

  @override
  Widget build(BuildContext context) {
    const badges = [
      _TrustBadgeData(icon: Icons.verified_user_rounded, title: 'Certifié ONSSA'),
      _TrustBadgeData(icon: Icons.eco_rounded, title: '100% Bio'),
      _TrustBadgeData(icon: Icons.local_shipping_rounded, title: 'Livraison gratuite'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      child: Row(
        children: [
          for (final b in badges)
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(b.icon, size: 22, color: AppColors.primary),
                  ),
                  const SizedBox(height: 6),
                  Text(b.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 10.5,
                          fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TrustBadgeData {
  final IconData icon;
  final String title;
  const _TrustBadgeData({required this.icon, required this.title});
}

// ─────────────────────────────────────────────────────────────────────────────
//  COMMANDES EN COURS — statut différent de delivered / cancelled
// ─────────────────────────────────────────────────────────────────────────────
class _OrdersInProgressSection extends StatelessWidget {
  final String uid;
  const _OrdersInProgressSection({required this.uid});

  static const _statusLabels = {
    'pending': 'En attente',
    'confirmed': 'Confirmée',
    'preparing': 'En préparation',
    'shipped': 'Expédiée',
  };

  static const _statusColors = {
    'pending': Color(0xFFFFA000),
    'confirmed': Color(0xFF1565C0),
    'preparing': Color(0xFF7B61FF),
    'shipped': AppColors.primary,
  };

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('userId', isEqualTo: uid)
          .where('status', whereIn: ['pending', 'confirmed', 'preparing', 'shipped'])
          .orderBy('createdAt', descending: true)
          .limit(8)
          .snapshots(),
      builder: (context, snap) {
        // ⚠️ Cette requête (where + whereIn + orderBy) nécessite un index
        // composite Firestore. Si l'index manque, Firestore renvoie une
        // erreur — avant, elle était silencieusement ignorée (l'utilisateur
        // ne voyait jamais cette section, sans aucune information). On logue
        // l'erreur en mode debug pour la détecter facilement en dev, et on
        // masque proprement la section en prod plutôt que de planter.
        if (snap.hasError) {
          assert(() {
            // ignore: avoid_print
            print('[_OrdersInProgressSection] Firestore error: ${snap.error}\n'
                'Astuce : cette requête nécessite probablement un index composite '
                '(userId == + status in + orderBy createdAt). Crée-le depuis le '
                'lien fourni dans le message d\'erreur Firestore.');
            return true;
          }());
          return const SizedBox.shrink();
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        final orders = snap.data!.docs;

        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(children: [
                  Container(
                    width: 4, height: 16,
                    decoration: BoxDecoration(
                        color: AppColors.accent, borderRadius: BorderRadius.circular(4)),
                  ),
                  const SizedBox(width: 8),
                  const Text('Vos commandes en cours',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 13.5,
                          fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => context.push('/orders'),
                    child: Text('Tout voir',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5,
                            fontWeight: FontWeight.w700, color: AppColors.primary)),
                  ),
                ]),
              ),
              SizedBox(
                height: 168,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (ctx, i) {
                    final doc = orders[i];
                    final data = doc.data() as Map<String, dynamic>;
                    final status = data['status']?.toString() ?? 'pending';
                    final items = (data['items'] as List?) ?? [];
                    final total = (data['total'] as num?)?.toDouble() ?? 0;
                    final statusColor = _statusColors[status] ?? Colors.grey;
                    final statusLabel = _statusLabels[status] ?? status;

                    return GestureDetector(
                      onTap: () => context.push('/orders/${doc.id}'),
                      child: Container(
                        width: 168,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                          boxShadow: [BoxShadow(
                              color: AppColors.shadow, blurRadius: 8,
                              offset: const Offset(0, 3))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(statusLabel,
                                    style: TextStyle(fontFamily: 'Cairo', fontSize: 9.5,
                                        fontWeight: FontWeight.w800, color: statusColor)),
                              ),
                            ]),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 46,
                              child: Stack(children: [
                                for (int k = 0; k < min(items.length, 3); k++)
                                  Positioned(
                                    left: k * 24.0,
                                    child: Container(
                                      width: 44, height: 44,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 2),
                                      ),
                                      child: ClipOval(
                                        child: CachedNetworkImage(
                                          imageUrl: (items[k] as Map)['imageUrl']
                                                  ?.toString() ?? '',
                                          fit: BoxFit.cover,
                                          errorWidget: (_, __, ___) => Container(
                                              color: Colors.grey[200],
                                              child: const Icon(Icons.image_rounded,
                                                  size: 16, color: Colors.grey)),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (items.length > 3)
                                  Positioned(
                                    left: 3 * 24.0,
                                    child: Container(
                                      width: 44, height: 44,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.black.withValues(alpha: 0.55),
                                        border: Border.all(color: Colors.white, width: 2),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text('+${items.length - 3}',
                                          style: const TextStyle(fontFamily: 'Cairo',
                                              fontSize: 11, fontWeight: FontWeight.w800,
                                              color: Colors.white)),
                                    ),
                                  ),
                              ]),
                            ),
                            const Spacer(),
                            Text('${total.toStringAsFixed(total % 1 == 0 ? 0 : 2)} DH',
                                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13,
                                    fontWeight: FontWeight.w800, color: Colors.black)),
                            const SizedBox(height: 6),
                            SizedBox(
                              width: double.infinity,
                              height: 28,
                              child: OutlinedButton(
                                onPressed: () => context.push('/orders/${doc.id}'),
                                style: OutlinedButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  side: const BorderSide(color: AppColors.primary),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text('Détails',
                                    style: TextStyle(fontFamily: 'Cairo', fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  CARTE PRODUIT GÉNÉRIQUE — utilisée par les sections "recommandés" et
//  "meilleures ventes" pour éviter la duplication de layout.
// ─────────────────────────────────────────────────────────────────────────────
class _ProductCard extends StatelessWidget {
  final String productId;
  final Map<String, dynamic> product;
  const _ProductCard({required this.productId, required this.product});

  double _p(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final price = _p(product['price']);
    final oldPrice = _p(product['oldPrice']);
    final hasDiscount = oldPrice > price && oldPrice > 0;

    return GestureDetector(
      onTap: () => context.push('/product/$productId'),
      child: Container(
        width: 128,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: [BoxShadow(
              color: AppColors.shadow, blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              child: CachedNetworkImage(
                imageUrl: product['imageUrl']?.toString() ?? '',
                height: 96, width: double.infinity, fit: BoxFit.cover,
                placeholder: (_, __) =>
                    Container(height: 96, color: const Color(0xFFF0F0F0)),
                errorWidget: (_, __, ___) => Container(
                    height: 96, color: Colors.grey[200],
                    child: const Icon(Icons.image_not_supported_rounded,
                        color: Colors.grey)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product['name']?.toString() ?? '',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 11.5,
                          fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                  const SizedBox(height: 3),
                  Row(children: [
                    Text('${price.toStringAsFixed(price % 1 == 0 ? 0 : 1)} DH',
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5,
                            fontWeight: FontWeight.w800, color: Colors.black)),
                    if (hasDiscount) ...[
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                            '${oldPrice.toStringAsFixed(oldPrice % 1 == 0 ? 0 : 1)}',
                            style: const TextStyle(fontFamily: 'Cairo', fontSize: 9.5,
                                color: Color(0xFF9E9E9E),
                                decoration: TextDecoration.lineThrough)),
                      ),
                    ],
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PRODUITS RECOMMANDÉS — même catégorie que le panier
// ─────────────────────────────────────────────────────────────────────────────
class _RecommendedProductsSection extends StatelessWidget {
  final String uid;
  final List<String> cartProductIds;
  const _RecommendedProductsSection({required this.uid, required this.cartProductIds});

  @override
  Widget build(BuildContext context) {
    if (cartProductIds.isEmpty) return const SizedBox.shrink();

    // 1) on lit les produits du panier pour récupérer leurs catégories
    return _DocsMapZipper(
      docIds: cartProductIds,
      collection: () => FirebaseFirestore.instance.collection('products'),
      builder: (context, cartProductsById, hasError) {
        if (hasError) return const SizedBox.shrink();

        final categories = <String>{};
        for (final doc in cartProductsById.values) {
          if (!doc.exists) continue;
          final cat = (doc.data() as Map)['category']?.toString();
          if (cat != null && cat.isNotEmpty) categories.add(cat);
        }

        if (categories.isEmpty) return const SizedBox.shrink();

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('products')
              .where('category', whereIn: categories.take(10).toList())
              .limit(20)
              .snapshots(),
          builder: (context, recSnap) {
            if (recSnap.hasError || !recSnap.hasData) {
              return const SizedBox.shrink();
            }

            final recs = recSnap.data!.docs
                .where((d) => !cartProductIds.contains(d.id))
                .where((d) {
                  final stock = _parseIntOrNull((d.data() as Map)['stock']);
                  return stock == null || stock > 0;
                })
                .take(10)
                .toList();

            if (recs.isEmpty) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Row(children: [
                      Container(
                        width: 4, height: 16,
                        decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(4)),
                      ),
                      const SizedBox(width: 8),
                      const Text('Vous pourriez aussi aimer',
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 13.5,
                              fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
                    ]),
                  ),
                  SizedBox(
                    height: 188,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: recs.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (ctx, i) => _ProductCard(
                        productId: recs[i].id,
                        product: recs[i].data() as Map<String, dynamic>,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  MEILLEURES VENTES — utilisée quand le panier est vide (et sans historique
//  de commandes connu à ce stade) : tri sur `salesCount` décroissant.
//  But : ne jamais laisser l'écran panier vide sans aucune suggestion.
// ─────────────────────────────────────────────────────────────────────────────
class _BestSellersSection extends StatelessWidget {
  const _BestSellersSection();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('products')
          .orderBy('salesCount', descending: true)
          .limit(12)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return const SizedBox.shrink();
        }
        if (!snap.hasData) {
          return const SizedBox(
            height: 188,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final products = snap.data!.docs.where((d) {
          final stock = ((d.data() as Map)['stock'] as num?)?.toInt();
          return stock == null || stock > 0;
        }).toList();

        if (products.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(children: [
                  Container(
                    width: 4, height: 16,
                    decoration: BoxDecoration(
                        color: AppColors.accent, borderRadius: BorderRadius.circular(4)),
                  ),
                  const SizedBox(width: 8),
                  const Text('Nos meilleures ventes 🔥',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 13.5,
                          fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
                ]),
              ),
              SizedBox(
                height: 188,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: products.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (ctx, i) => _ProductCard(
                    productId: products[i].id,
                    product: products[i].data() as Map<String, dynamic>,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  BOUTON "OFFRE SPÉCIALE" — pulsant, fond blanc / contour orange, pour
//  attirer discrètement l'œil vers l'échange de points sans être criard.
//  Fines rayures "confettis" en fond (très légères, alpha faible) et un
//  léger effet de respiration (scale 1 → 1.06 en boucle).
// ─────────────────────────────────────────────────────────────────────────────
class _PulsingOfferButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _PulsingOfferButton({required this.label, required this.onTap});

  @override
  State<_PulsingOfferButton> createState() => _PulsingOfferButtonState();
}

class _PulsingOfferButtonState extends State<_PulsingOfferButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  late final AnimationController _handCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    _handCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = Tween<double>(begin: 1.0, end: 1.07)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_ctrl);
    final handShift = Tween<double>(begin: 0, end: 4)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_handCtrl);

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: scale,
        builder: (context, child) => Transform.scale(scale: scale.value, child: child),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFFF8F00), width: 2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF8F00).withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Fines rayures diagonales "confettis" — très discrètes.
                Positioned.fill(
                  child: CustomPaint(painter: _DiagonalStripesPainter()),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Text('🎉', style: TextStyle(fontSize: 15)),
                    const SizedBox(width: 6),
                    Text(widget.label,
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 13.5,
                            fontWeight: FontWeight.w800, color: Color(0xFFFF8F00))),
                    const SizedBox(width: 6),
                    // ── Icône "curseur main" qui glisse légèrement vers le
                    //    bouton, façon "cliquez ici" ──
                    AnimatedBuilder(
                      animation: handShift,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(handShift.value, 0),
                        child: child,
                      ),
                      child: const Icon(Icons.touch_app_rounded,
                          size: 20, color: Color(0xFFFF8F00)),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DiagonalStripesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF8F00).withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;
    const stripeWidth = 6.0;
    const gap = 10.0;
    double x = -size.height;
    while (x < size.width) {
      final path = Path()
        ..moveTo(x, size.height)
        ..lineTo(x + size.height, 0)
        ..lineTo(x + size.height + stripeWidth, 0)
        ..lineTo(x + stripeWidth, size.height)
        ..close();
      canvas.drawPath(path, paint);
      x += stripeWidth + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DiagonalStripesPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
//  SUMMARY BAR — calcule en live à partir des produits sélectionnés.
//
//  ✏️ Livraison désormais TOUJOURS gratuite (deliveryFee = 0.0), la commande
//     est simplement bloquée tant que le sous-total n'atteint pas
//     `minOrderAmount` (99 DH).
//
//  ✏️ Système d'échange de points Graine :
//     • seedValueDh (1.5 DH / point) donne la valeur de la réduction.
//     • Le bouton d'échange n'apparaît QUE si le solde de l'utilisateur
//       dépasse l'équivalent de 20 DH (≥ pointsThreshold points), pour
//       éviter un usage dérisoire du système.
//     • La réduction appliquée est plafonnée par DEUX contraintes cumulées
//       (voir `_maxDiscountAllowed`) : jamais plus de 30% du sous-total, ET
//       jamais de quoi faire descendre le prix final sous `minOrderAmount`.
//       Le slider du bottom sheet est borné en conséquence.
//     • Le solde `userPoints` est affiché via `_AnimatedSeedCount` : dès
//       qu'il augmente (commande livrée entre-temps par ex.), un petit
//       effet "pièces de jeu vidéo" (rebond + particules + "+N") se joue.
//
//  ⚠️ NOTE FORMULES : le sous-total inclut désormais aussi les articles de
//  type 'formule' sélectionnés (lus directement via `unitPrice` sur le
//  document panier, pas de lookup produit par produit).
// ─────────────────────────────────────────────────────────────────────────────
class _CartSummaryBar extends StatefulWidget {
  final String uid;
  final List<QueryDocumentSnapshot> cartDocs;
  final Set<String> selectedIds;
  final double minOrderAmount;

  const _CartSummaryBar({
    required this.uid,
    required this.cartDocs,
    required this.selectedIds,
    required this.minOrderAmount,
  });

  @override
  State<_CartSummaryBar> createState() => _CartSummaryBarState();
}

class _CartSummaryBarState extends State<_CartSummaryBar> {
  // valeur d'1 point Graine, en DH
  static const double seedValueDh = 1.5;
  // seuil minimum de VALEUR (en DH) pour afficher le bouton d'échange
  static const double minRedeemableValueDh = 20.0;
  // seuil minimum de POINTS correspondant (arrondi au-dessus pour garantir
  // que le solde "dépasse" bien 20 DH, comme demandé)
  static int get pointsThreshold => (minRedeemableValueDh / seedValueDh).ceil();

  // nombre de points que l'utilisateur a choisi d'échanger (persiste tant
  // que ce widget reste monté, ex. tant qu'on est sur l'écran panier)
  int _redeemPoints = 0;

  // ── Anti-double-achat : bloque "Commander" pendant 60s après la
  //    dernière commande passée par ce client (toutes commandes confondues,
  //    peu importe l'écran depuis lequel elle a été passée). ──
  static const int purchaseCooldownSeconds = 60;
  DateTime? _lastOrderAt;
  Timer? _cooldownTicker;

  // ── Masquer la carte points Graine (croix ✕) pour la session en cours ──
  bool _hidePointsCard = false;

  @override
  void dispose() {
    _cooldownTicker?.cancel();
    super.dispose();
  }

  int get _cooldownSecondsRemaining {
    if (_lastOrderAt == null) return 0;
    final elapsed = DateTime.now().difference(_lastOrderAt!).inSeconds;
    final remaining = purchaseCooldownSeconds - elapsed;
    return remaining > 0 ? remaining : 0;
  }

  void _ensureCooldownTicker() {
    if (_cooldownSecondsRemaining > 0 && _cooldownTicker == null) {
      _cooldownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_cooldownSecondsRemaining <= 0) {
          _cooldownTicker?.cancel();
          _cooldownTicker = null;
        }
        setState(() {});
      });
    }
  }

  double _p(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  /// Réduction maximale autorisée (en DH), en cumulant DEUX contraintes :
  ///   1) le prix final après réduction ne peut JAMAIS descendre en dessous
  ///      du montant minimum de commande (`minOrderAmount`) — la réduction
  ///      ne doit jamais servir à contourner ce seuil ;
  ///   2) la réduction ne peut JAMAIS dépasser 30% du sous-total, quel que
  ///      soit le solde de points détenu par le client.
  /// Le plafond retenu est toujours le plus restrictif des deux.
  double _maxDiscountAllowed(double subtotal, double minOrderAmount) {
    if (subtotal <= 0) return 0;
    final byPercentCap = subtotal * 0.30;
    final byMinOrderCap = (subtotal - minOrderAmount).clamp(0.0, double.infinity);
    return min(byPercentCap, byMinOrderCap);
  }

  Future<void> _openRedeemSheet(
      BuildContext context, int userPoints, double subtotal) async {
    final maxDiscountAllowed = _maxDiscountAllowed(subtotal, widget.minOrderAmount);
    final maxPointsByCap = (maxDiscountAllowed / seedValueDh).floor();
    final maxRedeemable = min(userPoints, maxPointsByCap);
    if (maxRedeemable <= 0) return;

    int tempValue = _redeemPoints.clamp(0, maxRedeemable);

    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final discount = tempValue * seedValueDh;
            final currentPrice = (subtotal - discount).clamp(0.0, subtotal);
            final priceFloor = (subtotal - maxDiscountAllowed).clamp(0.0, subtotal);
            final atMaxDiscount = tempValue >= maxRedeemable;

            return Padding(
              padding: EdgeInsets.only(
                left: 20, right: 20, top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: Colors.grey[300], borderRadius: BorderRadius.circular(4)),
                ),
                Row(children: [
                  const _SeedCoinIcon(size: 24),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Utilisez vos points Graine',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 15,
                            fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
                  ),
                ]),
                const SizedBox(height: 18),

                // ── Prix de la commande — grand affichage, live, orange ──
                Text('Prix de votre commande',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5,
                        fontWeight: FontWeight.w700, color: Colors.grey[600])),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 320),
                      transitionBuilder: (child, anim) => ScaleTransition(
                        scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: Text(
                        '${currentPrice.toStringAsFixed(currentPrice % 1 == 0 ? 0 : 2)} DH',
                        key: ValueKey(tempValue),
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 30,
                            fontWeight: FontWeight.w900, color: Color(0xFFFF8F00)),
                      ),
                    ),
                    if (tempValue > 0) ...[
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Text(
                          '${subtotal.toStringAsFixed(subtotal % 1 == 0 ? 0 : 2)} DH',
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 14,
                              fontWeight: FontWeight.w700, color: Colors.grey[400],
                              decoration: TextDecoration.lineThrough),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),

                // ── Slider "prix" — tirer vers la gauche = prix qui baisse ──
                SliderTheme(
                  data: SliderTheme.of(ctx).copyWith(
                    activeTrackColor: const Color(0xFFFF8F00),
                    inactiveTrackColor: const Color(0xFFFFE0B2),
                    thumbColor: const Color(0xFFFF8F00),
                    overlayColor: const Color(0xFFFF8F00).withValues(alpha: 0.15),
                    valueIndicatorColor: const Color(0xFFFF8F00),
                    valueIndicatorTextStyle: const TextStyle(
                        fontFamily: 'Cairo', fontWeight: FontWeight.w800,
                        color: Colors.white, fontSize: 13),
                    showValueIndicator: ShowValueIndicator.always,
                    trackHeight: 6,
                  ),
                  child: Slider(
                    value: currentPrice,
                    min: priceFloor,
                    max: subtotal,
                    divisions: maxRedeemable > 0 ? maxRedeemable : 1,
                    label:
                        '${currentPrice.toStringAsFixed(currentPrice % 1 == 0 ? 0 : 1)} DH',
                    onChanged: (v) {
                      final newDiscount = (subtotal - v).clamp(0.0, maxDiscountAllowed);
                      final newPoints =
                          (newDiscount / seedValueDh).round().clamp(0, maxRedeemable);
                      setModalState(() => tempValue = newPoints);
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Prix plein · ${subtotal.toStringAsFixed(subtotal % 1 == 0 ? 0 : 1)} DH',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 9.5,
                            color: Colors.grey[500])),
                    Text('Réduction max · ${priceFloor.toStringAsFixed(priceFloor % 1 == 0 ? 0 : 1)} DH',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 9.5,
                            color: Colors.grey[500])),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  atMaxDiscount
                      ? 'Réduction maximale atteinte pour cette commande'
                      : 'Tirez la piste vers la gauche pour augmenter la réduction',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 10.5,
                      fontWeight: atMaxDiscount ? FontWeight.w700 : FontWeight.w500,
                      color: atMaxDiscount ? const Color(0xFFFF8F00) : Colors.grey[500]),
                ),

                const SizedBox(height: 16),
                if (tempValue < maxRedeemable)
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      setModalState(() => tempValue = maxRedeemable);
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF8F00), AppColors.primary],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF8F00).withValues(alpha: 0.32),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.bolt_rounded, color: Colors.white, size: 19),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Échanger $maxRedeemable points contre '
                              '${maxDiscountAllowed.toStringAsFixed(maxDiscountAllowed % 1 == 0 ? 0 : 1)} DH',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13.5,
                                  fontWeight: FontWeight.w800, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F8E9),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFAED581).withValues(alpha: 0.6)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 19),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$tempValue points échangés · -${discount.toStringAsFixed(discount % 1 == 0 ? 0 : 1)} DH',
                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5,
                              fontWeight: FontWeight.w700, color: Color(0xFF33691E)),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setModalState(() => tempValue = 0),
                        child: Text('Annuler',
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5,
                                fontWeight: FontWeight.w700, color: Colors.grey[600])),
                      ),
                    ]),
                  ),
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, 0),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Annuler',
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700,
                              color: Color(0xFF757575))),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, tempValue),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8F00),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: const Text('Confirmer',
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                  ),
                ]),
              ]),
            );
          },
        );
      },
    );

    if (result != null && mounted) {
      setState(() => _redeemPoints = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedDocs =
        widget.cartDocs.where((d) => widget.selectedIds.contains(d.id)).toList();

    if (selectedDocs.isEmpty) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        decoration: const BoxDecoration(color: Colors.white,
            boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 8,
                offset: Offset(0, -2))]),
        child: Text('Sélectionnez des articles pour commander',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 13,
                color: Colors.grey[500])),
      );
    }

    // ── Sépare les articles PRODUITS (prix live) des articles FORMULE
    //    (prix déjà figé dans `unitPrice`) pour le calcul du sous-total. ──
    final selectedProductDocs = selectedDocs
        .where((d) => (d.data() as Map)['type'] != 'formule')
        .toList();
    final selectedFormuleDocs = selectedDocs
        .where((d) => (d.data() as Map)['type'] == 'formule')
        .toList();
    final selectedProductIdsList = selectedProductDocs.map((d) => d.id).toList();

    double formulesSubtotal = 0;
    int formulesItemCount = 0;
    for (final d in selectedFormuleDocs) {
      final data = d.data() as Map<String, dynamic>;
      final qty = (data['quantity'] as num?)?.toInt() ?? 1;
      formulesSubtotal += _p(data['unitPrice']) * qty;
      formulesItemCount += qty;
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('userId', isEqualTo: widget.uid)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, lastOrderSnap) {
        if (lastOrderSnap.hasData && lastOrderSnap.data!.docs.isNotEmpty) {
          final ts = (lastOrderSnap.data!.docs.first.data() as Map)['createdAt']
              as Timestamp?;
          if (ts != null) _lastOrderAt = ts.toDate();
        }
        // Démarre (ou relance) le compte à rebours d'1 seconde tant qu'on
        // est encore dans la fenêtre de blocage.
        WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCooldownTicker());

        return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(widget.uid).snapshots(),
      builder: (context, userSnap) {
        final userPoints = (userSnap.hasData && userSnap.data!.exists)
            ? _parseInt((userSnap.data!.data() as Map)['points'])
            : 0;

        return _DocsMapZipper(
          docIds: selectedProductIdsList,
          collection: () => FirebaseFirestore.instance.collection('products'),
          builder: (context, productsById, hasZipError) {
            double subtotal = formulesSubtotal;
            int itemCount = formulesItemCount;
            bool hasOutOfStock = false;
            final isReady = !hasZipError &&
                selectedProductIdsList.every(productsById.containsKey);

            if (isReady) {
              for (final cartDoc in selectedProductDocs) {
                final prodDoc = productsById[cartDoc.id];
                if (prodDoc == null || !prodDoc.exists) continue;
                final p = prodDoc.data() as Map<String, dynamic>;
                final stock = _parseIntOrNull(p['stock']);
                if (stock != null && stock <= 0) {
                  hasOutOfStock = true;
                  continue;
                }
                final qty = ((cartDoc.data() as Map)['qty'] as num?)?.toInt() ?? 1;
                subtotal += _p(p['price']) * qty;
                itemCount += qty;
              }
            }

            // plafond de réduction : le plus restrictif entre 30% du
            // sous-total et le respect du montant minimum de commande —
            // peu importe le solde de points du client.
            final maxDiscountAllowed = _maxDiscountAllowed(subtotal, widget.minOrderAmount);
            final maxPointsByCap = (maxDiscountAllowed / seedValueDh).floor();
            final maxRedeemable = min(userPoints, maxPointsByCap);
            // si le sous-total diminue (retrait d'un article), on replafonne
            // silencieusement les points déjà sélectionnés
            final effectiveRedeemPoints =
                _redeemPoints.clamp(0, maxRedeemable < 0 ? 0 : maxRedeemable);
            final discountAmount = effectiveRedeemPoints * seedValueDh;

            const deliveryFee = 0.0; // livraison toujours gratuite
            final total =
                (subtotal - discountAmount + deliveryFee).clamp(0, double.infinity);
            final missingForMinOrder = widget.minOrderAmount - subtotal;
            final belowMinOrder = subtotal > 0 && subtotal < widget.minOrderAmount;

            final showRedeemButton = userPoints >= pointsThreshold &&
                subtotal > 0 &&
                maxRedeemable > 0;

            return Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(color: Colors.white,
                  boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 8,
                      offset: Offset(0, -2))]),
              child: SafeArea(
                top: false,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  // ── Livraison gratuite (toujours) ──
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(children: const [
                      Icon(Icons.local_shipping_rounded, size: 16, color: AppColors.primary),
                      SizedBox(width: 6),
                      Text('Livraison gratuite sur toutes les commandes 🎉',
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5,
                              fontWeight: FontWeight.w800, color: AppColors.primary)),
                    ]),
                  ),

                  // ── Montant minimum de commande ──
                  if (belowMinOrder)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            'Encore ${missingForMinOrder.toStringAsFixed(missingForMinOrder % 1 == 0 ? 0 : 1)} DH '
                            'pour atteindre le minimum de commande (${widget.minOrderAmount.toStringAsFixed(0)} DH)',
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 11,
                                fontWeight: FontWeight.w700, color: Colors.orange[800]),
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: LinearProgressIndicator(
                              value: (subtotal / widget.minOrderAmount).clamp(0.0, 1.0),
                              minHeight: 6,
                              backgroundColor: Colors.orange.withValues(alpha: 0.12),
                              valueColor: AlwaysStoppedAnimation(Colors.orange[700]),
                            ),
                          ),
                        ]),
                      ),
                    ),

                  // ── Points Graine : solde (animé) + bouton d'échange ──
                  if (subtotal > 0 && !_hidePointsCard)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          GestureDetector(
                            onTap: showRedeemButton
                                ? () => _openRedeemSheet(context, userPoints, subtotal)
                                : null,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(12, 10, 30, 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F8E9),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFAED581).withValues(alpha: 0.6)),
                              ),
                              child: Row(children: [
                                if (effectiveRedeemPoints > 0) ...[
                                  const _SeedCoinIcon(size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '$effectiveRedeemPoints points utilisés · il vous restera ${userPoints - effectiveRedeemPoints} points',
                                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 11,
                                          fontWeight: FontWeight.w700, color: Color(0xFF33691E)),
                                    ),
                                  ),
                                ] else ...[
                                  Expanded(
                                    child: Row(children: [
                                      Text('Vous avez ',
                                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 11,
                                              fontWeight: FontWeight.w700, color: Color(0xFF33691E))),
                                      _AnimatedSeedCount(
                                        value: userPoints,
                                        coinSize: 16,
                                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 11,
                                            fontWeight: FontWeight.w800, color: Color(0xFF33691E)),
                                      ),
                                      Flexible(
                                        child: Text(
                                          showRedeemButton
                                              ? ' points Graine'
                                              : ' points Graine (débloquez la réduction à partir de $pointsThreshold points)',
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 11,
                                              fontWeight: FontWeight.w700, color: Color(0xFF33691E)),
                                        ),
                                      ),
                                    ]),
                                  ),
                                ],
                                if (showRedeemButton) ...[
                                  const SizedBox(width: 8),
                                  _PulsingOfferButton(
                                    label: effectiveRedeemPoints > 0 ? 'Modifier' : 'Offre spéciale',
                                    onTap: () => _openRedeemSheet(context, userPoints, subtotal),
                                  ),
                                ],
                              ]),
                            ),
                          ),
                          // ── Croix pour masquer cette carte pour la session ──
                          Positioned(
                            top: -6,
                            right: -6,
                            child: GestureDetector(
                              onTap: () => setState(() => _hidePointsCard = true),
                              child: Container(
                                width: 22, height: 22,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFFAED581).withValues(alpha: 0.6)),
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withValues(alpha: 0.08),
                                        blurRadius: 4, offset: const Offset(0, 1)),
                                  ],
                                ),
                                child: const Icon(Icons.close_rounded,
                                    size: 13, color: Color(0xFF616161)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Sous-total ($itemCount articles)',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 12,
                            color: Colors.grey[600])),
                    Text('${subtotal.toStringAsFixed(subtotal % 1 == 0 ? 0 : 2)} DH',
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 12,
                            color: Color(0xFF424242))),
                  ]),
                  const SizedBox(height: 3),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Frais de livraison',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 12,
                            color: Colors.grey[600])),
                    const Text('Gratuit',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 12,
                            fontWeight: FontWeight.w800, color: AppColors.primary)),
                  ]),
                  if (effectiveRedeemPoints > 0) ...[
                    const SizedBox(height: 3),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('Réduction points Graine',
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 12,
                              color: Colors.grey[600])),
                      Text('-${discountAmount.toStringAsFixed(discountAmount % 1 == 0 ? 0 : 1)} DH',
                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 12,
                              fontWeight: FontWeight.w700, color: AppColors.primary)),
                    ]),
                  ],
                  const SizedBox(height: 8),
                  Container(height: 1, color: const Color(0xFFEEEEEE)),
                  const SizedBox(height: 8),

                  if (hasOutOfStock)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '⚠️ Certains articles sont en rupture de stock et seront exclus',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 10.5,
                            color: Colors.orange[800]),
                      ),
                    ),

                  // ── Anti-double-achat : message + compte à rebours ──
                  if (_cooldownSecondsRemaining > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(children: [
                          Icon(Icons.timer_outlined, size: 15, color: Colors.orange[800]),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Merci de patienter ${_cooldownSecondsRemaining}s avant '
                              'de passer une nouvelle commande.',
                              style: TextStyle(fontFamily: 'Cairo', fontSize: 11,
                                  fontWeight: FontWeight.w700, color: Colors.orange[800]),
                            ),
                          ),
                        ]),
                      ),
                    ),

                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Total à payer',
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 11,
                                color: Colors.grey[600])),
                        Text('${total.toStringAsFixed(total % 1 == 0 ? 0 : 2)} DH',
                            style: const TextStyle(fontFamily: 'Cairo', fontSize: 19,
                                fontWeight: FontWeight.w900, color: AppColors.primary)),
                      ]),
                    ),
                    ElevatedButton(
                      onPressed: (!isReady || subtotal <= 0 || belowMinOrder ||
                              _cooldownSecondsRemaining > 0)
                          ? null
                          : () => _goToCheckout(context, selectedProductDocs, productsById,
                              selectedFormuleDocs, effectiveRedeemPoints, discountAmount),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        disabledBackgroundColor: Colors.grey[300],
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: _cooldownSecondsRemaining > 0
                          ? Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.timer_outlined, color: Colors.white, size: 16),
                              const SizedBox(width: 6),
                              Text('${_cooldownSecondsRemaining}s',
                                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 14,
                                      fontWeight: FontWeight.w800, color: Colors.white)),
                            ])
                          : Row(mainAxisSize: MainAxisSize.min, children: const [
                              Text('Commander',
                                  style: TextStyle(fontFamily: 'Cairo', fontSize: 14,
                                      fontWeight: FontWeight.w800, color: Colors.white)),
                              SizedBox(width: 6),
                              Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 16),
                            ]),
                    ),
                  ]),
                ]),
              ),
            );
          },
        );
      },
    );
      },
    );
  }

  // ⚠️ Cet écran (cart_screen.dart) ne fait QUE calculer et PROPOSER la
  // réduction — il transmet `redeemedPoints`/`pointsDiscount` à l'écran
  // checkout via `extra`, mais n'écrit jamais lui-même dans Firestore.
  // C'est à l'écran checkout de, dans une même transaction lors de la
  // création de la commande :
  //   • décrémenter users/{uid}.points de `redeemedPoints` ;
  //   • incrémenter users/{uid}.negativePoints de `redeemedPoints` (cumul
  //     historique, ne diminue jamais) ;
  //   • stocker redeemedPoints/pointsDiscount sur orders/{orderId}.
  //
  // ⚠️ `formuleDocs` est transmis séparément : l'écran checkout devra
  // décider comment les traiter (ex. les éclater en lignes de commande à
  // partir de `includedProductIds`, ou les garder comme une ligne "formule"
  // à part sur `orders/{orderId}.items`). Non géré ici — cf. TODO listé
  // dans formules_screen.dart au moment de l'ajout au panier.
  void _goToCheckout(
    BuildContext context,
    List<QueryDocumentSnapshot> productCartDocs,
    Map<String, DocumentSnapshot> productsById,
    List<QueryDocumentSnapshot> formuleDocs,
    int redeemedPoints,
    double discountAmount,
  ) {
    // On reconstruit la liste des documents produits dans le MÊME ORDRE que
    // productCartDocs, garanti correct car on lit depuis la Map indexée par
    // id (et non plus depuis une liste positionnelle potentiellement
    // désynchronisée).
    final productDocs = productCartDocs
        .map((d) => productsById[d.id])
        .whereType<DocumentSnapshot>()
        .toList();

    context.push('/checkout', extra: {
      'cartDocs': productCartDocs,
      'productDocs': productDocs,
      'formuleDocs': formuleDocs,
      'deliveryFee': 0.0,
      'redeemedPoints': redeemedPoints,
      'pointsDiscount': discountAmount,
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  1) BANNER "لا تفوّت هداياك" — remplace l'ancien message neutre
//     ("Ce panier est enregistré sur cet appareil uniquement...").
//     Base psychologique : Loss Aversion (la peur de perdre une opportunité
//     motive davantage qu'une promesse de gain neutre) + halo doré animé
//     + lueur Shimmer qui balaie la carte en continu pour capter l'œil
//     inconscient + flèche qui pulse en direction de l'action attendue.
// ─────────────────────────────────────────────────────────────────────────
class _GuestLoginTeaserBanner extends StatefulWidget {
  const _GuestLoginTeaserBanner();

  @override
  State<_GuestLoginTeaserBanner> createState() =>
      _GuestLoginTeaserBannerState();
}

class _GuestLoginTeaserBannerState extends State<_GuestLoginTeaserBanner>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  late final AnimationController _shimmerCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  late final AnimationController _arrowCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _shimmerCtrl.dispose();
    _arrowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pulse = Tween<double>(begin: 1.0, end: 1.12)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_pulseCtrl);
    final arrowShift = Tween<double>(begin: 0, end: -5)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_arrowCtrl);

    return GestureDetector(
      onTap: () => context.push('/login'),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF8E1), Color(0xFFFFF3E0)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: const Color(0xFFFFCC80), width: 1.3),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF8F00).withValues(alpha: 0.18),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              // ── لمعة ذهبية متحركة تعبر البطاقة (Shimmer) ──
              AnimatedBuilder(
                animation: _shimmerCtrl,
                builder: (context, _) => Positioned.fill(
                  child: CustomPaint(
                    painter:
                        _ShimmerSweepPainter(progress: _shimmerCtrl.value),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
                child: Row(children: [
                  // ── أيقونة هدية نابضة داخل ميدالية ذهبية ──
                  AnimatedBuilder(
                    animation: pulse,
                    builder: (context, child) =>
                        Transform.scale(scale: pulse.value, child: child),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFB300), Color(0xFFFF8F00)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFFFF8F00).withValues(alpha: 0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.card_giftcard_rounded,
                          color: Colors.white, size: 21),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                        'Ne manquez pas vos cadeaux et réductions exclusives 🎁',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFE65100)),
                        ),
                        const SizedBox(height: 3),
                        Text(
                         'Connectez-vous pour récupérer vos points Graine',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 10.8,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                              height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedBuilder(
                    animation: arrowShift,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(arrowShift.value, 0),
                      child: child,
                    ),
                    child: const Icon(Icons.chevron_left_rounded,
                        color: Color(0xFFFF8F00), size: 22),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── رسام لمعة تعبر البطاقة قطرياً بشكل مستمر ──
class _ShimmerSweepPainter extends CustomPainter {
  final double progress; // 0 → 1
  _ShimmerSweepPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final sweepX = -size.width * 0.4 + progress * size.width * 1.4;
    final rect = Rect.fromLTWH(sweepX, 0, size.width * 0.35, size.height);
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.35),
          Colors.white.withValues(alpha: 0.0),
        ],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _ShimmerSweepPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────
//  2) BOUTON "سجّل الدخول واحصل على هداياك" — remplace le bouton neutre
//     ("Se connecter pour profiter des réductions"). Base psychologique :
//     la formulation de l'appel à l'action tourne autour d'un gain concret
//     (cadeau/points) plutôt qu'une action administrative neutre
//     ("se connecter"), avec halo pulsant, icône cadeau qui vibre
//     doucement, et badge "عرض" créant un léger sentiment d'exclusivité.
// ─────────────────────────────────────────────────────────────────────────
class _GuestLoginGiftButton extends StatefulWidget {
  final VoidCallback? onTap;
  const _GuestLoginGiftButton({required this.onTap});

  @override
  State<_GuestLoginGiftButton> createState() => _GuestLoginGiftButtonState();
}

class _GuestLoginGiftButtonState extends State<_GuestLoginGiftButton>
    with TickerProviderStateMixin {
  late final AnimationController _glowCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  late final AnimationController _giftCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _glowCtrl.dispose();
    _giftCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glow = Tween<double>(begin: 0.18, end: 0.42)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_glowCtrl);
    final giftBounce = Tween<double>(begin: 0, end: -3)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_giftCtrl);

    final disabled = widget.onTap == null;

    return AnimatedBuilder(
      animation: glow,
      builder: (context, child) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: disabled
              ? []
              : [
                  BoxShadow(
                    color: const Color(0xFFFF8F00).withValues(alpha: glow.value),
                    blurRadius: 18,
                    spreadRadius: 1,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: child,
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: Ink(
              decoration: BoxDecoration(
                gradient: disabled
                    ? LinearGradient(colors: [Colors.grey[300]!, Colors.grey[300]!])
                    : const LinearGradient(
                        colors: [Color.fromARGB(255, 55, 204, 105), AppColors.primary],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
              ),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: giftBounce,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(0, disabled ? 0 : giftBounce.value),
                        child: child,
                      ),
                      child: Icon(Icons.card_giftcard_rounded,
                          color: disabled ? Colors.grey[500] : Colors.white,
                          size: 20),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Connectez-vous et recevez vos cadeaux 🎁',
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: disabled ? Colors.grey[600] : Colors.white),
                      ),
                    ),
                    if (!disabled) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('Offre',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  ÉCRAN PANIER — VISITEUR NON CONNECTÉ
//  Lit la SELLA المحلية (LocalCartService), affiche les produits en live
//  depuis Firestore (lecture publique de `products`), et propose un bouton
//  "Se connecter" au lieu de "Commander". Dès connexion réussie, la sync
//  automatique (voir LocalCartService) écrit tout dans carts/{uid}/items.
// ─────────────────────────────────────────────────────────────────────────
class _GuestCartScreen extends StatefulWidget {
  const _GuestCartScreen();
  @override
  State<_GuestCartScreen> createState() => _GuestCartScreenState();
}

class _GuestCartScreenState extends State<_GuestCartScreen> {
  @override
  void initState() {
    super.initState();
    LocalCartService.warmUp();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        centerTitle: false,
        title: const Text('Mon panier',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A1A), fontSize: 18)),
      ),
      body: StreamBuilder<List<LocalCartItem>>(
        stream: LocalCartService.watch(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return const _EmptyCartState(uid: '');
          }
          return Column(children: [
            Expanded(child: _GuestCartBody(items: items)),
            _GuestCartSummaryBar(items: items),
          ]);
        },
      ),
    );
  }
}

class _GuestCartBody extends StatelessWidget {
  final List<LocalCartItem> items;
  const _GuestCartBody({required this.items});

  @override
  Widget build(BuildContext context) {
    final productIds = items.map((e) => e.productId).toList();
    return _DocsMapZipper(
      docIds: productIds,
      collection: () => FirebaseFirestore.instance.collection('products'),
      builder: (context, productsById, hasError) {
        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          children: [
            // ✏️ v5 : ancien bandeau informatif neutre remplacé par le
            // bandeau psychologique orienté "perte potentielle" (voir
            // _GuestLoginTeaserBanner plus haut dans ce fichier).
            const _GuestLoginTeaserBanner(),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Builder(builder: (_) {
                  if (hasError) {
                    return _CartItemUnavailable(
                      productId: item.productId,
                      message: 'Erreur de chargement de ce produit',
                      onRemove: () => LocalCartService.removeItem(item.productId),
                    );
                  }
                  final doc = productsById[item.productId];
                  if (doc == null) return const _CartItemSkeleton();
                  if (!doc.exists) {
                    return _CartItemUnavailable(
                      productId: item.productId,
                      message: "Ce produit n'est plus disponible",
                      onRemove: () => LocalCartService.removeItem(item.productId),
                    );
                  }
                  final p = doc.data() as Map<String, dynamic>;
                  final stock = _parseIntOrNull(p['stock']);
                  final outOfStock = stock != null && stock <= 0;
                  return _CartItemCard(
                    productId: item.productId,
                    product: p,
                    qty: item.qty,
                    isSelected: true,
                    outOfStock: outOfStock,
                    maxStock: stock,
                    showCheckbox: false, // ✏️ لا داعي للاختيار عند الزائر
                    onSelect: (_) {},
                    onQtyChange: (q) => LocalCartService.updateQty(item.productId, q),
                    onRemove: () => LocalCartService.removeItem(item.productId),
                  );
                }),
              ),
          ],
        );
      },
    );
  }
}

class _GuestCartSummaryBar extends StatelessWidget {
  final List<LocalCartItem> items;
  const _GuestCartSummaryBar({required this.items});

  double _p(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final productIds = items.map((e) => e.productId).toList();
    return _DocsMapZipper(
      docIds: productIds,
      collection: () => FirebaseFirestore.instance.collection('products'),
      builder: (context, productsById, hasError) {
        double subtotal = 0;
        int itemCount = 0;
        final isReady = !hasError && productIds.every(productsById.containsKey);
        if (isReady) {
          for (final item in items) {
            final doc = productsById[item.productId];
            if (doc == null || !doc.exists) continue;
            final p = doc.data() as Map<String, dynamic>;
            final stock = _parseIntOrNull(p['stock']);
            if (stock != null && stock <= 0) continue;
            subtotal += _p(p['price']) * item.qty;
            itemCount += item.qty;
          }
        }

        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: const BoxDecoration(color: Colors.white,
              boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 8,
                  offset: Offset(0, -2))]),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Sous-total ($itemCount articles)',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 12,
                        color: Colors.grey[600])),
                Text('${subtotal.toStringAsFixed(subtotal % 1 == 0 ? 0 : 2)} DH',
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 12,
                        color: Color(0xFF424242))),
              ]),
              const SizedBox(height: 8),
              Container(height: 1, color: const Color(0xFFEEEEEE)),
              const SizedBox(height: 10),
              // ✏️ v5 : ancien ElevatedButton.icon neutre remplacé par le
              // bouton psychologique orienté "cadeau" (voir
              // _GuestLoginGiftButton plus haut dans ce fichier).
              _GuestLoginGiftButton(
                onTap: !isReady ? null : () => context.push('/login'),
              ),
            ]),
          ),
        );
      },
    );
  }
}