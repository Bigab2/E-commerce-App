// lib/features/home/home_screen.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mrbeldi/core/services/local_cart_service.dart';
import 'package:mrbeldi/core/theme/app_colors.dart';
import 'package:mrbeldi/routes/app_routes.dart';
// ─────────────────────────────────────────────────────────────────────────────
//  HOME SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) => const _HomeContent();
}

// ─────────────────────────────────────────────────────────────────────────────
//  HOME CONTENT
// ─────────────────────────────────────────────────────────────────────────────
class _HomeContent extends StatefulWidget {
  const _HomeContent();
  @override
  State<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<_HomeContent> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  // الفئة المختارة: null = tout
  String? _selectedCategory;
  // الفلتر المختار: null = tout
  String? _selectedFilter; // 'offers' | '5stars' | 'bestseller'

  // ── حالة السلة المركزية ──────────────────────────────────────────────────
  // نداء Firestore واحد فقط لكل وثائق السلة (وليس نداء منفصل لكل بطاقة منتج).
  // كل الـ _ProductCard تستهلك نفس الـ Stream عبر هذا الـ StreamBuilder.
  Stream<Set<String>>? _cartIdsStream;

  @override
  void initState() {
    super.initState();
     LocalCartService.warmUp();
    _cartIdsStream = _buildCartIdsStream();
  }

 Stream<Set<String>> _buildCartIdsStream() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) {
    // زائر غير مسجل: "في السلة" كيتحدد من التخزين المحلي بدل ما يبقى فارغ.
    return LocalCartService.watch()
        .map((items) => items.map((e) => e.productId).toSet());
  }
  return FirebaseFirestore.instance
      .collection('carts')
      .doc(uid)
      .collection('items')
      .snapshots()
      .map((snap) => snap.docs.map((d) => d.id).toSet())
      .handleError((_) {});
}

  void _showTrustSheet(BuildContext ctx) => showModalBottomSheet(
        context: ctx,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _TrustBottomSheet(),
      );

  Query _buildQuery() {
    // لا نضيف where('category') على Firestore لتجنّب الحاجة لفهرس مركّب
    // الفلترة/الترتيب حسب الفئة تتم في الذاكرة داخل _ProductsGrid
    return FirebaseFirestore.instance
        .collection('products')
        .where('isAvailable', isEqualTo: true);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

 @override
Widget build(BuildContext context) {
  final sw = MediaQuery.of(context).size.width;
  final bool isSearching = _searchQuery.isNotEmpty;

  return StreamBuilder<Set<String>>(
    stream: _cartIdsStream,
    builder: (context, cartSnap) {
      final cartIds = cartSnap.data ?? const <String>{};

      return SafeArea(
        top: true,
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [ 
            // ── AppBar ──────────────────────────────────────────────────────
            SliverAppBar(
              floating: true,
              snap: true,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              elevation: 0,
              titleSpacing: 0,
              toolbarHeight: 60,
              title: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.black, width: 1.5),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        style: const TextStyle(
                            fontFamily: 'Cairo', fontSize: 14, color: Colors.black87),
                        decoration: const InputDecoration(
                          hintText: 'Rechercher sur MrBeldi...',
                          hintStyle: TextStyle(
                              fontFamily: 'Cairo', color: Color(0xFF9E9E9E), fontSize: 14),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: true,
                          fillColor: Colors.white,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (v) =>
                            setState(() => _searchQuery = v.trim().toLowerCase()),
                      ),
                    ),
                    Container(width: 1, height: 20, color: const Color(0xFFE0E0E0)),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {},
                      child: Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                            color: Colors.black, borderRadius: BorderRadius.circular(16)),
                        child: const Icon(Icons.document_scanner_outlined,
                            color: Colors.white, size: 17),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () {},
                      child: Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                            color: Colors.black, borderRadius: BorderRadius.circular(16)),
                        child: const Icon(Icons.search_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                  ]),
                ),
              ),
            ),

            // ── Sticky Categories ────────────────────────────────────────────────
            SliverPersistentHeader(
              pinned: true,
              delegate: _CategoriesHeader(
                selectedCategory: _selectedCategory,
                onCategorySelected: (cat) =>
                    setState(() => _selectedCategory = cat),
              ),
            ),

            if (isSearching) ...[
              _SectionTitle(title: 'Résultats pour "$_searchQuery"'),
              _ProductsGrid(query: _buildQuery(), searchQuery: _searchQuery,
                  filterType: _selectedFilter, category: _selectedCategory,
                  cartIds: cartIds),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ] else ...[
              const SliverToBoxAdapter(child: _HeroSlider()),
              SliverToBoxAdapter(
                  child: _TrustBadge(sw: sw,
                      onTap: () => _showTrustSheet(context))),
              SliverToBoxAdapter(child:  _FormulesPromoBanner(sw: sw)),
              const SliverToBoxAdapter(child: SizedBox(height: 10)),
              // ── Filter tabs ──
              SliverToBoxAdapter(
                child: _FilterTabs(
                  selected: _selectedFilter,
                  onSelected: (f) => setState(() => _selectedFilter = f),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 4)),
              _SectionTitle(
                title: _selectedCategory != null
                    ? _selectedCategory!
                    : _selectedFilter != null
                        ? 'Filtrés'
                        : '🛒 Tous les produits',
              ),
              _ProductsGrid(query: _buildQuery(), filterType: _selectedFilter,
                  category: _selectedCategory, cartIds: cartIds),
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ],
        ));
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  TRUST BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────
class _TrustBottomSheet extends StatelessWidget {
  const _TrustBottomSheet();
  @override
  Widget build(BuildContext context) {
    final sh = MediaQuery.of(context).size.height;
    return Container(
      height: sh * 0.80,
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            const Expanded(
              child: Text('Pourquoi choisir MrBeldi ?',
                  style: TextStyle(
                      fontFamily: 'Cairo', fontSize: 16,
                      fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                    color: const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(15)),
                child: const Icon(Icons.close_rounded,
                    size: 18, color: Color(0xFF424242)),
              ),
            ),
          ]),
        ),
        Container(height: 1, color: const Color(0xFFEEEEEE)),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _trustCard(AppColors.primary.withOpacity(0.07),
                    AppColors.primary.withOpacity(0.25), AppColors.primary,
                    Icons.verified_rounded, 'Certificat ONSSA',
                    'Office National de Sécurité Sanitaire\ndes Produits Alimentaires'),
                const SizedBox(height: 16),
                _trustCard(const Color(0xFFFFF8E1), const Color(0xFFFFD54F),
                    const Color(0xFFFFB300), null, 'Certification BIO',
                    'Produits 100% biologiques,\nsans pesticides ni additifs chimiques',
                    emoji: '🌿'),
                const SizedBox(height: 20),
                ...[
                  ('🚜','Directement de la ferme','Produits frais livrés du producteur à votre porte'),
                  ('🌱','Agriculture durable','Pratiques agricoles respectueuses de l\'environnement'),
                  ('❄️','Chaîne du froid garantie','Conservation optimale de nos produits frais'),
                  ('⚡','Livraison rapide','Commandez aujourd\'hui, livré demain chez vous'),
                ].map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.$1, style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.$2, style: const TextStyle(
                            fontFamily: 'Cairo', fontSize: 14,
                            fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                        Text(item.$3, style: TextStyle(
                            fontFamily: 'Cairo', fontSize: 12,
                            color: Colors.grey[600], height: 1.4)),
                      ],
                    )),
                  ]),
                )),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _trustCard(Color bg, Color border, Color iconColor,
      IconData? icon, String title, String sub, {String? emoji}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border)),
      child: Column(children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(color: iconColor, shape: BoxShape.circle),
          child: emoji != null
              ? Center(child: Text(emoji, style: const TextStyle(fontSize: 30)))
              : Icon(icon, color: Colors.white, size: 34),
        ),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(
            fontFamily: 'Cairo', fontSize: 18, fontWeight: FontWeight.w900,
            color: Color(0xFF1A1A1A))),
        const SizedBox(height: 6),
        Text(sub, textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 13,
                color: Colors.grey[600], height: 1.5)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  TRUST BADGE
