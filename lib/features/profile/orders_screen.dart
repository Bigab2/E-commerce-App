// lib/features/profile/orders_screen.dart
//
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mrbeldi/core/reviews/review_dialog.dart';
import 'package:mrbeldi/core/theme/app_colors.dart';
import 'package:mrbeldi/routes/app_routes.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  PALETTE — identité "nature" alignée sur AppColors (vert organique dominant),
//  avec une déclinaison de teintes naturelles (terre, eau, feuillage) pour les
//  statuts, afin de garder une lecture claire tout en restant cohérent avec
//  l'identité visuelle globale de l'app.
// ─────────────────────────────────────────────────────────────────────────────
class _Palette {
  static const ink     = AppColors.textPrimary;
  static const inkSoft = AppColors.textSecondary;
  static const bg      = AppColors.background;
  static const card    = AppColors.surface;
  static const border  = AppColors.border;

  // Header / éléments structurants — dégradé vert forêt → vert organique
  static const headerStart = AppColors.primaryDark;
  static const headerMid   = Color(0xFF256B48);
  static const headerEnd   = AppColors.primary;

  // Accent principal (boutons, totaux, étape active)
  static const accent     = AppColors.primary;
  static const accentSoft = Color(0xFFE6F4EC); // vert très clair (fond icônes/placeholders)

  // Statuts — palette nature cohérente
  static const pendingFg    = AppColors.warning;    // ambre — en attente
  static const pendingBg    = Color(0xFFFFF3E0);
  static const processingFg = AppColors.secondary;  // vert tendre — en préparation
  static const processingBg = Color(0xFFEAF6F0);
  static const shippingFg   = Color(0xFF2A7DA8);    // bleu "eau" — en livraison
  static const shippingBg   = Color(0xFFE7F3F8);
  static const deliveredFg  = AppColors.success;    // vert franc — livré
  static const deliveredBg  = Color(0xFFE3F3E9);
  static const cancelledFg  = AppColors.error;
  static const cancelledBg  = Color(0xFFFBEAEA);
}

// ── Constantes de statut ─────────────────────────────────────────────────────
class _Status {
  static const pending    = 'pending';
  static const processing = 'processing';
  static const shipping   = 'shipping';
  static const delivered  = 'delivered';
  static const cancelled  = 'cancelled';
}

