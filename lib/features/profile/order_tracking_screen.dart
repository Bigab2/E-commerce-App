// lib/features/profile/order_tracking_screen.dart
//
// ─────────────────────────────────────────────────────────────────────────────
//  RÈGLE D'OR : cet écran ÉCOUTE seulement (snapshots) le champ `status`.
//  Il ne l'écrit JAMAIS. Le `status` est modifié exclusivement par le
//  dashboard admin (autre application Flutter connectée au même Firestore).
//  Dès que l'admin change orders/{id}.status, ce StreamBuilder reçoit le
//  nouveau document EN DIRECT et reconstruit le badge + la timeline en
//  conséquence — aucune action manuelle, aucun cache, aucun état local.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mrbeldi/core/theme/app_colors.dart';

class OrderTrackingScreen extends StatelessWidget {
  final String orderId;
  const OrderTrackingScreen({super.key, required this.orderId});

  // ── Les statuts standards partagés avec le dashboard admin ──
  static const _statusSteps = [
    ('pending', 'Commande reçue', Icons.receipt_long_rounded),
    ('confirmed', 'Confirmée', Icons.check_circle_outline_rounded),
    ('preparing', 'En préparation', Icons.inventory_2_outlined),
    ('shipped', 'En livraison', Icons.local_shipping_outlined),
    ('delivered', 'Livrée', Icons.home_rounded),
  ];

  int _stepIndex(String status) {
    final idx = _statusSteps.indexWhere((s) => s.$1 == status);
    return idx == -1 ? 0 : idx;
  }