// ─────────────────────────────────────────────────────────────────────────────
class _TrustBadge extends StatelessWidget {
  final double sw;
  final VoidCallback onTap;
  const _TrustBadge({required this.sw, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            const Icon(Icons.verified_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Pourquoi choisir MrBeldi ? ONSSA et BIO Certificate',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: sw * 0.033,
                      fontWeight: FontWeight.w700, color: Colors.white)),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 20),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  FILTER TABS  ← يفلتر بالبيانات الحقيقية من product_placement
// ─────────────────────────────────────────────────────────────────────────────
class _FilterTabs extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onSelected;
  const _FilterTabs({required this.selected, required this.onSelected});

  static const _tabs = [
    (null, '', 'Tout'),
    ('offers', '⚡', 'Offres'),
    ('5stars', '⭐', 'Notés 5 étoiles'),
    ('bestseller', '👍', 'Meilleures ventes'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (_, i) {
          final (key, emoji, label) = _tabs[i];
          final isSel = selected == key;
          return GestureDetector(
            onTap: () => onSelected(key),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (emoji.isNotEmpty) ...[
                      ColorFiltered(
                        colorFilter: const ColorFilter.mode(
                            Colors.black, BlendMode.srcIn),
                        child: Text(emoji, style: const TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 3),
                    ],
                    Text(label,
                        style: TextStyle(
                            fontFamily: 'Cairo', fontSize: 13,
                            fontWeight: isSel ? FontWeight.w800 : FontWeight.w500,
                            color: const Color(0xFF424242))),
                  ]),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 2.5,
                  width: isSel ? 40 : 0,
                  decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SECTION TITLE
// ─────────────────────────────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});
  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
        child: Row(children: [
          Text(title,
              style: TextStyle(fontFamily: 'Cairo', fontSize: sw * 0.042,
                  fontWeight: FontWeight.w800, color: const Color(0xFF1A1A1A))),
          const Spacer(),
          GestureDetector(
            onTap: () => context.go('/categories'),
            child: Text('Voir tout >',
                style: TextStyle(fontFamily: 'Cairo', fontSize: sw * 0.032,
                    fontWeight: FontWeight.w600, color: AppColors.primary)),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PRODUCTS GRID  — فلتر حقيقي من product_placement
// ─────────────────────────────────────────────────────────────────────────────
class _ProductsGrid extends StatelessWidget {
  final Query query;
  final String searchQuery;
  final String? filterType;
  final String? category;
  // معرّفات المنتجات الموجودة حالياً في سلة المستخدم — مصدرها واحد لكل الصفحة
  final Set<String> cartIds;

  const _ProductsGrid({
    required this.query,
    this.searchQuery = '',
    this.filterType,
    this.category,
    required this.cartIds,
  });

  bool _matchFilter(Map<String, dynamic> data) {
    if (filterType == null) return true;
    final placement = (data['product_placement'] as String? ?? '').toLowerCase();
    switch (filterType) {
      case 'offers':
        return placement.contains('offer') ||
            (data['oldPrice'] != null &&
                _p(data['oldPrice']) > _p(data['price']));
      case '5stars':
        return _p(data['rating']) >= 4.5;
      case 'bestseller':
        return placement.contains('best seller') ||
            placement.contains('bestseller');
      default:
        return true;
    }
  }

  bool _matchCategory(Map<String, dynamic> data) {
    if (category == null) return true;
    final cat = (data['category'] as String? ?? '').trim();
    return cat.toLowerCase() == category!.toLowerCase();
  }

  double _p(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final cardW = (sw - 10 * 2 - 8) / 2;
    final ratio = cardW / (cardW * 0.60 + 148);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SliverToBoxAdapter(
              child: SizedBox(height: 200,
                  child: Center(child: CircularProgressIndicator())));
        }
        if (snap.hasError) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('Erreur de chargement',
                  style: TextStyle(fontFamily: 'Cairo',
                      color: Colors.grey[500], fontSize: 14))),
            ),
          );
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox(height: 8));
        }

        var docs = snap.data!.docs;

        // فلتر البحث
        if (searchQuery.isNotEmpty) {
          docs = docs.where((d) {
            final name = ((d.data() as Map)['name'] as String? ?? '').toLowerCase();
            return name.contains(searchQuery);
          }).toList();
        }

        // ترتيب: منتجات الفئة المحددة + الفلتر تظهر أولاً، الباقي يظهر بعدها
        // (لا يتم إخفاء أي منتج، فقط إعادة ترتيب)
        List<QueryDocumentSnapshot> matched = [];
        List<QueryDocumentSnapshot> rest = [];
        for (final d in docs) {
          final data = d.data() as Map<String, dynamic>;
          final catOk = _matchCategory(data);
          final filterOk = _matchFilter(data);
          if (catOk && filterOk) {
            matched.add(d);
          } else {
            rest.add(d);
          }
        }
        final orderedDocs = [...matched, ...rest];

        if (orderedDocs.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('Aucun produit trouvé',
                  style: TextStyle(fontFamily: 'Cairo',
                      color: Colors.grey[500], fontSize: 14))),
            ),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: ratio,
            ),
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final doc = orderedDocs[i];
                final data = doc.data() as Map<String, dynamic>;
                return _ProductCard(
                  data: data,
                  docId: doc.id,
                  isInCart: cartIds.contains(doc.id),
                );
              },
              childCount: orderedDocs.length,
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ANIMATED BADGE PAINTER  — شعلة للـ best seller
// ─────────────────────────────────────────────────────────────────────────────
class _FlamePainter extends CustomPainter {
  final double progress;
  _FlamePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress;
    final paint = Paint()..style = PaintingStyle.fill;

