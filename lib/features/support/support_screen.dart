import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:mrbeldi/core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  DATA MODEL
// ─────────────────────────────────────────────────────────────────────────────
class _FaqItem {
  final String question;
  final String answer;
  final IconData icon;
  final Color iconColor;

  const _FaqItem({
    required this.question,
    required this.answer,
    required this.icon,
    required this.iconColor,
  });
}

const _kFaqs = <_FaqItem>[
  _FaqItem(
    question: 'Que faire si le produit est abîmé ou différent de la commande ?',
    icon: Icons.broken_image_rounded,
    iconColor: AppColors.error,
    answer:
        'Votre satisfaction est notre priorité absolue.\n\n'
        'Si vous recevez un produit endommagé, de qualité insuffisante '
        'ou différent de celui commandé, voici la marche à suivre :\n\n'
        '① Prenez une photo du produit dans les 24h suivant la livraison.\n'
        '② Signalez le problème via le bouton « Contacter le support » ci-dessous '
        'en joignant la photo.\n'
        '③ Notre équipe traite votre demande sous 24h ouvrées et vous propose '
        'un remboursement intégral ou un renvoi immédiat du produit.\n\n'
        'Aucun retour physique n\'est nécessaire pour les produits frais.',
  ),
  _FaqItem(
    question: 'D\'où proviennent les produits MrBeldi ?',
    icon: Icons.location_on_rounded,
    iconColor: AppColors.primary,
    answer:
        'Tous nos produits sont issus exclusivement de fermes marocaines '
        'soigneusement sélectionnées à travers le Royaume.\n\n'
        'Nous travaillons en partenariat direct avec des agriculteurs locaux '
        'des régions de Souss-Massa, Doukkala, Haouz, Meknès et bien d\'autres, '
        'afin de vous garantir :\n\n'
        '✓ Une fraîcheur maximale (récolte → livraison en moins de 48h)\n'
        '✓ Un soutien direct à l\'agriculture marocaine\n'
        '✓ Des prix justes pour le producteur et pour vous\n\n'
        'Chaque fiche produit indique la région d\'origine exacte.',
  ),
  _FaqItem(
    question: 'Comment savoir si un produit est 100 % biologique ?',
    icon: Icons.eco_rounded,
    iconColor: Color(0xFF33691E),
    answer:
        'Tous les produits labellisés « 🌿 Bio » sur MrBeldi répondent aux normes '
        'strictes établies par l\'ONSSA (Office National de Sécurité Sanitaire '
        'des produits Alimentaires).\n\n'
        'Pour identifier un produit biologique :\n\n'
        '① Repérez le badge vert « 🌿 Bio » sur la fiche produit.\n'
        '② Consultez la section « Certification » sur la page du produit pour '
        'voir le numéro de certificat ONSSA.\n'
        '③ Les produits bio sont cultivés sans pesticides chimiques, '
        'sans OGM et avec des engrais naturels uniquement.\n\n'
        'En cas de doute, notre équipe peut vous fournir les documents '
        'de certification sur simple demande.',
  ),
  _FaqItem(
    question: 'Comment utiliser mes points bonus ?',
    icon: Icons.card_giftcard_rounded,
    iconColor: AppColors.accent,
    answer:
        'Vos points bonus MrBeldi sont une récompense pour votre fidélité !\n\n'
        'Comment les accumuler :\n'
        '✓ Chaque achat vous rapporte 1 point par 10 MAD dépensés.\n'
        '✓ Parrainez un ami : +50 points offerts dès sa première commande.\n'
        '✓ Laissez un avis produit : +3 à +10 graines par évaluation.\n\n'
        'Comment les utiliser :\n'
        '① Ajoutez vos articles au panier normalement.\n'
        '② À l\'étape de paiement, activez « Utiliser mes points ».\n'
        '③ 100 points = 10 MAD de réduction, applicable sans minimum d\'achat.\n\n'
        'Vos points sont valables 12 mois et consultables dans votre profil.',
  ),
  _FaqItem(
    question: 'Quels sont les délais et modalités de livraison ?',
    icon: Icons.local_shipping_rounded,
    iconColor: Color(0xFF1565C0),
    answer:
        'MrBeldi s\'engage à livrer vos produits frais dans les meilleures '
        'conditions et les meilleurs délais.\n\n'
        'Délais de livraison :\n'
        '✓ Casablanca, Rabat, Marrakech : livraison en 24h\n'
        '✓ Autres villes principales : 24 à 48h\n'
        '✓ Zones éloignées : 48 à 72h\n\n'
        'Nos livraisons sont effectuées en véhicules réfrigérés pour '
        'préserver la fraîcheur optimale de vos produits.\n\n'
        'La livraison est gratuite à partir de 150 MAD d\'achat. '
        'En dessous, un forfait de 20 MAD est appliqué.\n\n'
        'Vous recevrez un SMS de confirmation avec le suivi en temps réel '
        'dès l\'expédition de votre commande.',
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
//  SUPPORT SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen>
    with TickerProviderStateMixin {
  // ── expanded FAQ index ────────────────────────────────────────────────────
  int? _expandedIndex;

  // ── stagger animation ─────────────────────────────────────────────────────
  late final AnimationController _staggerCtrl;
  final List<Animation<double>> _itemAnims = [];

  // ── answer expand controllers ─────────────────────────────────────────────
  late final List<AnimationController> _expandCtrl;
  late final List<Animation<double>> _expandAnim;

  @override
  void initState() {
    super.initState();

    // stagger entrance
    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    for (int i = 0; i < _kFaqs.length + 3; i++) {
      final start = (i * 0.08).clamp(0.0, 0.75);
      final end = (start + 0.35).clamp(0.0, 1.0);
      _itemAnims.add(CurvedAnimation(
        parent: _staggerCtrl,
        curve: Interval(start, end, curve: Curves.easeOutCubic),
      ));
    }
    Future.delayed(
      const Duration(milliseconds: 100),
      () {
        if (mounted) _staggerCtrl.forward();
      },
    );

    // per-FAQ expand animations
    _expandCtrl = List.generate(
      _kFaqs.length,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 320),
      ),
    );
    _expandAnim = _expandCtrl
        .map((c) => CurvedAnimation(parent: c, curve: Curves.easeInOutCubic))
        .toList();
  }

  @override
  void dispose() {
    _staggerCtrl.dispose();
    for (final c in _expandCtrl) {
      c.dispose();
    }
    super.dispose();
  }

  // ── toggle FAQ ────────────────────────────────────────────────────────────
  void _toggle(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_expandedIndex == index) {
        _expandedIndex = null;
        _expandCtrl[index].reverse();
      } else {
        if (_expandedIndex != null) {
          _expandCtrl[_expandedIndex!].reverse();
        }
        _expandedIndex = index;
        _expandCtrl[index].forward();
      }
    });
  }

  // ── contact support via WhatsApp ───────────────────────────────────────────
  static const String _whatsappNumber = '212782293139'; // 0782293139 → format international (sans le 0)
  static const String _defaultMessage =
      'Bonjour 👋, j\'ai une question concernant MrBeldi.';

  Future<void> _openWhatsApp() async {
    HapticFeedback.mediumImpact();
    final uri = Uri.parse(
      'https://wa.me/$_whatsappNumber?text=${Uri.encodeComponent(_defaultMessage)}',
    );
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WhatsApp n\'est pas installé sur cet appareil')),
      );
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── AppBar ───────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            expandedHeight: 160,
            backgroundColor: AppColors.primaryDark,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: _SupportHeader(itemAnim: _itemAnims[0]),
            ),
          ),

          // ── ONSSA Quality Banner ─────────────────────────────────────────
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _itemAnims[1],
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.3),
                  end: Offset.zero,
                ).animate(_itemAnims[1]),
                child: const _OnsaBanner(),
              ),
            ),
          ),

          // ── Welcome text ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _itemAnims[2],
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.2),
                  end: Offset.zero,
                ).animate(_itemAnims[2]),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('👋', style: TextStyle(fontSize: 26)),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Bonjour, comment pouvons-nous vous aider ?',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Trouvez rapidement une réponse à vos questions ci-dessous.',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── FAQ section label ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 20,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Questions fréquentes',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_kFaqs.length} questions',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── FAQ List ─────────────────────────────────────────────────────
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final anim = _itemAnims[i + 3];
                return FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.05, 0),
                      end: Offset.zero,
                    ).animate(anim),
                    child: _FaqCard(
                      faq: _kFaqs[i],
                      index: i,
                      isExpanded: _expandedIndex == i,
                      expandAnim: _expandAnim[i],
                      onTap: () => _toggle(i),
                      onContactTap: _openWhatsApp,
                    ),
                  ),
                );
              },
              childCount: _kFaqs.length,
            ),
          ),

          // ── "Pas trouvé de solution ?" ───────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 120),
              child: _NotFoundCard(onTap: _openWhatsApp),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SUPPORT HEADER