  // ── retour vers le panier ──
  void _backToCart(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/cart');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Estimation de livraison : moins de 24h après la commande, mais toujours
  //  ramenée à l'intérieur des heures ouvrées 08:00 – 18:00.
  // ─────────────────────────────────────────────────────────────────────────
  DateTime _estimatedDelivery(DateTime createdAt) {
    final hardLimit = createdAt.add(const Duration(hours: 24));
    DateTime candidate;

    if (createdAt.hour < 14) {
      // commande passée le matin/début d'après-midi → livrée le jour même
      candidate = DateTime(
          createdAt.year, createdAt.month, createdAt.day, 18, 0);
    } else {
      // commande passée tard → livrée le lendemain matin
      final next = createdAt.add(const Duration(days: 1));
      candidate = DateTime(next.year, next.month, next.day, 12, 0);
    }

    // ne jamais dépasser la limite stricte des 24h
    if (candidate.isAfter(hardLimit)) candidate = hardLimit;

    // toujours rester dans la plage horaire ouvrée 8h–18h
    if (candidate.hour < 8) {
      candidate =
          DateTime(candidate.year, candidate.month, candidate.day, 8, 0);
    } else if (candidate.hour > 18) {
      candidate =
          DateTime(candidate.year, candidate.month, candidate.day, 18, 0);
    }

    return candidate;
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        leadingWidth: 56,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: GestureDetector(
            onTap: () => _backToCart(context),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.1),
              ),
              child: const Icon(Icons.arrow_back_rounded,
                  color: AppColors.primary, size: 20),
            ),
          ),
        ),
        title: const Text('Suivi de commande',
            style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A1A),
                fontSize: 16)),
      ),
      // ── écoute en direct — se met à jour dès que le dashboard change `status` ──
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders').doc(orderId).snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          if (!snap.hasData || !snap.data!.exists) {
            return Center(
              child: Text('Commande introuvable',
                  style: TextStyle(
                      fontFamily: 'Cairo', color: AppColors.textSecondary)),
            );
          }

          // ── données lues directement depuis le document Firestore ──
          final data = snap.data!.data() as Map<String, dynamic>;
          final status = data['status']?.toString() ?? 'pending';
          final isCancelled = status == 'cancelled';
          final isDelivered = status == 'delivered';
          final items = (data['items'] as List?) ?? [];
          final total = (data['total'] as num?)?.toDouble() ?? 0;
          final subtotal = (data['subtotal'] as num?)?.toDouble() ?? 0;
          final deliveryFee = (data['deliveryFee'] as num?)?.toDouble() ?? 0;
          final address = data['deliveryAddress'] as Map<String, dynamic>?;
          final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
          final eta = (createdAt != null && !isCancelled && !isDelivered)
              ? _estimatedDelivery(createdAt)
              : null;

          return ListView(
            padding: EdgeInsets.fromLTRB(w * 0.04, 14, w * 0.04, 32),
            children: [

              // ── carte de statut compacte (dégradé léger, style "Seeds") ──
              _StatusCard(
                orderId: orderId,
                createdAt: createdAt,
                status: status,
                eta: eta,
                screenW: w,
              ),
              const SizedBox(height: 22),

              if (isCancelled)
                _CancelledBanner()
              else ...[
                _SectionLabel('Statut de la commande'),
                const SizedBox(height: 10),
                _StatusTimeline(
                  currentIndex: _stepIndex(status),
                  steps: _statusSteps,
                ),
              ],
              const SizedBox(height: 22),

              // ── Adresse ──
              if (address != null) ...[
                _SectionLabel('Adresse de livraison'),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.shadow,
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: w * 0.1,
                          height: w * 0.1,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.location_on_rounded,
                              color: AppColors.primary, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(address['fullName']?.toString() ?? '',
                                    style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary)),
                                Text(address['phone']?.toString() ?? '',
                                    style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 12,
                                        color: AppColors.textSecondary)),
                                Text(
                                    '${address['address'] ?? ''}, ${address['city'] ?? ''}',
                                    style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 12,
                                        color: AppColors.textSecondary)),
                              ]),
                        ),
                      ]),
                ),
                const SizedBox(height: 22),
              ],

              // ── Articles ──
              _SectionLabel('Articles commandés'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.shadow,
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...items.map((raw) {
                        final item = raw as Map<String, dynamic>;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: CachedNetworkImage(
                                imageUrl: item['imageUrl']?.toString() ?? '',
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                    width: 48,
                                    height: 48,
                                    color: AppColors.primary
                                        .withValues(alpha: 0.08)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(item['name']?.toString() ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textPrimary)),
                                    Text(
                                        'x${item['qty']} • ${item['price']} DH',
                                        style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 11,
                                            color: AppColors.textSecondary)),
                                  ]),
                            ),
                            Text('${item['subtotal']} DH',
                                style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary)),
                          ]),
                        );
                      }),
                      Container(height: 1, color: AppColors.border),
                      const SizedBox(height: 8),
                      _PriceRow('Sous-total', subtotal),
                      _PriceRow('Livraison', deliveryFee),
                      const SizedBox(height: 4),
                      _PriceRow('Total (paiement à la livraison)', total,
                          isBold: true),
                    ]),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  CARTE DE STATUT — version compacte du dégradé "Seeds" de la page profil
// ─────────────────────────────────────────────────────────────────────────────
class _StatusCard extends StatelessWidget {
  final String orderId;
  final DateTime? createdAt;
  final String status;
  final DateTime? eta;
  final double screenW;

