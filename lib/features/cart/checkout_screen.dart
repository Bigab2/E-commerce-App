// TODO Implement this library.// lib/features/cart/checkout_screen.dart
//
// ─────────────────────────────────────────────────────────────────────────────
//  CHECKOUT — crée la commande de façon ATOMIQUE (Firestore Transaction)
//
//  Étapes de la transaction :
//   1. Relit le solde de points Graine ACTUEL de l'utilisateur, champ
//      `users/{uid}.points` (jamais la valeur mise en cache côté client)
//   2. Relit le stock + prix ACTUELS de chaque produit, et les articles de
//      type "formule" du panier (jamais les valeurs mises en cache côté
//      client — empêche tout décalage de prix/stock)
//   3. Vérifie stock >= qty pour chaque article produit
//   4. Recalcule et PLAFONNE les points échangés (redeemedPoints) en
//      fonction du solde réel, du sous-total réel (après exclusion des
//      articles en rupture, produits + formules), ET du montant minimum de
//      commande (99 DH) — jamais la valeur venue de l'écran panier
//   5. Crée orders/{orderId} avec les items "gelés" (copie figée) +
//      redeemedPoints / pointsDiscount réels
//   6. Décrémente products/{id}.stock et incrémente salesCount
//   7. Décrémente users/{uid}.points du nombre de points réellement
//      échangés, ET incrémente users/{uid}.negativePoints du même montant
//      (cumul historique, ne diminue jamais)
//   8. Supprime les items commandés (produits et formules) de
//      carts/{uid}/items
//
//  ⚠️ Toutes les lectures (tx.get) sont effectuées AVANT toute écriture
//  (tx.set/tx.update/tx.delete), comme l'exige Firestore pour les
//  transactions.
//
//  Si une seule vérification échoue (ex: stock insuffisant), TOUTE la
//  transaction est annulée — aucune commande à moitié créée.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mrbeldi/core/theme/app_colors.dart';

class CheckoutScreen extends StatefulWidget {
  final List<QueryDocumentSnapshot> cartDocs;
  // ✏️ Articles de type "formule" sélectionnés dans le panier (voir
  // cart_screen.dart). Optionnel : liste vide si aucune formule.
  final List<QueryDocumentSnapshot> formuleDocs;
  final double deliveryFee;
  // ✏️ NOUVEAU — valeurs proposées par l'écran panier. Elles sont
  // uniquement indicatives : la transaction recalcule et plafonne la
  // valeur réelle en fonction du solde et du sous-total au moment du
  // paiement, donc aucune confiance aveugle n'est accordée à ces valeurs.
  final int redeemedPoints;
  final double pointsDiscount;