    // طبقة خارجية برتقالية
    paint.color = const Color(0xFFFF6F00).withOpacity(0.85);
    final outer = Path()
      ..moveTo(size.width * 0.5, 0)
      ..cubicTo(size.width * (0.9 + 0.1 * math.sin(t * math.pi * 2)),
          size.height * 0.3,
          size.width * (0.85 - 0.1 * math.cos(t * math.pi * 2)),
          size.height * 0.6,
          size.width * 0.5, size.height)
      ..cubicTo(size.width * (0.15 + 0.1 * math.sin(t * math.pi * 2)),
          size.height * 0.6,
          size.width * (0.1 - 0.05 * math.cos(t * math.pi)),
          size.height * 0.3,
          size.width * 0.5, 0)
      ..close();
    canvas.drawPath(outer, paint);

    // طبقة داخلية صفراء
    paint.color = const Color(0xFFFFD54F).withOpacity(0.9);
    final inner = Path()
      ..moveTo(size.width * 0.5, size.height * 0.15)
      ..cubicTo(size.width * (0.75 - 0.08 * math.sin(t * math.pi * 2)),
          size.height * 0.4,
          size.width * (0.7 + 0.08 * math.cos(t * math.pi * 2)),
          size.height * 0.65,
          size.width * 0.5, size.height * 0.9)
      ..cubicTo(size.width * (0.3 - 0.08 * math.sin(t * math.pi * 2)),
          size.height * 0.65,
          size.width * (0.25 + 0.08 * math.cos(t * math.pi * 2)),
          size.height * 0.4,
          size.width * 0.5, size.height * 0.15)
      ..close();
    canvas.drawPath(inner, paint);
  }

  @override
  bool shouldRepaint(_FlamePainter old) => old.progress != progress;
}

class _FlameWidget extends StatefulWidget {
  const _FlameWidget();
  @override
  State<_FlameWidget> createState() => _FlameWidgetState();
}

class _FlameWidgetState extends State<_FlameWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
            painter: _FlamePainter(_ctrl.value),
            size: const Size(12, 16)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  LIGHTNING BOLT ANIMATION — للـ offer
// ─────────────────────────────────────────────────────────────────────────────
class _LightningWidget extends StatefulWidget {
  const _LightningWidget();
  @override
  State<_LightningWidget> createState() => _LightningWidgetState();
}

