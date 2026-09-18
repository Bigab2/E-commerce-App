// lib/core/reviews/review_prompt_manager.dart
//
// ─────────────────────────────────────────────────────────────────────────────
//  RAPPEL AUTOMATIQUE DE NOTATION
//
//  30 secondes après l'ouverture de l'app, on vérifie SILENCIEUSEMENT si
//  l'utilisateur a une commande livrée qui n'a jamais été proposée à la
//  notation. Si oui → on affiche la popup (OrderReviewDialog), peu importe
//  l'écran affiché. Si non → on ne fait strictement rien (aucun message,
//  aucune gêne).
//
//  La popup, une fois soumise, écrit :
//    • orders/{orderId}.rating / reviewComment / reviewed / reviewedAt
//    • products/{productId}.rating (moyenne, via transaction)
//    • products/{productId}/reviews/{autoId} (commentaire détaillé)
//  → voir review_dialog.dart pour le détail complet de l'écriture Firestore.
//
//  ── Installation (une seule fois, dans lib/main.dart) ───────────────────────
//
//    MaterialApp(
//      navigatorKey: appNavigatorKey,
//      builder: (context, child) => ReviewPromptManager(
//        child: child ?? const SizedBox(),
//      ),
//      ...
//    )
//
//  ── Pré-requis Firestore ─────────────────────────────────────────────────────
//  La requête ci-dessous filtre par (userId, status) et trie par updatedAt :
//  un index composite (userId ASC, status ASC, updatedAt DESC) sera demandé
//  par Firestore au premier lancement (lien direct dans les logs de debug).
//  Comme cette vérification est silencieuse, une erreur d'index manquant
//  n'affiche jamais rien à l'utilisateur — elle est juste journalisée.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mrbeldi/core/navigation/app_navigator.dart' show appNavigatorKey;

import 'review_dialog.dart';

class ReviewPromptManager extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const ReviewPromptManager({
    super.key,
    required this.child,
    this.delay = const Duration(seconds: 30),
  });

  @override
  State<ReviewPromptManager> createState() => _ReviewPromptManagerState();
}

class _ReviewPromptManagerState extends State<ReviewPromptManager> {
  Timer? _timer;
  bool _checkedThisSession = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, _maybeShowReviewPrompt);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _maybeShowReviewPrompt() async {
    if (_checkedThisSession) return;
    _checkedThisSession = true;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('orders')
          .where('userId', isEqualTo: uid)
          .where('status', isEqualTo: 'delivered')
          .orderBy('updatedAt', descending: true)
          .limit(8) // on regarde quelques commandes récentes livrées
          .get();

      // Filtrage client : la première commande livrée jamais proposée à la
      // notation (reviewPromptedAt absent ET reviewed != true). On évite
      // whereIn/isNull côté serveur pour ne pas exiger un index
      // supplémentaire trop spécifique.
      QueryDocumentSnapshot<Map<String, dynamic>>? target;
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['reviewPromptedAt'] == null && data['reviewed'] != true) {
          target = doc;
          break;
        }
      }

      if (target == null) return;

      // On marque IMMÉDIATEMENT la commande comme "proposée" pour ne plus
      // jamais la re-proposer, même si l'utilisateur ferme l'app avant de
      // répondre à la popup.
      await target.reference.update({
        'reviewPromptedAt': FieldValue.serverTimestamp(),
      });

      final ctx = appNavigatorKey.currentState?.overlay?.context;
      if (ctx == null || !ctx.mounted) return;

      final data = target.data();
      final total = (data['total'] as num?)?.toDouble();
      final shortId = target.id.length >= 8
          ? target.id.substring(0, 8).toUpperCase()
          : target.id.toUpperCase();

      // Articles de la commande — indispensables pour que la popup
      // répercute la note et le commentaire sur chaque produit concerné
      // (voir OrderReviewDialog._applyProductRating).
      final rawItems = data['items'];
      final items = rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];

      await OrderReviewDialog.show(
        ctx,
        orderId: target.id,
        orderLabel: total != null
            ? 'Commande #$shortId · ${total.toStringAsFixed(2)} DH'
            : 'Commande #$shortId',
        items: items,
      );
    } catch (e) {
      // Vérification silencieuse : on ne montre jamais d'erreur à
      // l'utilisateur pour ce rappel de confort. On journalise seulement
      // pour le debug (ex : lien d'index Firestore manquant).
      debugPrint('ReviewPromptManager: vérification silencieuse échouée: $e');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}