// ─────────────────────────────────────────────────────────────────────────────
class _SupportHeader extends StatelessWidget {
  final Animation<double> itemAnim;
  const _SupportHeader({required this.itemAnim});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primaryDark, AppColors.primary],
            ),
          ),
        ),
        // decorative circles
        Positioned(
          top: -40,
          right: -40,
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
        ),
        Positioned(
          bottom: 10,
          left: -20,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent.withValues(alpha: 0.10),
            ),
          ),
        ),
        // headset icon background
        Positioned(
          right: 24,
          bottom: 16,
          child: Icon(Icons.support_agent_rounded,
              size: 90, color: Colors.white.withValues(alpha: 0.07)),
        ),
        // content
        FadeTransition(
          opacity: itemAnim,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.headset_mic_rounded,
                            color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Centre d\'aide MrBeldi',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              )),
                          Text('Disponible 7j/7 · 08h–22h',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                color: Color(0xFFB9F6CA),
                              )),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ONSSA QUALITY BANNER
// ─────────────────────────────────────────────────────────────────────────────
class _OnsaBanner extends StatelessWidget {
  const _OnsaBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Row(
          children: [
            // ── Left fixed part – shield + "Qualité garantie" ──────────────
            Container(
              width: 155,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primaryDark, AppColors.primary],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.verified_user_rounded,
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 7),
                  const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Qualité garantie',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          )),
                      Text('✓  Certifié',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 9,
                            color: Color(0xFFB9F6CA),
                          )),
                    ],
                  ),
                ],
              ),
            ),

            // ── Divider ────────────────────────────────────────────────────
            Container(width: 1.5, color: Colors.white.withValues(alpha: 0.3)),

            // ── Right scrolling part – ONSSA message ───────────────────────
            Expanded(
              child: Container(
                color: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: const Text(
                  'Tous les produits sont vérifiés par l\'Office National de Sécurité Sanitaire des produits Alimentaires (ONSSA) du Maroc 🇲🇦',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  FAQ CARD
// ─────────────────────────────────────────────────────────────────────────────
class _FaqCard extends StatelessWidget {
  final _FaqItem faq;
  final int index;
  final bool isExpanded;
  final Animation<double> expandAnim;
  final VoidCallback onTap;
  final VoidCallback onContactTap;

  const _FaqCard({
    required this.faq,
    required this.index,
    required this.isExpanded,
    required this.expandAnim,
    required this.onTap,
    required this.onContactTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isExpanded
                ? AppColors.primary.withValues(alpha: 0.5)
                : AppColors.border,
            width: isExpanded ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isExpanded
                  ? AppColors.primary.withValues(alpha: 0.10)
                  : AppColors.shadow,
              blurRadius: isExpanded ? 16 : 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            // ── Question row ──────────────────────────────────────────────
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(18),
              splashColor: AppColors.primary.withValues(alpha: 0.06),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(
                  children: [
                    // icon bubble
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: isExpanded
                            ? faq.iconColor.withValues(alpha: 0.15)
                            : AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(faq.icon, color: faq.iconColor, size: 22),
                    ),
                    const SizedBox(width: 12),

                    // question text
                    Expanded(
                      child: Text(
                        faq.question,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13.5,
                          fontWeight:
                              isExpanded ? FontWeight.w700 : FontWeight.w600,
                          color: isExpanded
                              ? AppColors.primaryDark
                              : AppColors.textPrimary,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // chevron
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeInOutCubic,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: isExpanded
                              ? AppColors.primary.withValues(alpha: 0.12)
                              : AppColors.border.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: isExpanded ? AppColors.primary : AppColors.textLight,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Animated answer ───────────────────────────────────────────
            SizeTransition(
              sizeFactor: expandAnim,
              child: FadeTransition(
                opacity: expandAnim,
                child: Column(
                  children: [
                    Container(
                      height: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      color: AppColors.border,
                    ),
                    // answer text
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          faq.answer,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            height: 1.65,
                          ),
                        ),
                      ),
                    ),
                    // contact support button
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                      child: GestureDetector(
                        onTap: onContactTap,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.primaryDark, AppColors.primary],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.phone_android_rounded, color: Colors.white, size: 16),
                              SizedBox(width: 8),
                              Text(
                                'Contacter le support sur WhatsApp',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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

// ─────────────────────────────────────────────────────────────────────────────
//  "PAS TROUVÉ DE SOLUTION ?" CARD
// ─────────────────────────────────────────────────────────────────────────────
class _NotFoundCard extends StatelessWidget {
  final VoidCallback onTap;
  const _NotFoundCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // icon
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
              ),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text('🤔', style: TextStyle(fontSize: 32)),
            ),
          ),
          const SizedBox(height: 16),

          // title
          const Text(
            'Vous n\'avez pas trouvé la solution ?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),

          // subtitle
          const Text(
            'Notre équipe de support est disponible 7j/7 pour répondre à toutes vos questions en quelques minutes.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),

          // response time badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                const Text(
                  'Temps de réponse moyen : moins de 10 min',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // contact button
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primaryDark, AppColors.primary],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.phone_android_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 10),
                  Text(
                    'Discuter sur WhatsApp',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}