class _LightningWidgetState extends State<_LightningWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Opacity(
          opacity: 0.6 + _ctrl.value * 0.4,
          child: const Text('⚡', style: TextStyle(fontSize: 11)),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  SHIMMER STARS — للـ 5 stars
// ─────────────────────────────────────────────────────────────────────────────
class _ShimmerStars extends StatefulWidget {
  const _ShimmerStars();
  @override
  State<_ShimmerStars> createState() => _ShimmerStarsState();
}

class _ShimmerStarsState extends State<_ShimmerStars>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) {
          final delay = i / 5.0;
          final t = (_ctrl.value - delay).clamp(0.0, 1.0);
          final shine = math.sin(t * math.pi);
          return Icon(Icons.star_rounded,
              size: 10,
              color: Color.lerp(const Color(0xFFFFC107),
                  Colors.white, shine * 0.6)!);
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  NATURE PLACEMENT BADGE — شريط أخضر مع تأثير shimmer
// ─────────────────────────────────────────────────────────────────────────────
class _NatureBadge extends StatefulWidget {
  final String label;
  final String placement; // 'choisissez maintenant' | 'à l\'intérieur de la ferme'
  const _NatureBadge({required this.label, required this.placement});
  @override
  State<_NatureBadge> createState() => _NatureBadgeState();
}

class _NatureBadgeState extends State<_NatureBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _isFarm =>
      widget.placement.toLowerCase().contains('intérieur') ||
      widget.placement.toLowerCase().contains('farm') ||
      widget.placement.toLowerCase().contains('ferme');

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final shimmerX = _ctrl.value * 2 - 0.5;
        return Container(
          height: 18,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: LinearGradient(
              colors: [
                const Color(0xFF2E7D32),
                Color.lerp(const Color(0xFF43A047), const Color(0xFFA5D6A7),
                    math.max(0, math.sin(_ctrl.value * math.pi)))!,
                const Color(0xFF2E7D32),
              ],
              stops: [
                (shimmerX - 0.3).clamp(0.0, 1.0),
                shimmerX.clamp(0.0, 1.0),
                (shimmerX + 0.3).clamp(0.0, 1.0),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isFarm ? '🌱' : '🌿',
                style: const TextStyle(fontSize: 9),
              ),
              const SizedBox(width: 3),
              Flexible(
                child: Text(widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PRODUCT CARD  — النسخة الكاملة المُحدَّثة
//
//  ⚠️ هذه البطاقة لا تستعلم Firestore بنفسها لمعرفة إن كانت في السلة.
//  الحالة isInCart تأتي جاهزة من _HomeContent (نداء واحد لكل السلة)
//  بدل نداء get() مستقل لكل بطاقة — هذا ما كان يسبب الكراش وتهنيج السكرول.
// ─────────────────────────────────────────────────────────────────────────────
class _ProductCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final String docId;
  final bool isInCart;
  const _ProductCard({
    required this.data,
    required this.docId,
    required this.isInCart,
  });
  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  int _badgeIndex = 0;
  Timer? _badgeTimer;
  // حالة محلية مؤقتة لتفعيل الأيقونة فوراً بعد الضغط (تحسين بصري فقط)،
  // قبل أن يصل تحديث الـ Stream من Firestore. القيمة الحقيقية تبقى دائماً
  // widget.isInCart القادمة من الأعلى.
  bool _optimisticAdded = false;

  @override
  void initState() {
    super.initState();
    final msg2 = widget.data['message2']?.toString() ?? '';
    if (msg2.isNotEmpty) {
      _badgeTimer = Timer.periodic(const Duration(seconds: 3),
          (_) { if (mounted) setState(() => _badgeIndex = (_badgeIndex + 1) % 2); });
    }
  }

  @override
  void dispose() {
    _badgeTimer?.cancel();
    super.dispose();
  }

  double _p(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

 Future<void> _addToCart(BuildContext ctx) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  final stock = (widget.data['stock'] as num?)?.toInt();
  if (stock != null && stock <= 0) {
    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
        content: Text('Ce produit est en rupture de stock'),
        backgroundColor: Color(0xFFE53935),
        behavior: SnackBarBehavior.floating));
    return;
  }

  setState(() => _optimisticAdded = true);

  // ── زائر غير مسجل: نحفظ محلياً فقط، وما نعرضوش "سجل الدخول" هنا ──
  if (uid == null) {
    await LocalCartService.addItem(widget.docId);
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text('${widget.data['name'] ?? ''} ajouté au panier',
            style: const TextStyle(fontFamily: 'Cairo'))),
      ]),
      backgroundColor: AppColors.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
    return;
  }

