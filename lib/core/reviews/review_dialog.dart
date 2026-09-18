// lib/core/reviews/review_dialog.dart
//
// ─────────────────────────────────────────────────────────────────────────────
//  POPUP DE NOTATION — vivante, ludique, vert + orange + étoiles dorées.
//
//  Utilisation :
//    OrderReviewDialog.show(
//      context,
//      orderId: id,
//      orderLabel: 'Commande #ABC123',
//    );
//
//  Écrit dans Firestore, sur le document orders/{orderId} :
//    • rating           : int (1-5)
//    • reviewComment    : String?
//    • reviewed         : true
//    • reviewedAt       : Timestamp (serveur)
//    • reviewPromptedAt : Timestamp (serveur) — si pas déjà défini
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mrbeldi/core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Cette popup utilise AppColors (identité visuelle officielle) pour le vert
//  et l'orange. Seules les étoiles restent dorées — convention universelle
//  de notation, indépendante de la charte de l'app — et une nuance d'orange
//  plus profonde (non définie dans AppColors) sert uniquement à la
//  profondeur du dégradé du bouton et de l'en-tête.
// ─────────────────────────────────────────────────────────────────────────────
class _ReviewAccents {
  static const gold      = Color(0xFFFFC107);
  static const goldDim   = Color(0xFFE0C08A);
  static const orangeDeep = Color(0xFFE86A00); // nuance plus profonde de AppColors.accent
}

class OrderReviewDialog extends StatefulWidget {
  final String orderId;
  final String? orderLabel;

  /// Les articles de la commande (chacun avec au minimum `productId`).
  /// Utilisés pour répercuter la note sur chaque produit concerné.
  final List<Map<String, dynamic>> items;

  final VoidCallback? onSubmitted;
  final VoidCallback? onSkipped;

  const OrderReviewDialog({
    super.key,
    required this.orderId,
    this.orderLabel,
    this.items = const [],
    this.onSubmitted,
    this.onSkipped,
  });