// ─────────────────────────────────────────────────────────────────────────────
//  ÉCRAN PRINCIPAL
// ─────────────────────────────────────────────────────────────────────────────
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin {
  // Filtres par onglet
  static const _tabs = [
    ('Tout',     null),
    ('En cours', [_Status.pending, _Status.processing, _Status.shipping]),
    ('Livrées',  [_Status.delivered]),
    ('Annulées', [_Status.cancelled]),
  ];

  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;

    // Utilisateur non connecté : on évite une query Firestore avec un uid vide
    // (qui ne renverrait jamais rien mais laisserait un loader silencieux).
    if (uid == null || uid.isEmpty) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
        ),
        child: Scaffold(
          backgroundColor: _Palette.bg,
          body: _NotSignedIn(w: w),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _Palette.bg,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          // ── AppBar avec onglets ───────────────────────────────────────
          SliverAppBar(
            expandedHeight: h * 0.16,
            pinned: true,
            backgroundColor: _Palette.headerMid,
            systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
            ),
            elevation: 0,
            leadingWidth: 52,
            leading: Padding(
              padding: const EdgeInsets.only(left: 12, top: 4),
              child: _RoundBackButton(
                onTap: () => Navigator.maybePop(context),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _Palette.headerStart,
                      _Palette.headerMid,
                      _Palette.headerEnd,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(w * 0.05, 0, w * 0.05, h * 0.07),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            width: w * 0.1,
                            height: w * 0.1,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.receipt_long_rounded,
                                color: Colors.white, size: w * 0.055),
                          ),
                          SizedBox(width: w * 0.03),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Mes commandes',
                                style: TextStyle(
                                  fontSize: w * 0.055,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              Text(
                                'Suivez vos achats en temps réel',
                                style: TextStyle(
                                  fontSize: w * 0.03,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(46),
              child: Container(
                color: _Palette.headerMid,
                child: TabBar(
                  controller: _tabCtrl,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorColor: Colors.white,
                  indicatorWeight: 2.5,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white54,
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: w * 0.033,
                  ),
                  unselectedLabelStyle: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: w * 0.033,
                  ),
                  tabs: _tabs.map((t) => Tab(text: t.$1)).toList(),
                ),
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabCtrl,
          children: _tabs.map((tab) {
            return _OrdersList(
              uid: uid,
              statusFilter: tab.$2,
              w: w,
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  LISTE DES COMMANDES (avec filtre optionnel)
// ─────────────────────────────────────────────────────────────────────────────
class _OrdersList extends StatelessWidget {
  final String uid;
  final List<String>? statusFilter;
  final double w;

  const _OrdersList({
    required this.uid,
    required this.statusFilter,
    required this.w,
  });

  @override
  Widget build(BuildContext context) {
    // Construction de la query Firestore.
    // ⚠️ where('userId') + orderBy('createdAt') nécessite un index composite
    // Firestore (userId ASC, createdAt DESC). S'il manque, Firestore renvoie
    // une erreur contenant un lien direct pour le créer — vérifie la console
    // de debug au premier lancement.
    final query = FirebaseFirestore.instance
        .collection('orders')
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _ErrorView(w: w, error: snap.error);
        }

        // Filtrage client si onglet autre que "Tout"
        var docs = snap.data?.docs ?? [];
        if (statusFilter != null) {
          docs = docs.where((d) {
            final s = d.data()['status'] as String? ?? '';
            return statusFilter!.contains(s);
          }).toList();
        }

        if (docs.isEmpty) {
          return _EmptyOrders(w: w, filtered: statusFilter != null);
        }

        return ListView.separated(
          padding: EdgeInsets.fromLTRB(w * 0.04, w * 0.04, w * 0.04, w * 0.12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => SizedBox(height: w * 0.035),
          itemBuilder: (_, i) => _OrderCard(
            key: ValueKey(docs[i].id),
            data: docs[i].data(),
            id: docs[i].id,
            w: w,
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  CARTE COMMANDE — complète et professionnelle
// ─────────────────────────────────────────────────────────────────────────────
class _OrderCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final String id;
  final double w;

  const _OrderCard({
    super.key,
    required this.data,
    required this.id,
    required this.w,
  });

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _expanded = false;

  // ── Statut ───────────────────────────────────────────────────────────────
  static const _statusConfig = {
    _Status.pending: (
      label: 'En attente',
      icon: Icons.hourglass_empty_rounded,
      color: _Palette.pendingFg,
      bg: _Palette.pendingBg,
      step: 0,
    ),
    _Status.processing: (
      label: 'En préparation',
      icon: Icons.inventory_2_rounded,
      color: _Palette.processingFg,
      bg: _Palette.processingBg,
      step: 1,
    ),
    _Status.shipping: (
      label: 'En livraison',
      icon: Icons.local_shipping_rounded,
      color: _Palette.shippingFg,
      bg: _Palette.shippingBg,
      step: 2,
    ),
    _Status.delivered: (
      label: 'Livré',
      icon: Icons.check_circle_rounded,
      color: _Palette.deliveredFg,
      bg: _Palette.deliveredBg,
      step: 3,
    ),
    _Status.cancelled: (
      label: 'Annulé',
      icon: Icons.cancel_rounded,
      color: _Palette.cancelledFg,
      bg: _Palette.cancelledBg,
      step: -1,
    ),
  };

  static const _fallbackCfg = (
    label: 'Statut inconnu',
    icon: Icons.help_outline_rounded,
    color: _Palette.pendingFg,
    bg: _Palette.pendingBg,
    step: 0,
  );

  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    final d = widget.data;
    final id = widget.id;

    final status = d['status'] as String? ?? _Status.pending;
    final cfg = _statusConfig[status] ?? _fallbackCfg;

    final total = (d['total'] as num?)?.toDouble() ?? 0.0;
    final deliveryFee = (d['deliveryFee'] as num?)?.toDouble() ?? 0.0;
    final paymentMethod = d['paymentMethod'] as String?;
    final ts = d['createdAt'] as Timestamp?;
    final trackingId = d['trackingId'] as String?;
    final reviewed = d['reviewed'] == true; // ← commande déjà notée ?

    // Articles de la commande
    final rawItems = d['items'];
    final List<Map<String, dynamic>> items = () {
      if (rawItems is! List) return <Map<String, dynamic>>[];
      return rawItems
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }();
    final itemsCount =
        (d['itemsCount'] as num?)?.toInt() ?? items.length;

    // Adresse de livraison — c'est une Map dans Firestore, pas une String.
    final rawAddress = d['deliveryAddress'];
    final Map<String, dynamic> deliveryAddress =
        rawAddress is Map ? Map<String, dynamic>.from(rawAddress) : const {};

    final dateStr = ts != null ? _formatDate(ts.toDate()) : '—';
    final shortId = id.length >= 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase();

    return Container(
      decoration: BoxDecoration(
        color: _Palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Palette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── En-tête commande ───────────────────────────────────────────
          Padding(
            padding: EdgeInsets.all(w * 0.04),
            child: Row(
              children: [
                Container(
                  width: w * 0.12,
                  height: w * 0.12,
                  decoration: BoxDecoration(
                    color: cfg.bg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Icon(cfg.icon, color: cfg.color, size: w * 0.055),
                  ),
                ),
                SizedBox(width: w * 0.03),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Commande #$shortId',
                        style: TextStyle(
                          fontSize: w * 0.036,
                          fontWeight: FontWeight.w800,
                          color: _Palette.ink,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: w * 0.005),
                      Text(
                        '$dateStr  •  $itemsCount article${itemsCount > 1 ? "s" : ""}',
                        style: TextStyle(
                          fontSize: w * 0.028,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${total.toStringAsFixed(2)} DH',
                  style: TextStyle(
                    fontSize: w * 0.042,
                    fontWeight: FontWeight.w900,
                    color: _Palette.accent,
                  ),
                ),
              ],
            ),
          ),

          // ── Barre de progression (sauf annulé) ────────────────────────
          if (status != _Status.cancelled)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: w * 0.04),
              child: _ProgressStepper(currentStep: cfg.step, w: w),
            ),

          // ── Badge statut + actions ─────────────────────────────────────
          Padding(
            padding:
                EdgeInsets.symmetric(horizontal: w * 0.04, vertical: w * 0.035),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: w * 0.03, vertical: w * 0.012),
                  decoration: BoxDecoration(
                    color: cfg.bg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cfg.color.withOpacity(0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(cfg.icon, size: w * 0.033, color: cfg.color),
                      SizedBox(width: w * 0.015),
                      Text(
                        cfg.label,
                        style: TextStyle(
                          fontSize: w * 0.03,
                          fontWeight: FontWeight.w700,
                          color: cfg.color,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (status == _Status.shipping &&
                    trackingId != null &&
                    trackingId.isNotEmpty)
                  _ActionBtn(
                    label: 'Suivre',
                    icon: Icons.location_on_rounded,
                    color: _Palette.shippingFg,
                    onTap: () => context.push(Routes.orderTrackingPath(id)),
                    w: w,
                  )
                else if (status == _Status.delivered)
                  (reviewed
                      ? _ReviewedBadge(w: w)
                      : _ActionBtn(
                          label: 'Laisser un avis',
                          icon: Icons.star_rounded,
                          color: AppColors.accent,
                          onTap: () => OrderReviewDialog.show(
                            context,
                            orderId: id,
                            orderLabel: 'Commande #$shortId',
                            items: items, // ← permet de répercuter la note sur chaque produit
                          ),
                          w: w,
                        )),
                SizedBox(width: w * 0.02),
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Container(
                    padding: EdgeInsets.all(w * 0.02),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: w * 0.05,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Détails expandables ────────────────────────────────────────
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState:
                _expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: _OrderDetails(
              items: items,
              deliveryAddress: deliveryAddress,
              trackingId: trackingId,
              paymentMethod: paymentMethod,
              total: total,
              deliveryFee: deliveryFee,
              w: w,
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}

// ─────────────────────────────────────────────────────────────────────────────
//  STEPPER DE PROGRESSION (4 étapes : Reçu → Préparé → Expédié → Livré)
// ─────────────────────────────────────────────────────────────────────────────
class _ProgressStepper extends StatelessWidget {
  final int currentStep; // 0=pending 1=processing 2=shipping 3=delivered
  final double w;

  const _ProgressStepper({required this.currentStep, required this.w});

  static const _steps = ['Reçu', 'Préparé', 'Expédié', 'Livré'];
  static const _icons = [
    Icons.receipt_long_rounded,
    Icons.inventory_2_rounded,
    Icons.local_shipping_rounded,
    Icons.check_circle_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    // currentStep ne devrait jamais être négatif ici (le stepper n'est pas
    // affiché pour les commandes annulées), mais on se protège quand même.
    final safeStep = currentStep.clamp(0, _steps.length - 1);

    return Padding(
      padding: EdgeInsets.only(bottom: w * 0.03),
      child: Row(
        children: List.generate(_steps.length * 2 - 1, (index) {
          if (index.isOdd) {
            final stepIndex = index ~/ 2;
            final isDone = stepIndex < safeStep;
            return Expanded(
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  color: isDone ? _Palette.accent : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }

          final stepIndex = index ~/ 2;
          final isDone = stepIndex <= safeStep;
          final isCurrent = stepIndex == safeStep;

          return Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: w * (isCurrent ? 0.085 : 0.07),
                height: w * (isCurrent ? 0.085 : 0.07),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone ? _Palette.accent : Colors.grey.shade200,
                  border: isCurrent
                      ? Border.all(
                          color: _Palette.accent.withOpacity(0.3), width: 3)
                      : null,
                ),
                child: Icon(
                  _icons[stepIndex],
                  size: w * (isCurrent ? 0.04 : 0.032),
                  color: isDone ? Colors.white : Colors.grey.shade400,
                ),
              ),
              SizedBox(height: w * 0.01),
              Text(
                _steps[stepIndex],
                style: TextStyle(
                  fontSize: w * 0.024,
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                  color: isDone ? _Palette.ink : Colors.grey.shade400,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  DÉTAILS EXPANDABLE (articles, adresse, paiement, suivi)
// ─────────────────────────────────────────────────────────────────────────────
class _OrderDetails extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final Map<String, dynamic> deliveryAddress;
  final String? trackingId;
  final String? paymentMethod;
  final double total;
  final double deliveryFee;
  final double w;

  const _OrderDetails({
    required this.items,
    required this.deliveryAddress,
    required this.trackingId,
    required this.paymentMethod,
    required this.total,
    required this.deliveryFee,
    required this.w,
  });

  String _paymentLabel(String? method) {
    switch (method) {
      case 'cod':
        return 'Paiement à la livraison';
      case 'card':
        return 'Carte bancaire';
      default:
        return method == null || method.isEmpty ? 'Non spécifié' : method;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fullName = deliveryAddress['fullName'] as String?;
    final phone = deliveryAddress['phone'] as String?;
    final addressLine = deliveryAddress['address'] as String?;
    final city = deliveryAddress['city'] as String?;
    final notes = deliveryAddress['notes'] as String?;

    final hasAddress =
        (addressLine != null && addressLine.trim().isNotEmpty) ||
            (city != null && city.trim().isNotEmpty);

    final addressText = [
      if (addressLine != null && addressLine.trim().isNotEmpty) addressLine,
      if (city != null && city.trim().isNotEmpty) city,
    ].join(', ');

    final subtotal = (total - deliveryFee).clamp(0, double.infinity);

    return Container(
      decoration: BoxDecoration(
        color: _Palette.bg,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        border: Border(top: BorderSide(color: _Palette.border)),
      ),
      padding: EdgeInsets.all(w * 0.04),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Articles ────────────────────────────────────────────────
          if (items.isNotEmpty) ...[
            _DetailLabel(label: 'Articles commandés', icon: Icons.list_alt_rounded, w: w),
            SizedBox(height: w * 0.025),
            ...items.map((item) => _ItemRow(item: item, w: w)),
            Divider(height: w * 0.05, color: Colors.grey.shade200),
          ],

          // ── Récapitulatif prix ────────────────────────────────────────
          _PriceRow(label: 'Sous-total', value: subtotal.toDouble(), w: w),
          if (deliveryFee > 0)
            _PriceRow(label: 'Frais de livraison', value: deliveryFee, w: w),
          Padding(
            padding: EdgeInsets.symmetric(vertical: w * 0.015),
            child: Divider(height: 1, color: Colors.grey.shade200),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total payé',
                style: TextStyle(
                  fontSize: w * 0.032,
                  fontWeight: FontWeight.w700,
                  color: _Palette.ink,
                ),
              ),
              Text(
                '${total.toStringAsFixed(2)} DH',
                style: TextStyle(
                  fontSize: w * 0.036,
                  fontWeight: FontWeight.w900,
                  color: _Palette.accent,
                ),
              ),
            ],
          ),

          // ── Paiement ────────────────────────────────────────────────
          SizedBox(height: w * 0.035),
          _DetailLabel(label: 'Paiement', icon: Icons.payments_rounded, w: w),
          SizedBox(height: w * 0.015),
          _InfoChip(
            text: _paymentLabel(paymentMethod),
            icon: Icons.account_balance_wallet_rounded,
            w: w,
          ),

          // ── Adresse ─────────────────────────────────────────────────
          if (hasAddress) ...[
            SizedBox(height: w * 0.035),
            _DetailLabel(
                label: 'Adresse de livraison',
                icon: Icons.location_on_rounded,
                w: w),
            SizedBox(height: w * 0.015),
            _InfoChip(
              text: addressText,
              icon: Icons.home_rounded,
              w: w,
            ),
            if (fullName != null && fullName.trim().isNotEmpty) ...[
              SizedBox(height: w * 0.015),
              _InfoChip(text: fullName, icon: Icons.person_rounded, w: w),
            ],
            if (phone != null && phone.trim().isNotEmpty) ...[
              SizedBox(height: w * 0.015),
              _InfoChip(text: phone, icon: Icons.phone_rounded, w: w),
            ],
            if (notes != null && notes.trim().isNotEmpty) ...[
              SizedBox(height: w * 0.015),
              _InfoChip(text: notes, icon: Icons.notes_rounded, w: w),
            ],
          ],

          // ── Numéro de suivi ──────────────────────────────────────────
          if (trackingId != null && trackingId!.trim().isNotEmpty) ...[
            SizedBox(height: w * 0.035),
            _DetailLabel(
                label: 'Numéro de suivi',
                icon: Icons.qr_code_rounded,
                w: w),
            SizedBox(height: w * 0.015),
            _InfoChip(
              text: trackingId!,
              icon: Icons.local_shipping_rounded,
              w: w,
              copyable: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  final String label;
  final double value;
  final double w;
  const _PriceRow({required this.label, required this.value, required this.w});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(vertical: w * 0.008),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(fontSize: w * 0.03, color: Colors.grey.shade600)),
            Text('${value.toStringAsFixed(2)} DH',
                style: TextStyle(
                    fontSize: w * 0.03,
                    fontWeight: FontWeight.w600,
                    color: _Palette.inkSoft)),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  LIGNE ARTICLE
// ─────────────────────────────────────────────────────────────────────────────
class _ItemRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final double w;
  const _ItemRow({required this.item, required this.w});

  @override
  Widget build(BuildContext context) {
    final name = item['name'] as String? ?? 'Produit';
    final qty = (item['qty'] as num?)?.toInt() ?? 1;
    final subtotal = (item['subtotal'] as num?)?.toDouble() ??
        (((item['price'] as num?)?.toDouble() ?? 0.0) * qty);
    final imageUrl = item['imageUrl'] as String?;
    final hasImage = imageUrl != null && imageUrl.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: w * 0.025),
      child: Row(
        children: [
          // Image ou placeholder — errorBuilder évite tout crash de décodage
          Container(
            width: w * 0.12,
            height: w * 0.12,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: _Palette.accentSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: hasImage
                ? Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Icon(Icons.image_not_supported_outlined,
                          size: w * 0.05, color: Colors.grey.shade400),
                    ),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Center(
                        child: SizedBox(
                          width: w * 0.04,
                          height: w * 0.04,
                          child: const CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    },
                  )
                : Center(
                    child: Icon(Icons.shopping_bag_rounded,
                        size: w * 0.05, color: Colors.grey.shade400),
                  ),
          ),
          SizedBox(width: w * 0.03),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: w * 0.032,
                    fontWeight: FontWeight.w600,
                    color: _Palette.ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Qté : $qty',
                  style: TextStyle(fontSize: w * 0.027, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          Text(
            '${subtotal.toStringAsFixed(2)} DH',
            style: TextStyle(
              fontSize: w * 0.032,
              fontWeight: FontWeight.w700,
              color: _Palette.accent,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  COMPOSANTS UTILITAIRES
// ─────────────────────────────────────────────────────────────────────────────
class _DetailLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  final double w;
  const _DetailLabel({required this.label, required this.icon, required this.w});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: w * 0.04, color: _Palette.accent),
          SizedBox(width: w * 0.02),
          Text(
            label,
            style: TextStyle(
              fontSize: w * 0.03,
              fontWeight: FontWeight.w700,
              color: _Palette.ink,
            ),
          ),
        ],
      );
}

class _InfoChip extends StatelessWidget {
  final String text;
  final IconData icon;
  final double w;
  final bool copyable;
  final Color? iconColor;

  const _InfoChip({
    required this.text,
    required this.icon,
    required this.w,
    this.copyable = false,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: w * 0.035, vertical: w * 0.025),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(icon, size: w * 0.038, color: iconColor ?? Colors.grey.shade500),
            SizedBox(width: w * 0.025),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: w * 0.03, color: Colors.grey.shade700),
              ),
            ),
            if (copyable)
              GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Numéro copié : $text'),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: _Palette.accent,
                    ),
                  );
                },
                child: Icon(Icons.copy_rounded, size: w * 0.04, color: _Palette.accent),
              ),
          ],
        ),
      );
}

class _RoundBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _RoundBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.18)),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 17),
          ),
        ),
      );
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double w;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.w,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: w * 0.03, vertical: w * 0.015),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: w * 0.035, color: color),
              SizedBox(width: w * 0.015),
              Text(
                label,
                style: TextStyle(
                  fontSize: w * 0.028,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  BADGE "DÉJÀ ÉVALUÉ" — remplace le bouton "Laisser un avis" une fois noté
// ─────────────────────────────────────────────────────────────────────────────
class _ReviewedBadge extends StatelessWidget {
  final double w;
  const _ReviewedBadge({required this.w});

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: w * 0.03, vertical: w * 0.015),
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.success.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: w * 0.035, color: AppColors.success),
            SizedBox(width: w * 0.015),
            Text(
              'Évalué',
              style: TextStyle(
                fontSize: w * 0.028,
                fontWeight: FontWeight.w700,
                color: AppColors.success,
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  ÉTAT : NON CONNECTÉ
// ─────────────────────────────────────────────────────────────────────────────
class _NotSignedIn extends StatelessWidget {
  final double w;
  const _NotSignedIn({required this.w});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: w * 0.08),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline_rounded, size: w * 0.14, color: Colors.grey.shade400),
              SizedBox(height: w * 0.04),
              Text(
                'Connectez-vous pour voir vos commandes',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: w * 0.04,
                  fontWeight: FontWeight.w700,
                  color: _Palette.ink,
                ),
              ),
              SizedBox(height: w * 0.05),
              ElevatedButton(
                onPressed: () => context.go('/login'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _Palette.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: EdgeInsets.symmetric(horizontal: w * 0.08, vertical: w * 0.035),
                ),
                child: Text(
                  'Se connecter',
                  style: TextStyle(fontSize: w * 0.035, color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  ÉTAT VIDE
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyOrders extends StatelessWidget {
  final double w;
  final bool filtered;
  const _EmptyOrders({required this.w, required this.filtered});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: w * 0.08),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                filtered ? Icons.search_off_rounded : Icons.inventory_2_outlined,
                size: w * 0.16,
                color: Colors.grey.shade400,
              ),
              SizedBox(height: w * 0.04),
              Text(
                filtered
                    ? 'Aucune commande dans cette catégorie'
                    : 'Aucune commande pour l\'instant',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: w * 0.042,
                  fontWeight: FontWeight.w700,
                  color: _Palette.ink,
                ),
              ),
              SizedBox(height: w * 0.02),
              Text(
                filtered
                    ? 'Vos commandes dans cette catégorie s\'afficheront ici.'
                    : 'Commencez à explorer nos produits frais !',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: w * 0.032,
                  color: Colors.grey.shade500,
                  height: 1.5,
                ),
              ),
              if (!filtered) ...[
                SizedBox(height: w * 0.06),
                ElevatedButton(
                  onPressed: () => context.go('/home'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _Palette.accent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: EdgeInsets.symmetric(horizontal: w * 0.08, vertical: w * 0.035),
                  ),
                  child: Text(
                    'Explorer les produits',
                    style: TextStyle(fontSize: w * 0.035, color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  ÉTAT ERREUR
// ─────────────────────────────────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  final double w;
  final Object? error;
  const _ErrorView({required this.w, this.error});

  @override
  Widget build(BuildContext context) {
    // En dev, ce message aide à repérer un index Firestore manquant
    // (FAILED_PRECONDITION contient un lien direct de création d'index).
    assert(() {
      if (error != null) debugPrint('OrdersScreen stream error: $error');
      return true;
    }());

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: w * 0.08),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: w * 0.14, color: Colors.grey.shade400),
            SizedBox(height: w * 0.04),
            Text(
              'Impossible de charger vos commandes',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: w * 0.038,
                fontWeight: FontWeight.w700,
                color: _Palette.ink,
              ),
            ),
            SizedBox(height: w * 0.02),
            Text(
              'Vérifiez votre connexion et réessayez.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: w * 0.03, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}