  try {
    final ref = FirebaseFirestore.instance
        .collection('carts').doc(uid)
        .collection('items').doc(widget.docId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final s = await tx.get(ref);
      if (s.exists) {
        final currentQty = ((s.data() as Map)['qty'] as num?)?.toInt() ?? 1;
        if (stock != null && currentQty + 1 > stock) {
          throw Exception('STOCK_LIMIT');
        }
        tx.update(ref, {'qty': FieldValue.increment(1)});
      } else {
        tx.set(ref, {
          'productId': widget.docId,
          'qty': 1,
          'addedAt': FieldValue.serverTimestamp(),
        });
      }
    });
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text('${widget.data['name'] ?? ''} ajouté au panier',
            style: const TextStyle(fontFamily: 'Cairo'))),
      ]),
      backgroundColor: AppColors.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  } on FirebaseException catch (e) {
    if (!ctx.mounted) return;
    setState(() => _optimisticAdded = false);
    final msg = (e.code == 'unavailable')
        ? 'Pas de connexion internet, réessayez'
        : 'Erreur, réessayez';
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(msg), backgroundColor: const Color(0xFFE53935),
        behavior: SnackBarBehavior.floating));
  } catch (e) {
    if (!ctx.mounted) return;
    setState(() => _optimisticAdded = false);
    final msg = e.toString().contains('STOCK_LIMIT')
        ? 'Stock maximum atteint pour ce produit'
        : 'Erreur, réessayez';
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(msg), backgroundColor: const Color(0xFFE53935),
        behavior: SnackBarBehavior.floating));
  }
}

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final cardW = (sw - 10 * 2 - 8) / 2;
    final imgH = cardW * 0.60;

    final price = _p(widget.data['price']);
    final oldPrice = _p(widget.data['oldPrice']);
    final name = widget.data['name']?.toString() ?? '';
    final imageUrl = widget.data['imageUrl']?.toString() ?? '';
    final description = widget.data['description']?.toString() ?? '';
    final message1 = widget.data['message']?.toString() ?? '';
    final message2 = widget.data['message2']?.toString() ?? '';
    final placement = (widget.data['product_placement'] as String? ?? '').trim();
    final hasDiscount = oldPrice > price && oldPrice > 0;
    final discountDH = oldPrice - price;
    final rating = _p(widget.data['rating']).clamp(0.0, 5.0);
    final reviewCount = (widget.data['reviewCount'] as num?)?.toInt() ?? 0;
    final hasRating = rating > 0;
    final salesCount = (widget.data['salesCount'] as num?)?.toInt() ?? 0;
    final stock = (widget.data['stock'] as num?)?.toInt();
    final outOfStock = stock != null && stock <= 0;
    // الحالة الحقيقية القادمة من الـ Stream، أو التحديث الفوري المؤقت
    final addedToCart = widget.isInCart || _optimisticAdded;

    final currentBadge = (message2.isNotEmpty && _badgeIndex == 1) ? message2 : message1;
    final showBadge = currentBadge.isNotEmpty;

    // تحديد نوع placement
    final placeLower = placement.toLowerCase();
    final isChoisissez = placeLower.contains('choisissez');
    final isFerme = placeLower.contains('ferme') || placeLower.contains('intérieur');
    final isNaturePlacement = isChoisissez || isFerme;

    return GestureDetector(
      onTap: () => context.push('/product/${widget.docId}'),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Image (بدون أي badge فوقها) ──
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            child: CachedNetworkImage(
              imageUrl: imageUrl, height: imgH,
              width: double.infinity, fit: BoxFit.cover,
              placeholder: (_, __) => Container(height: imgH,
                  color: const Color(0xFFF0F0F0),
                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
              errorWidget: (_, __, ___) => Container(height: imgH,
                  color: Colors.grey[200],
                  child: const Icon(Icons.image_not_supported_rounded,
                      size: 40, color: Colors.grey)),
            ),
          ),

          // ── Info ──
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(7, 5, 7, 5),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // اسم
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 12,
                        fontWeight: FontWeight.w700, color: Color(0xFF212121),
                        height: 1.2)),

                // Rupture de stock
                if (outOfStock) ...[
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                        color: const Color(0xFFE53935).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4)),
                    child: const Text('Rupture de stock',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 8.5,
                            fontWeight: FontWeight.w700, color: Color(0xFFE53935))),
                  ),
                ],

                // وصف
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(description, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 10,
                          color: Color(0xFF757575), height: 1.2)),
                ],

                // Nature placement badge (Choisissez / Ferme)
                if (isNaturePlacement) ...[
                  const SizedBox(height: 4),
                  _NatureBadge(label: placement, placement: placement),
                ]
                // Regular badge (best seller / offer / 5stars)
                else if (showBadge) ...[
                  const SizedBox(height: 4),
                  _RegularBadge(badge: currentBadge),
                ],

                // تقييم
                if (hasRating) ...[
                  const SizedBox(height: 3),
                  Row(children: [
                    ...List.generate(5, (i) {
                      if (i < rating.floor()) {
                        return const Icon(Icons.star_rounded,
                            size: 10, color: Color(0xFFFFC107));
                      } else if (i < rating) {
                        return const Icon(Icons.star_half_rounded,
                            size: 10, color: Color(0xFFFFC107));
                      } else {
                        return const Icon(Icons.star_border_rounded,
                            size: 10, color: Color(0xFFBDBDBD));
                      }
                    }),
                    const SizedBox(width: 3),
                    if (reviewCount > 0)
                      Text('($reviewCount)',
                          style: const TextStyle(fontFamily: 'Cairo',
                              fontSize: 9, color: Color(0xFF9E9E9E))),
                  ]),
                ],

                // عدد المبيعات الحقيقي + شعلة إذا تجاوز 100
                if (salesCount > 0) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    Text('$salesCount ${salesCount == 1 ? "vente" : "ventes"}',
                        style: const TextStyle(fontFamily: 'Cairo',
                            fontSize: 9, color: Color(0xFF9E9E9E))),
                    if (salesCount > 100) ...[
                      const SizedBox(width: 3),
                      const _FlameWidget(),
                    ],
                  ]),
                ],

                const Spacer(),

                // ── السعر + زر السلة ──
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasDiscount) ...[
                          // السعر القديم — أعمق وأكبر قليلاً، مشطوب بماركور أحمر
                          Stack(clipBehavior: Clip.none, children: [
                            Text(
                              '${oldPrice.toStringAsFixed(oldPrice % 1 == 0 ? 0 : 1)} DH',
                              style: const TextStyle(
                                  fontFamily: 'Cairo', fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF4A4A4A)),
                            ),
                            Positioned.fill(
                              child: CustomPaint(
                                  painter: _MarkerStrikePainter()),
                            ),
                          ]),
                          // توفير بالدرهم
                          Text(
                            'Économisez ${discountDH.toStringAsFixed(discountDH % 1 == 0 ? 0 : 1)} DH',
                            style: const TextStyle(
                                fontFamily: 'Cairo', fontSize: 8,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF43A047)),
                          ),
                        ],
                        // السعر الحالي بالأسود
                        Text(
                          '${price.toStringAsFixed(price % 1 == 0 ? 0 : 1)} DH',
                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Colors.black),
                        ),
                      ],
                    ),
                  ),

                  // ── زر السلة — أيقونة أحدث وأبسط، حافة بيضاوية أعلى بـ25% ──
                  GestureDetector(
                    onTap: outOfStock ? null : () => _addToCart(context),
                    child: Container(
                      width: 34, height: 30, // بيضاوي: أعرض من ارتفاعه بنسبة ~25%
                      decoration: BoxDecoration(
                        color: outOfStock ? const Color(0xFFF5F5F5) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: outOfStock ? const Color(0xFFBDBDBD) : Colors.black,
                            width: 1.4),
                        boxShadow: outOfStock ? [] : [BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 4, offset: const Offset(0, 2))],
                      ),
                      child: Stack(alignment: Alignment.center, children: [
                        Icon(Icons.add_shopping_cart_rounded,
                            color: outOfStock ? const Color(0xFFBDBDBD) : Colors.black,
                            size: 15),
                        if (addedToCart && !outOfStock)
                          Positioned(
                            right: 3, top: 3,
                            child: Container(
                              width: 12, height: 12,
                              decoration: const BoxDecoration(
                                  color: Color(0xFFFF6F00),
                                  shape: BoxShape.circle),
                              child: const Center(
                                child: Text('1',
                                    style: TextStyle(color: Colors.white,
                                        fontSize: 7, fontWeight: FontWeight.w800)),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  MARKER STRIKE PAINTER — خط ماركور أحمر واقعي
// ─────────────────────────────────────────────────────────────────────────────
class _MarkerStrikePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE53935).withOpacity(0.85)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // خط غير مستقيم تماماً (ماركور واقعي)
    final path = Path()
      ..moveTo(-2, size.height * 0.52)
      ..cubicTo(
        size.width * 0.25, size.height * 0.38,
        size.width * 0.60, size.height * 0.62,
        size.width + 2, size.height * 0.48,
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MarkerStrikePainter _) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
//  REGULAR BADGE — best seller / offer / 5stars / autres
// ─────────────────────────────────────────────────────────────────────────────
class _RegularBadge extends StatelessWidget {
  final String badge;
  const _RegularBadge({required this.badge});

  @override
  Widget build(BuildContext context) {
    final lower = badge.toLowerCase();
    final isBestSeller = lower.contains('best seller') || lower.contains('bestseller');
    final isOffer = lower.contains('offer');
    final is5Stars = lower.contains('5 star') || lower.contains('5star') ||
        lower.contains('étoile');

    if (isBestSeller) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFFF6F00).withOpacity(0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFFF6F00).withOpacity(0.4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const _FlameWidget(),
            const SizedBox(width: 3),
            Text(badge, style: const TextStyle(fontFamily: 'Cairo', fontSize: 9,
                fontWeight: FontWeight.w700, color: Color(0xFFE65100))),
          ]),
        ),
      ]);
    }

    if (isOffer) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
            color: const Color(0xFFFFF176),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFFFD600).withOpacity(0.6))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const _LightningWidget(),
          const SizedBox(width: 2),
          Text(badge, style: const TextStyle(fontFamily: 'Cairo', fontSize: 9,
              fontWeight: FontWeight.w700, color: Color(0xFF827717))),
        ]),
      );
    }

    if (is5Stars) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFFFC107).withOpacity(0.5))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const _ShimmerStars(),
          const SizedBox(width: 3),
          Text(badge, style: const TextStyle(fontFamily: 'Cairo', fontSize: 9,
              fontWeight: FontWeight.w700, color: Color(0xFFFF8F00))),
        ]),
      );
    }

    // Default badge برتقالي
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6F00).withOpacity(0.10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFFF6F00).withOpacity(0.35)),
      ),
      child: Text(badge, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontFamily: 'Cairo', fontSize: 9,
              fontWeight: FontWeight.w700, color: Color(0xFFE65100))),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  HERO SLIDER