  const _StatusCard({
    required this.orderId,
    required this.createdAt,
    required this.status,
    required this.eta,
    required this.screenW,
  });

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} à ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  // ── on n'affiche que le jour, jamais une heure précise ──
  String _formatEta(DateTime eta) {
    final now = DateTime.now();
    final isSameDay =
        eta.year == now.year && eta.month == now.month && eta.day == now.day;
    final tomorrow = now.add(const Duration(days: 1));
    final isTomorrow = eta.year == tomorrow.year &&
        eta.month == tomorrow.month &&
        eta.day == tomorrow.day;
    if (isSameDay) return "Aujourd'hui";
    if (isTomorrow) return 'Demain';
    return '${eta.day.toString().padLeft(2, '0')}/${eta.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final w = screenW;
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2E8B57), Color(0xFF3DAA6E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Commande #${orderId.substring(0, 8).toUpperCase()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: (w * 0.042).clamp(14.0, 17.0),
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    if (createdAt != null) ...[
                      const SizedBox(height: 3),
                      Text(_formatDate(createdAt!),
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: (w * 0.028).clamp(10.0, 12.0),
                              color: Colors.white.withValues(alpha: 0.8))),
                    ],
                  ],
                ),
              ),
              _StatusBadge(status: status),
            ],
          ),
          if (eta != null) ...[
            const SizedBox(height: 14),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.18)),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: w * 0.08,
                  height: w * 0.08,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.local_shipping_outlined,
                      color: Colors.white, size: 17),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Livraison estimée',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: (w * 0.027).clamp(10.0, 12.0),
                              color: Colors.white.withValues(alpha: 0.75))),
                      Text(_formatEta(eta!),
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: (w * 0.034).clamp(12.0, 14.0),
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                      Text('Pendant les heures ouvrées (8h – 18h)',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: (w * 0.025).clamp(9.0, 11.0),
                              color: Colors.white.withValues(alpha: 0.65))),
                    ],
                  ),
                ),
              ],
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
  final bool isBold;
  const _PriceRow(this.label, this.value, {this.isBold = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style: TextStyle(fontFamily: 'Cairo',
                  fontSize: isBold ? 13 : 12,
                  fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
                  color: isBold ? AppColors.textPrimary : AppColors.textSecondary)),
          Text('${value.toStringAsFixed(value % 1 == 0 ? 0 : 2)} DH',
              style: TextStyle(fontFamily: 'Cairo',
                  fontSize: isBold ? 14 : 12,
                  fontWeight: isBold ? FontWeight.w900 : FontWeight.w600,
                  color: isBold ? AppColors.primary : AppColors.textPrimary)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  STATUS TIMELINE — réagit en direct au changement venant du dashboard admin
// ─────────────────────────────────────────────────────────────────────────────
class _StatusTimeline extends StatelessWidget {
  final int currentIndex;
  final List<(String, String, IconData)> steps;
  const _StatusTimeline({required this.currentIndex, required this.steps});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: List.generate(steps.length, (i) {
          final (_, label, icon) = steps[i];
          final isDone = i <= currentIndex;
          final isCurrent = i == currentIndex;
          final isLast = i == steps.length - 1;

          return IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Column(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDone ? AppColors.primary : const Color(0xFFEEEEEE),
                  ),
                  child: Icon(icon, size: 16,
                      color: isDone ? Colors.white : Colors.grey[500]),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: i < currentIndex
                          ? AppColors.primary
                          : const Color(0xFFEEEEEE),
                    ),
                  ),
              ]),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 22, top: 5),
                  child: Text(label,
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 13.5,
                          fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w500,
                          color: isDone
                              ? AppColors.textPrimary
                              : Colors.grey[500])),
                ),
              ),
            ]),
          );
        }),
      ),
    );
  }
}

class _CancelledBanner extends StatelessWidget {
  const _CancelledBanner();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: const Color(0xFFE53935).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: const Color(0xFFE53935).withValues(alpha: 0.3))),
        child: Row(children: [
          const Icon(Icons.cancel_outlined, color: Color(0xFFE53935), size: 28),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Cette commande a été annulée',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 14,
                    fontWeight: FontWeight.w800, color: Color(0xFFE53935))),
          ),
        ]),
      );
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  (Color, String) _config() {
    switch (status) {
      case 'confirmed': return (const Color(0xFF64B5F6), 'Confirmée');
      case 'preparing': return (const Color(0xFFFFB74D), 'Préparation');
      case 'shipped': return (const Color(0xFFBA68C8), 'En livraison');
      case 'delivered': return (const Color(0xFF81E2A4), 'Livrée');
      case 'cancelled': return (const Color(0xFFEF5350), 'Annulée');
      default: return (Colors.white70, 'En attente');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (color, label) = _config();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7, height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(fontFamily: 'Cairo', fontSize: 11,
                  fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SECTION LABEL — identique au style de la page profil
// ─────────────────────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4, height: 18,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(label,
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          )),
      ],
    );
  }
}