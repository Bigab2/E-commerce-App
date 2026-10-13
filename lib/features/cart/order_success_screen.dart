import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mrbeldi/core/theme/app_colors.dart';

class OrderSuccessScreen extends StatelessWidget {
  final String orderId;
  const OrderSuccessScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96, height: 96,
                decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1), shape: BoxShape.circle),
                child: Center(
                  child: Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                        color: AppColors.primary, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded,
                        color: Colors.white, size: 36),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text('Commande confirmée !',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 20,
                      fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
              const SizedBox(height: 8),
              Text('Vous payerez à la livraison',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 13,
                      color: Colors.grey[600])),
              const SizedBox(height: 24),

              // ── Numéro de commande ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: const Color(0xFFF7F8F7),
                    borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.receipt_long_outlined, color: Color(0xFF757575)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Numéro de commande',
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 11,
                              color: Colors.grey[600])),
                      Text('#${orderId.substring(0, 8).toUpperCase()}',
                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 14,
                              fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 8),

              // ── Total (lu en direct depuis Firestore) ──
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('orders').doc(orderId).snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData || !snap.data!.exists) {
                    return const SizedBox();
                  }
                  final data = snap.data!.data() as Map<String, dynamic>;
                  final total = (data['total'] as num?)?.toDouble() ?? 0;
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF7F8F7),
                        borderRadius: BorderRadius.circular(12)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total à payer',
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 13,
                                color: Colors.grey[600])),
                        Text('${total.toStringAsFixed(total % 1 == 0 ? 0 : 2)} DH',
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 16,
                                fontWeight: FontWeight.w800, color: AppColors.primary)),
                      ]),
                  );
                },
              ),

              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => context.go('/order-tracking/$orderId'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('Suivre ma commande',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 14,
                          fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => context.go('/home'),
                child: Text('Retour à l\'accueil',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 13,
                        fontWeight: FontWeight.w600, color: Colors.grey[600])),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}