// ─────────────────────────────────────────────────────────────────────────────
class _HeroSlider extends StatefulWidget {
  const _HeroSlider();
  @override
  State<_HeroSlider> createState() => _HeroSliderState();
}

class _HeroSliderState extends State<_HeroSlider> {
  final _ctrl = PageController();
  int _page = 0;
  Timer? _timer;
  List<DocumentSnapshot> _slides = [];

  final _stream = FirebaseFirestore.instance
      .collection('slider').orderBy('order').snapshots();

  @override
  void dispose() { _timer?.cancel(); _ctrl.dispose(); super.dispose(); }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _slides.isEmpty || !_ctrl.hasClients) return;
      _ctrl.animateToPage((_page + 1) % _slides.length,
          duration: const Duration(milliseconds: 700), curve: Curves.easeInOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final double h = sw * 0.312;
    return StreamBuilder<QuerySnapshot>(
      stream: _stream,
      builder: (ctx, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) return _ph(h);
        _slides = snap.data!.docs;
        if (_page >= _slides.length) _page = 0;
        _startTimer();
        return Container(
          height: h,
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12),
                  blurRadius: 10, offset: const Offset(0, 4))]),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(children: [
              PageView.builder(
                controller: _ctrl,
                itemCount: _slides.length,
                onPageChanged: (i) { if (mounted) setState(() => _page = i); },
                itemBuilder: (_, i) {
                  final d = _slides[i].data() as Map<String, dynamic>;
                  return Stack(fit: StackFit.expand, children: [
                    CachedNetworkImage(
                      imageUrl: d['imageUrl']?.toString() ?? '',
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: Colors.grey[200]),
                      errorWidget: (_, __, ___) => Container(
                          color: AppColors.primaryLight.withOpacity(0.2),
                          child: const Icon(Icons.broken_image_rounded,
                              size: 60, color: Colors.grey)),
                    ),
                    const DecoratedBox(decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: [Colors.transparent, Colors.black54],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter))),
                    if ((d['title']?.toString() ?? '').isNotEmpty)
                      Positioned(bottom: 22, left: 12, right: 40,
                          child: Text(d['title'].toString(),
                              style: const TextStyle(fontFamily: 'Cairo',
                                  color: Colors.white, fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  shadows: [Shadow(color: Colors.black38, blurRadius: 4)]))),
                  ]);
                },
              ),
              Positioned(bottom: 8, left: 0, right: 0,
                child: Row(mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_slides.length, (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: _page == i ? 16 : 5, height: 5,
                    decoration: BoxDecoration(
                        color: _page == i ? Colors.white
                            : Colors.white.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(3)),
                  ))),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _ph(double h) => Container(
      height: h, margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12)),
      child: const Center(child: CircularProgressIndicator()));
}
// ─────────────────────────────────────────────────────────────────────────────
//  FORMULES PROMO BANNER — دعوة لاكتشاف الفورميلات مع صورهم من Firestore
// ─────────────────────────────────────────────────────────────────────────────
class _FormulesPromoBanner extends StatelessWidget {
  final double sw;
  const _FormulesPromoBanner({required this.sw});