  const CheckoutScreen({
    super.key,
    required this.cartDocs,
    this.formuleDocs = const [],
    required this.deliveryFee,
    this.redeemedPoints = 0,
    this.pointsDiscount = 0.0,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

// ─────────────────────────────────────────────────────────────────────────────
//  Petit conteneur pour regrouper (référence, snapshot, quantité) d'un
//  produit lu pendant la transaction — utilisé pour séparer proprement la
//  phase de LECTURE de la phase d'ÉCRITURE (obligatoire avec Firestore).
// ─────────────────────────────────────────────────────────────────────────────
class _ProductRead {
  final DocumentReference ref;
  final DocumentSnapshot snap;
  final int qty;
  final String cartDocId;
  _ProductRead(this.ref, this.snap, this.qty, this.cartDocId);
}

// ✏️ Même principe pour les articles de type "formule" — on relit le
// document panier lui-même (pas de document "produit" séparé), car
// `unitPrice` y est déjà figé.
class _FormuleRead {
  final DocumentReference ref;
  final DocumentSnapshot snap;
  _FormuleRead(this.ref, this.snap);
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  // ⚠️ Ces constantes DOIVENT rester identiques à celles de cart_screen.dart
  // (seedValueDh, minOrderAmount) — la transaction est la source de vérité
  // finale, mais les règles métier elles-mêmes doivent rester cohérentes
  // entre les deux écrans.
  static const double _seedValueDh = 1.5;
  static const double _minOrderAmount = 99.0;
  static const int _purchaseCooldownSeconds = 60;

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  bool _isPlacingOrder = false;
  bool _loadedSavedAddress = false;

  @override
  void initState() {
    super.initState();
    _loadSavedAddress();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _cityCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // يحمّل آخر عنوان استُخدم (إن وُجد) لتسهيل التكرار
  Future<void> _loadSavedAddress() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data();
        final addr = data?['lastDeliveryAddress'] as Map<String, dynamic>?;
        if (addr != null && mounted) {
          _nameCtrl.text = addr['fullName']?.toString() ?? '';
          _phoneCtrl.text = addr['phone']?.toString() ?? '';
          _cityCtrl.text = addr['city']?.toString() ?? '';
          _addressCtrl.text = addr['address']?.toString() ?? '';
        }
      }
    } catch (_) {
      // pas grave si ça échoue — l'utilisateur remplit manuellement
    } finally {
      if (mounted) setState(() => _loadedSavedAddress = true);
    }
  }

  double _p(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
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

  // ─────────────────────────────────────────────────────────────────────────
  //  PLACER LA COMMANDE — Transaction atomique
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _placeOrder() async {
    if (!_formKey.currentState!.validate()) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showError('Vous devez être connecté pour commander');
      return;
    }

    setState(() => _isPlacingOrder = true);

    try {
      final firestore = FirebaseFirestore.instance;

      // ── Anti-double-achat côté serveur : le compte à rebours affiché sur
      //    l'écran panier est purement visuel et peut être contourné (deep
      //    link direct vers /checkout, redémarrage de l'app, etc.). On
      //    revérifie donc ici, juste avant de créer la commande, en lisant
      //    la dernière commande réelle de ce client. ──
      try {
        final lastOrderQuery = await firestore
            .collection('orders')
            .where('userId', isEqualTo: uid)
            .orderBy('createdAt', descending: true)
            .limit(1)
            .get();
        if (lastOrderQuery.docs.isNotEmpty) {
          final lastTs =
              (lastOrderQuery.docs.first.data()['createdAt'] as Timestamp?)
                  ?.toDate();
          if (lastTs != null) {
            final elapsed = DateTime.now().difference(lastTs).inSeconds;
            final remaining = _purchaseCooldownSeconds - elapsed;
            if (remaining > 0) {
              _showError(
                  'Merci de patienter ${remaining}s avant de repasser une commande.');
              setState(() => _isPlacingOrder = false);
              return;
            }
          }
        }
      } catch (e) {
        // Silencieux si l'index composite n'est pas prêt ou si la requête échoue :
        // on ne doit jamais bloquer la création de commande du client.
        debugPrint('⚠️ Verification cooldown skippée: $e');
      }

      final orderRef = firestore.collection('orders').doc();
      final userRef = firestore.collection('users').doc(uid);

      final deliveryAddress = {
        'fullName': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'notes': _notesCtrl.text.trim(),
      };

      final result = await firestore.runTransaction<Map<String, dynamic>>(
        (tx) async {
          // ═══════════════════════════════════════════════════════════════
          //  PHASE 1 — LECTURES UNIQUEMENT (obligatoire avant toute écriture)
          // ═══════════════════════════════════════════════════════════════

          // ── 1a) solde de points Graine réel de l'utilisateur ──
          // ⚠️ CORRECTIF : ce champ s'appelle `points` partout ailleurs dans
          // l'app (cart_screen.dart, etc.). Il
          // était lu ici sous le nom `seeds`, qui n'existe nulle part dans
          // Firestore — ce qui forçait silencieusement `currentSeeds` à 0 et
          // annulait donc TOUJOURS la réduction choisie par le client dans
          // le panier, quel que soit son solde réel.
          final userSnap = await tx.get(userRef);
          final currentPoints = _parseInt(
              userSnap.data()?['points'] ?? userSnap.data()?['seeds']);

          // ── 1b) état actuel (stock/prix) de chaque produit du panier ──
          final List<_ProductRead> productReads = [];
          for (final cartDoc in widget.cartDocs) {
            final cartDocId = cartDoc.id;
            final cartData = cartDoc.data() as Map<String, dynamic>;
            final productId = cartData['productId']?.toString() ?? cartDocId;
            final qty = _parseInt(cartData['qty']);
            final prodRef = firestore.collection('products').doc(productId);
            final prodSnap = await tx.get(prodRef);
            productReads.add(_ProductRead(prodRef, prodSnap, qty, cartDocId));
          }

          // ── 1c) état actuel de chaque FORMULE du panier — on relit le
          //    document panier lui-même (fraîcheur : le client a pu changer
          //    les produits retirés entre l'ajout au panier et le paiement).
          final List<_FormuleRead> formuleReads = [];
          for (final formuleDoc in widget.formuleDocs) {
            final formuleRef = firestore
                .collection('carts').doc(uid)
                .collection('items').doc(formuleDoc.id);
            final formuleSnap = await tx.get(formuleRef);
            formuleReads.add(_FormuleRead(formuleRef, formuleSnap));
          }

          // ═══════════════════════════════════════════════════════════════
          //  PHASE 2 — CALCULS (aucune I/O, juste de la logique)
          // ═══════════════════════════════════════════════════════════════

          final List<Map<String, dynamic>> orderItems = [];
          double subtotal = 0;
          final List<String> outOfStockNames = [];

          for (final r in productReads) {
            if (!r.snap.exists) continue; // المنتج محذوف — يُتجاهل بصمت

            final p = r.snap.data() as Map<String, dynamic>;
            final stock = _parseIntOrNull(p['stock']);
            final price = _p(p['price']);
            final name = p['name']?.toString() ?? '';

            if (stock != null && stock < r.qty) {
              outOfStockNames.add(name);
              continue;
            }

            final lineSubtotal = price * r.qty;
            subtotal += lineSubtotal;

            orderItems.add({
              'productId': r.ref.id,
              'name': name,
              'price': price,
              'imageUrl': p['imageUrl']?.toString() ?? '',
              'qty': r.qty,
              'subtotal': lineSubtotal,
            });
          }

          // ── Ajout des FORMULES au sous-total et aux items de commande.
          //    Leur prix (`unitPrice`) est déjà figé sur le document panier
          //    au moment de l'ajout/modification (voir cart_screen.dart) —
          //    pas de re-lecture produit par produit nécessaire ici. ──
          for (final r in formuleReads) {
            if (!r.snap.exists) continue; // formule retirée entre-temps
            final data = r.snap.data() as Map<String, dynamic>?;
            if (data == null || data['type'] != 'formule') continue;

            final qty = _parseInt(data['quantity']);
            final unitPrice = _p(data['unitPrice']);
            final lineSubtotal = unitPrice * qty;
            subtotal += lineSubtotal;

            orderItems.add({
              'productId': data['formuleId']?.toString() ?? r.ref.id,
              'name': 'Formule ${data['formuleTitle']?.toString() ?? ''}'.trim(),
              'price': unitPrice,
              'imageUrl': data['formuleImageUrl']?.toString() ?? '',
              'qty': qty,
              'subtotal': lineSubtotal,
              'type': 'formule',
              'includedProductIds': data['includedProductIds'],
              'removedProductIds': data['removedProductIds'],
            });
          }

          if (orderItems.isEmpty) {
            throw Exception('NO_ITEMS_AVAILABLE');
          }

          // ── إعادة تحقق/تحديد النقاط المستخدمة فعلياً — لا نثق بالقيمة
          //    القادمة من شاشة السلة، بل نعيد حسابها هنا بناءً على:
          //    • الرصيد الحقيقي الحالي (currentPoints)
          //    • سقف 30% من الـ subtotal الحقيقي (بعد استبعاد النافد)
          //    • ⚠️ CORRECTIF : + سقف عدم النزول تحت الحد الأدنى للطلبية
          //      (minOrderAmount) — كان ناقص هنا وكاين فـ cart_screen فقط،
          //      مما كان يسمح نظرياً بتخفيض يهبط بالسعر تحت 99 DH.
          final byPercentCap = (subtotal * 0.30 / _seedValueDh).floor();
          final byMinOrderCap =
              ((subtotal - _minOrderAmount) / _seedValueDh).floor();
          final maxByCap = min(byPercentCap, byMinOrderCap < 0 ? 0 : byMinOrderCap);
          final cap = min(currentPoints, maxByCap < 0 ? 0 : maxByCap);
          final safeRedeemed = widget.redeemedPoints < 0
              ? 0
              : (widget.redeemedPoints > cap ? cap : widget.redeemedPoints);
          final actualDiscount = safeRedeemed * _seedValueDh;

          final total = (subtotal - actualDiscount + widget.deliveryFee)
              .clamp(0, double.infinity)
              .toDouble();

          // ═══════════════════════════════════════════════════════════════
          //  PHASE 3 — ÉCRITURES UNIQUEMENT
          // ═══════════════════════════════════════════════════════════════

          for (final r in productReads) {
            if (!r.snap.exists) continue;
            final p = r.snap.data() as Map<String, dynamic>;
            final stock = _parseIntOrNull(p['stock']);
            if (stock != null && stock < r.qty) continue; // déjà exclu plus haut

            if (stock != null) {
              tx.update(r.ref, {
                'stock': stock - r.qty,
                'salesCount': FieldValue.increment(r.qty),
              });
            } else {
              tx.update(r.ref, {'salesCount': FieldValue.increment(r.qty)});
            }

            tx.delete(firestore
                .collection('carts').doc(uid)
                .collection('items').doc(r.cartDocId));
          }

          // ── حذف الفورمولات المطلوبة من السلة (لا تأثير لها على مخزون
          //    المنتجات الفردية — السعر كان مثبتاً على وثيقة السلة). ──
          for (final r in formuleReads) {
            if (!r.snap.exists) continue;
            tx.delete(r.ref);
          }

          // ── إنشاء وثيقة الطلب المُجمَّدة ──
          tx.set(orderRef, {
            'userId': uid,
            'items': orderItems,
            'subtotal': subtotal,
            'deliveryFee': widget.deliveryFee,
            'redeemedPoints': safeRedeemed,
            'pointsDiscount': actualDiscount,
            'total': total,
            'paymentMethod': 'cod', // الدفع عند التوصيل — ثابت
            'status': 'pending',
            'statusHistory': [
              {'status': 'pending', 'at': Timestamp.now()},
            ],
            'deliveryAddress': deliveryAddress,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

          // ── خصم النقاط المستخدمة فعلياً + تحديث الرصيد التاريخي +
          //    حفظ العنوان الأخير معاً ──
          // ⚠️ CORRECTIF : كان الكود يكتب فـ `seeds` (حقل غير موجود) بدل
          // `points`، وكان `negativePoints` (السجل التراكمي التاريخي لعدد
          // النقاط المصروفة، يُستعمل من طرف لوحة تحكم الإدارة) غير مكتوب
          // نهائياً. الاثنان مصححان الآن.
          tx.set(
            userRef,
            {
              'lastDeliveryAddress': deliveryAddress,
              if (safeRedeemed > 0) 'points': currentPoints - safeRedeemed,
              if (safeRedeemed > 0)
                'negativePoints': FieldValue.increment(safeRedeemed),
            },
            SetOptions(merge: true),
          );

          return {
            'orderId': orderRef.id,
            'outOfStockNames': outOfStockNames,
            'total': total,
            'redeemedPoints': safeRedeemed,
          };
        },
      );

      if (!mounted) return;

      final outOfStock = (result['outOfStockNames'] as List).cast<String>();
      if (outOfStock.isNotEmpty) {
        _showError('Indisponible et retiré : ${outOfStock.join(", ")}');
      }

      context.go('/order-success/${result['orderId']}');
    } catch (e, stackTrace) {
      debugPrint('❌ Erreur lors de la commande: $e\n$stackTrace');
      if (!mounted) return;
      if (e.toString().contains('NO_ITEMS_AVAILABLE')) {
        _showError('Tous les articles sélectionnés sont en rupture de stock');
      } else {
        _showError('Erreur lors de la commande. Réessayez.');
      }
    } finally {
      if (mounted) setState(() => _isPlacingOrder = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
      backgroundColor: const Color(0xFFE53935),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text('Livraison',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A1A), fontSize: 17)),
      ),
      body: !_loadedSavedAddress
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  // ── Mode de paiement (fixe) ──
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                    ),
                    child: Row(children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                            color: AppColors.primary, shape: BoxShape.circle),
                        child: const Icon(Icons.payments_outlined,
                            color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Paiement à la livraison',
                                style: TextStyle(fontFamily: 'Cairo', fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1A1A1A))),
                            Text('Payez en espèces à la réception',
                                style: TextStyle(fontFamily: 'Cairo', fontSize: 11,
                                    color: Colors.grey[600])),
                          ]),
                      ),
                      const Icon(Icons.check_circle_rounded,
                          color: AppColors.primary, size: 20),
                    ]),
                  ),

                  // ── Récapitulatif points Graine (si applicable) ──
                  if (widget.redeemedPoints > 0) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F8E9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFFAED581).withValues(alpha: 0.6)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.eco_rounded,
                            color: Color(0xFF33691E), size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${widget.redeemedPoints} points Graine seront utilisés '
                            '(-${widget.pointsDiscount.toStringAsFixed(widget.pointsDiscount % 1 == 0 ? 0 : 1)} DH). '
                            'Le montant final sera confirmé après vérification.',
                            style: const TextStyle(fontFamily: 'Cairo', fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF33691E), height: 1.35),
                          ),
                        ),
                      ]),
                    ),
                  ],

                  const SizedBox(height: 20),

                  const Text('Adresse de livraison',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 15,
                          fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
                  const SizedBox(height: 12),

                  _FieldLabel('Nom complet'),
                  _TextInput(
                    controller: _nameCtrl,
                    hint: 'Ex: Ahmed Benali',
                    icon: Icons.person_outline_rounded,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
                  ),
                  const SizedBox(height: 12),

                  _FieldLabel('Téléphone'),
                  _TextInput(
                    controller: _phoneCtrl,
                    hint: 'Ex: 06 12 34 56 78',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Champ requis';
                      if (v.trim().length < 9) return 'Numéro invalide';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  _FieldLabel('Ville'),
                  _TextInput(
                    controller: _cityCtrl,
                    hint: 'Ex: Casablanca',
                    icon: Icons.location_city_outlined,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
                  ),
                  const SizedBox(height: 12),

                  _FieldLabel('Adresse complète'),
                  _TextInput(
                    controller: _addressCtrl,
                    hint: 'Quartier, rue, numéro...',
                    icon: Icons.home_outlined,
                    maxLines: 2,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
                  ),
                  const SizedBox(height: 12),

                  _FieldLabel('Notes pour le livreur (optionnel)'),
                  _TextInput(
                    controller: _notesCtrl,
                    hint: 'Ex: 2ème étage, sonnez fort...',
                    icon: Icons.note_outlined,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: const BoxDecoration(color: Colors.white,
            boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 8,
                offset: Offset(0, -2))]),
        child: SafeArea(
          top: false,
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isPlacingOrder ? null : _placeOrder,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _isPlacingOrder
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.4))
                  : const Text('Confirmer la commande',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 15,
                          fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  WIDGETS DE FORMULAIRE
// ─────────────────────────────────────────────────────────────────────────────
class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(text,
            style: const TextStyle(fontFamily: 'Cairo', fontSize: 12,
                fontWeight: FontWeight.w600, color: Color(0xFF616161))),
      );
}

class _TextInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final int maxLines;
  final String? Function(String?)? validator;

  const _TextInput({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.maxLines = 1,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      style: const TextStyle(fontFamily: 'Cairo', fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontFamily: 'Cairo', color: Color(0xFFBDBDBD)),
        prefixIcon: Icon(icon, size: 19, color: const Color(0xFF9E9E9E)),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE53935))),
      ),
    );
  }
}