  /// Affiche la popup avec une animation d'entrée façon "jeu vidéo"
  /// (zoom + rebond), peu importe l'écran actuellement affiché.
  static Future<void> show(
    BuildContext context, {
    required String orderId,
    String? orderLabel,
    List<Map<String, dynamic>> items = const [],
    VoidCallback? onSubmitted,
    VoidCallback? onSkipped,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Notation de commande',
      barrierColor: Colors.black.withOpacity(0.55),
      transitionDuration: const Duration(milliseconds: 380),
      pageBuilder: (context, anim1, anim2) => OrderReviewDialog(
        orderId: orderId,
        orderLabel: orderLabel,
        items: items,
        onSubmitted: onSubmitted,
        onSkipped: onSkipped,
      ),
      transitionBuilder: (context, anim, secondaryAnim, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.elasticOut);
        return Opacity(
          opacity: anim.value.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.7 + (0.3 * curved.value.clamp(0.0, 1.3)),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<OrderReviewDialog> createState() => _OrderReviewDialogState();
}

class _OrderReviewDialogState extends State<OrderReviewDialog>
    with SingleTickerProviderStateMixin {
  int _rating = 0;
  final _commentCtrl = TextEditingController();
  bool _submitting = false;

  late final AnimationController _starPulse;

  static const _messages = {
    0: ('Notez votre expérience', AppColors.textPrimary),
    1: ('On peut mieux faire 😕', AppColors.error),
    2: ('Pas terrible 🙁', _ReviewAccents.orangeDeep),
    3: ('Correct 🙂', AppColors.accent),
    4: ('Très bien ! 😃', AppColors.primary),
    5: ('Excellent ! 🤩🎉', AppColors.primaryDark),
  };

  @override
  void initState() {
    super.initState();
    _starPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
  }

  @override
  void dispose() {
    _starPulse.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  void _selectStar(int value) {
    HapticFeedback.selectionClick();
    setState(() => _rating = value);
    _starPulse.forward(from: 0);
    if (value == 5) {
      HapticFeedback.mediumImpact();
    }
  }

  Future<void> _skip() async {
    widget.onSkipped?.call();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _submit() async {
    if (_rating == 0 || _submitting) return;
    setState(() => _submitting = true);
    HapticFeedback.lightImpact();

    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .update({
        'rating': _rating,
        'reviewComment': _commentCtrl.text.trim().isEmpty
            ? null
            : _commentCtrl.text.trim(),
        'reviewed': true,
        'reviewedAt': FieldValue.serverTimestamp(),
        // Si l'utilisateur note manuellement sans être passé par le rappel
        // automatique, on marque quand même reviewPromptedAt pour que le
        // rappel ne le sollicite plus jamais pour cette commande.
        'reviewPromptedAt': FieldValue.serverTimestamp(),
      });

      // FIX : on récupère le nom complet du client depuis SA PROPRE
      // commande — orders/{widget.orderId} — pendant que les security
      // rules l'y autorisent encore (resource.data.userId ==
      // request.auth.uid, car c'est lui-même l'auteur de cette commande
      // au moment où il soumet sa notation). On ne pourra plus jamais
      // relire ce champ pour un AUTRE utilisateur plus tard (et ce n'est
      // pas souhaitable côté vie privée), donc on le capture maintenant
      // et on l'écrit directement sur chaque review créée ci-dessous.
      //
      // ⚠️ CORRECTIF : `fullName` n'est PAS un champ top-level sur
      // orders/{orderId}. Il est imbriqué dans `deliveryAddress` (voir
      // checkout_screen.dart : deliveryAddress = {fullName, phone, city,
      // address, notes}). L'ancien code lisait
      // `orderSnap.data()?['fullName']` directement, ce qui retournait
      // toujours null et empêchait le nom de s'afficher sur les reviews.
      String? reviewerFullName;
      try {
        final orderSnap = await FirebaseFirestore.instance
            .collection('orders')
            .doc(widget.orderId)
            .get();
        final deliveryAddress =
            orderSnap.data()?['deliveryAddress'] as Map<String, dynamic>?;
        final fn = deliveryAddress?['fullName']?.toString().trim();
        if (fn != null && fn.isNotEmpty) reviewerFullName = fn;
      } catch (_) {
        // Pas bloquant : les reviews seront simplement créées sans nom
        // affichable (repli sur "Client" côté UI) si ça échoue.
      }

      // Répercute la note + le commentaire sur chaque produit de la commande.
      // ⚠️ Les articles de type 'formule' (voir cart_screen.dart /
      // checkout_screen.dart) portent un `productId` qui est en réalité
      // l'ID de la FORMULE (ex: "formulesBeldi"), pas un vrai document
      // products/{id}. Si on le traitait comme un produit normal, on
      // créerait silencieusement un faux document dans `products`. On
      // détecte ces articles via `item['type'] == 'formule'` et on propage
      // plutôt la note à chacun des produits réellement inclus dans la
      // formule (`includedProductIds`).
      final productIds = <String>{};
      for (final item in widget.items) {
        final isFormule = item['type'] == 'formule';
        if (isFormule) {
          final included = item['includedProductIds'];
          if (included is List) {
            productIds.addAll(included
                .map((e) => e?.toString().trim() ?? '')
                .where((id) => id.isNotEmpty));
          }
          continue;
        }
        final id = (item['productId'] as String?)?.trim();
        if (id != null && id.isNotEmpty) productIds.add(id);
      }

      await Future.wait(
        productIds.map((id) => _applyProductRating(id, reviewerFullName)),
      );

      widget.onSubmitted?.call();
    } catch (_) {
      // On ne bloque pas l'utilisateur : la note reste visible, il peut
      // réessayer. On évite un crash silencieux ici.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Échec de l\'envoi, réessayez.')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }

    if (mounted) Navigator.of(context).pop();
  }

  /// Met à jour l'agrégat de note du produit (`ratingCount`, `ratingSum`,
  /// `rating` = moyenne) via une transaction (évite les pertes en cas de
  /// notations simultanées), puis ajoute le commentaire dans la
  /// sous-collection `products/{productId}/reviews`.
  ///
  /// [reviewerFullName] est capturé une seule fois dans `_submit()`, tant
  /// que les security rules autorisent encore la lecture de la commande
  /// (c'est l'auteur qui note sa propre commande). On l'enregistre tel
  /// quel sous `userName` sur la review — c'est l'écran d'affichage
  /// (product_detail_screen.dart) qui se charge ensuite de le masquer
  /// (ex: "Moham•••") pour l'affichage public.
  ///
  /// Échoue silencieusement pour un produit donné : on ne veut jamais
  /// bloquer ou faire échouer toute la notation pour un seul produit
  /// problématique (ex : productId qui ne correspond à aucun document réel).
  Future<void> _applyProductRating(String productId, String? reviewerFullName) async {
    final productRef =
        FirebaseFirestore.instance.collection('products').doc(productId);

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(productRef);
        final data = snap.data() ?? <String, dynamic>{};
        final currentCount = (data['ratingCount'] as num?)?.toInt() ?? 0;
        final currentSum = (data['ratingSum'] as num?)?.toDouble() ?? 0.0;

        final newCount = currentCount + 1;
        final newSum = currentSum + _rating;

        tx.set(
          productRef,
          {
            'ratingCount': newCount,
            'ratingSum': newSum,
            'rating': newSum / newCount,
          },
          SetOptions(merge: true),
        );
      });

      await productRef.collection('reviews').add({
        'rating': _rating,
        'comment': _commentCtrl.text.trim().isEmpty
            ? null
            : _commentCtrl.text.trim(),
        'orderId': widget.orderId,
        'userId': FirebaseAuth.instance.currentUser?.uid,
        if (reviewerFullName != null) 'userName': reviewerFullName,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint(
          'OrderReviewDialog: échec de mise à jour du produit $productId: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final dialogWidth = w > 480 ? 420.0 : w * 0.9;
    final (message, messageColor) = _messages[_rating]!;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: dialogWidth,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── En-tête dégradé vert → orange ──────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 26),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryDark,
                    AppColors.primary,
                    AppColors.accent,
                  ],
                  stops: [0.0, 0.55, 1.0],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('🎉', style: TextStyle(fontSize: 34)),
                      const SizedBox(height: 8),
                      const Text(
                        'Votre commande est arrivée !',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (widget.orderLabel != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          widget.orderLabel!,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Positioned(
                    top: -6,
                    right: -6,
                    child: _CloseButton(onTap: _skip),
                  ),
                ],
              ),
            ),

            // ── Corps ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
              child: Column(
                children: [
                  // Message dynamique animé selon la note
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, anim) => ScaleTransition(
                      scale: anim,
                      child: FadeTransition(opacity: anim, child: child),
                    ),
                    child: Text(
                      message,
                      key: ValueKey(_rating),
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: messageColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // ── Étoiles dorées interactives ──────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final value = i + 1;
                      final filled = value <= _rating;
                      return GestureDetector(
                        onTap: () => _selectStar(value),
                        child: AnimatedScale(
                          scale: filled && value == _rating ? 1.22 : 1.0,
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.elasticOut,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Icon(
                              filled ? Icons.star_rounded : Icons.star_border_rounded,
                              size: 42,
                              color: filled
                                  ? _ReviewAccents.gold
                                  : _ReviewAccents.goldDim,
                              shadows: filled
                                  ? [
                                      Shadow(
                                        color: _ReviewAccents.gold
                                            .withOpacity(0.55),
                                        blurRadius: 12,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 20),

                  // ── Commentaire optionnel ────────────────────────────
                  TextField(
                    controller: _commentCtrl,
                    maxLines: 3,
                    minLines: 2,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: InputDecoration(
                      hintText: 'Un commentaire ? (optionnel)',
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13.5),
                      filled: true,
                      fillColor: const Color(0xFFF6F7F9),
                      contentPadding: const EdgeInsets.all(14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                            color: AppColors.primary, width: 1.4),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Boutons ───────────────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: _submitting ? null : _skip,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            foregroundColor: Colors.grey.shade600,
                          ),
                          child: const Text(
                            'Plus tard',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: _SubmitButton(
                          enabled: _rating > 0 && !_submitting,
                          loading: _submitting,
                          onTap: _submit,
                        ),
                      ),
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

// ─────────────────────────────────────────────────────────────────────────────
//  BOUTON ENVOYER — dégradé orange → vert, réaction au tap (façon jeu)
// ─────────────────────────────────────────────────────────────────────────────
class _SubmitButton extends StatefulWidget {
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;
  const _SubmitButton({
    required this.enabled,
    required this.loading,
    required this.onTap,
  });

  @override
  State<_SubmitButton> createState() => _SubmitButtonState();
}

class _SubmitButtonState extends State<_SubmitButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: widget.enabled ? (_) => setState(() => _pressed = false) : null,
      onTap: widget.enabled ? widget.onTap : null,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: widget.enabled
                ? const LinearGradient(
                    colors: [_ReviewAccents.orangeDeep, AppColors.primary],
                  )
                : null,
            color: widget.enabled ? null : Colors.grey.shade300,
            boxShadow: widget.enabled
                ? [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: widget.loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : Text(
                  'Envoyer',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: widget.enabled ? Colors.white : Colors.grey.shade500,
                  ),
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  BOUTON FERMER (X) — coin haut-droit, façon badge de jeu
// ─────────────────────────────────────────────────────────────────────────────
class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(Icons.close_rounded, size: 18, color: AppColors.textPrimary),
      ),
    );
  }
}