  String _extractImageUrl(Map<String, dynamic> d) {
    for (final key in const ['imageURL', 'imageUrl', 'imageurl']) {
      final v = d[key];
      if (v is String && v.isNotEmpty) return v;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('formules')
          .limit(3)
          .snapshots(),
      builder: (ctx, snap) {
        final docs = snap.data?.docs ?? [];
        final images = docs
            .map((d) => _extractImageUrl(d.data() as Map<String, dynamic>))
            .where((u) => u.isNotEmpty)
            .toList();

        return GestureDetector(
          onTap: () {
            // ⚠️ عدّل الاسم إن كان مختلفاً في app_routes.dart
            context.push(Routes.formules);
          },
          child: Container(
            margin: EdgeInsets.fromLTRB(12, sw * 0.032, 12, 0),
            constraints: BoxConstraints(minHeight: sw * 0.234),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                colors: [
                  AppColors.primaryDark,
                  AppColors.primary,
                  AppColors.primaryLight,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.30),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(clipBehavior: Clip.hardEdge, children: [
                // بقعة زخرفية أصلية
                Positioned(
                  left: -sw * 0.05, bottom: -sw * 0.06,
                  child: Container(
                    width: sw * 0.3, height: sw * 0.3,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.08),
                    ),
                  ),
                ),

                // ── رسومات خفيفة موزعة (أكثر وضوحاً) ──
                // أوراق — زاوية علوية يمنى
                Positioned(
                  top: sw * 0.008, right: sw * 0.018,
                  child: Transform.rotate(
                    angle: -0.25,
                    child: Opacity(
                      opacity: 0.24,
                      child: Text('🍃', style: TextStyle(fontSize: sw * 0.052)),
                    ),
                  ),
                ),
                // ورقة — أسفل يسار الوسط
                Positioned(
                  bottom: sw * 0.012, left: sw * 0.26,
                  child: Transform.rotate(
                    angle: 0.3,
                    child: Opacity(
                      opacity: 0.22,
                      child: Text('🍃', style: TextStyle(fontSize: sw * 0.042)),
                    ),
                  ),
                ),
                // ورقة إضافية — أعلى يسار
                Positioned(
                  top: sw * 0.012, left: sw * 0.05,
                  child: Transform.rotate(
                    angle: -0.4,
                    child: Opacity(
                      opacity: 0.80,
                      child: Text('🍃', style: TextStyle(fontSize: sw * 0.038)),
                    ),
                  ),
                ),
                Positioned(
                  top: sw * 0.012, left: sw * 0.73,
                  child: Transform.rotate(
                    angle: -0.4,
                    child: Opacity(
                      opacity: 0.38,
                      child: Text('🍃', style: TextStyle(fontSize: sw * 0.048)),
                    ),
                  ),
                ),
                // ورقة إضافية — أسفل يمين
                Positioned(
                  bottom: sw * 0.03, right: sw * 0.05,
                  child: Transform.rotate(
                    angle: 0.15,
                    child: Opacity(
                      opacity: 0.12,
                      child: Text('🍃', style: TextStyle(fontSize: sw * 0.035)),
                    ),
                  ),
                ),
                // ورقة في المنتصف (بين النص والصور)
                Positioned(
                  top: sw * 0.12, left: sw * 0.4,
                  child: Transform.rotate(
                    angle: -0.12,
                    child: Opacity(
                      opacity: 0.28,
                      child: Text('🍃', style: TextStyle(fontSize: sw * 0.1)),
                    ),
                  ),
                ),
                // بيضة — يسار
                Positioned(
                  top: sw * 0.05, left: sw * 0.18,
                  child: Opacity(
                    opacity: 0.28,
                    child: Text('🌳', style: TextStyle(fontSize: sw * 0.28)),
                  ),
                ),
                // دجاجة — أسفل وسط-يمين
               

                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: sw * 0.04, vertical: sw * 0.028),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // ── النص + الزر ──
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(children: [
                              Text('🌿', style: TextStyle(fontSize: sw * 0.045)),
                              SizedBox(width: sw * 0.015),
                              Expanded(
                                child: Text('Nos Formules',
                                    style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: sw * 0.035,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white)),
                              ),
                            ]),
                            SizedBox(height: sw * 0.008),
                            Text(
                              'Des paniers pensés pour vous —\ndécouvrez la sélection idéale',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: sw * 0.028,
                                  color: Colors.white.withOpacity(0.95),
                                  height: 1.35),
                            ),
                            SizedBox(height: sw * 0.018),
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: sw * 0.028, vertical: sw * 0.01),
                              decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('Découvrir',
                                      style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: sw * 0.024,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.primaryDark)),
                                  SizedBox(width: sw * 0.008),
                                  Icon(Icons.arrow_forward_rounded,
                                      size: sw * 0.025,
                                      color: AppColors.primaryDark),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(width: sw * 0.03),

                      // ── صور الفورميلات المتراكبة (تراكب أكبر بـ5%) ──
                      SizedBox(
                        width: sw * 0.320,
                        height: sw * 0.27,
                        child: images.isEmpty
                            ? Icon(Icons.eco_rounded,
                                color: Colors.white.withOpacity(0.5),
                                size: sw * 0.12)
                            : Stack(
                                alignment: Alignment.center,
                                children: List.generate(images.length, (i) {
                                  final offset = i * sw * 0.0803;
                                  final size = sw * 0.19 - (i * sw * 0.014);
                                  return Positioned(
                                    right: offset,
                                    child: Container(
                                      width: size,
                                      height: size,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Colors.white, width: 2.3),
                                        boxShadow: [
                                          BoxShadow(
                                              color: Colors.black
                                                  .withOpacity(0.18),
                                              blurRadius: 6,
                                              offset: const Offset(0, 3)),
                                        ],
                                      ),
                                      child: ClipOval(
                                        child: CachedNetworkImage(
                                          imageUrl: images[i],
                                          fit: BoxFit.cover,
                                          placeholder: (_, __) => Container(
                                              color: Colors.white
                                                  .withOpacity(0.2)),
                                          errorWidget: (_, __, ___) =>
                                              Container(
                                                  color: Colors.white
                                                      .withOpacity(0.2),
                                                  child: const Icon(
                                                      Icons.image_rounded,
                                                      color: Colors.white)),
                                        ),
                                      ),
                                    ),
                                  );
                                }).reversed.toList(),
                              ),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
//  CATEGORIES HEADER — فلتر حقيقي + لمسة طبيعية + تمرير للمحدد
// ─────────────────────────────────────────────────────────────────────────────
class _CategoriesHeader extends SliverPersistentHeaderDelegate {
  final String? selectedCategory;
  final ValueChanged<String?> onCategorySelected;

  const _CategoriesHeader({
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  static const _allCats = [
    'Tout',
    'Saison des récoltes',
    'Légumes',
    'Fruits',
    'Œufs',
    'Viandes',
    'Laitiers',
    'Huiles',
    'Miel',
    'Herbes',
  ];

  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;
  @override
  bool shouldRebuild(covariant _CategoriesHeader old) =>
      old.selectedCategory != selectedCategory;

  @override
  Widget build(BuildContext ctx, double shrink, bool overlaps) {
    return _CategoriesBar(
      allCats: _allCats,
      selected: selectedCategory,
      onSelected: onCategorySelected,
    );
  }
}

class _CategoriesBar extends StatefulWidget {
  final List<String> allCats;
  final String? selected;
  final ValueChanged<String?> onSelected;
  const _CategoriesBar({
    required this.allCats,
    required this.selected,
    required this.onSelected,
  });
  @override
  State<_CategoriesBar> createState() => _CategoriesBarState();
}

class _CategoriesBarState extends State<_CategoriesBar> {
  final _scrollCtrl = ScrollController();
  final List<GlobalKey> _keys = [];

  @override
  void initState() {
    super.initState();
    _keys.addAll(List.generate(widget.allCats.length, (_) => GlobalKey()));
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cats = widget.allCats; // ترتيب ثابت، بدون إعادة ترتيب

    return Container(
      color: Colors.white,
      child: Column(children: [
        Expanded(
          child: ListView.separated(
            controller: _scrollCtrl,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: cats.length,
            separatorBuilder: (_, __) => const SizedBox(width: 18),
            itemBuilder: (_, i) {
              final cat = cats[i];
              final isTout = cat == 'Tout';
              final isSel = isTout
                  ? widget.selected == null
                  : widget.selected == cat;

              return GestureDetector(
                key: _keys[i],
                onTap: () => widget.onSelected(isTout ? null : cat),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: isSel ? FontWeight.w800 : FontWeight.w500,
                        color: const Color(0xFF616161),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(cat),
                        // لمسة طبيعية: ورقة صغيرة متحركة بجانب الفئة المحددة
                        if (isSel && !isTout) ...[
                          const SizedBox(width: 3),
                          const _LeafBadge(),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 3),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 2.5,
                      width: isSel ? 36 : 0,
                      decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Container(height: 1, color: const Color(0xFFEEEEEE)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  LEAF BADGE — ورقة شجرة صغيرة متحركة تميز الفئة المحددة
// ─────────────────────────────────────────────────────────────────────────────
class _LeafBadge extends StatefulWidget {
  const _LeafBadge();
  @override
  State<_LeafBadge> createState() => _LeafBadgeState();
}

class _LeafBadgeState extends State<_LeafBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _rotate;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
    _rotate = Tween<double>(begin: -0.18, end: 0.18).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Transform.rotate(
          angle: _rotate.value,
          child: const Text('🌿', style: TextStyle(fontSize: 11)),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  BOTTOM NAV BAR — عداد سلة حقيقي من Firestore
// ─────────────────────────────────────────────────────────────────────────────
class IFarmBottomNav extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const IFarmBottomNav({super.key, required this.currentIndex, required this.onTap});
  @override
  State<IFarmBottomNav> createState() => _IFarmBottomNavState();
}

class _IFarmBottomNavState extends State<IFarmBottomNav> {
  int _msgIndex = 0;
  Timer? _cycleTimer;

  static const _messages = [
    '🚚 Livraison gratuite',
    '🌾 Saison des récoltes — Produits de saison',
  ];
  static const _durations = [3500, 3000];

  @override
  void initState() { super.initState(); _scheduleNext(); }

  void _scheduleNext() {
    _cycleTimer?.cancel();
    _cycleTimer = Timer(Duration(milliseconds: _durations[_msgIndex]), () {
      if (!mounted) return;
      setState(() => _msgIndex = (_msgIndex + 1) % _messages.length);
      _scheduleNext();
    });
  }

  @override
  void dispose() { _cycleTimer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.home_rounded, 'Accueil'),
      (Icons.grid_view_rounded, 'Catégories'),
      (Icons.person_outline_rounded, 'Vous'),
      (Icons.shopping_cart_outlined, 'Panier'),
    ];
    final isHarvest = _msgIndex == 1;

    return Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        color: isHarvest ? const Color(0xFFE65100) : AppColors.primary,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, anim) => SlideTransition(
            position: Tween<Offset>(begin: const Offset(1.0, 0), end: Offset.zero)
                .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: FadeTransition(opacity: anim, child: child)),
          child: Text(_messages[_msgIndex], key: ValueKey(_msgIndex),
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13,
                  fontWeight: FontWeight.w700, color: Colors.white)),
        ),
      ),
      Container(
        decoration: const BoxDecoration(color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFEEEEEE), width: 1))),
        child: Row(
          children: List.generate(items.length, (i) {
            final isSel = widget.currentIndex == i;
            final (icon, label) = items[i];
            return Expanded(
              child: GestureDetector(
                onTap: () => widget.onTap(i),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Stack(clipBehavior: Clip.none, children: [
                      Icon(icon, size: 24,
                          color: isSel ? AppColors.primary : const Color(0xFF9E9E9E)),
                      if (i == 3)
                        Positioned(right: -6, top: -4,
                          child: StreamBuilder<QuerySnapshot>(
                            stream: FirebaseAuth.instance.currentUser == null
                                ? const Stream.empty()
                                : FirebaseFirestore.instance
                                    .collection('carts')
                                    .doc(FirebaseAuth.instance.currentUser!.uid)
                                    .collection('items')
                                    .snapshots(),
                            builder: (_, s) {
                              final count = s.data?.docs.length ?? 0;
                              if (count == 0) return const SizedBox();
                              return Container(
                                width: 16, height: 16,
                                decoration: BoxDecoration(
                                    color: AppColors.primary, shape: BoxShape.circle),
                                child: Center(child: Text(count > 9 ? '9+' : '$count',
                                    style: const TextStyle(color: Colors.white,
                                        fontSize: 9, fontWeight: FontWeight.w800))),
                              );
                            },
                          ),
                        ),
                    ]),
                    const SizedBox(height: 3),
                    Text(label, style: TextStyle(fontFamily: 'Cairo', fontSize: 10,
                        fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                        color: isSel ? AppColors.primary : const Color(0xFF9E9E9E))),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(top: 3),
                      width: isSel ? 20 : 0, height: 2,
                      decoration: BoxDecoration(color: AppColors.primary,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ]),
                ),
              ),
            );
          }),
        ),
      ),
      Container(color: Colors.white,
          height: MediaQuery.of(context).padding.bottom),
    ]);
  }
}
// hamdllah saliit ;)