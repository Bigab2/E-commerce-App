import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/localization/app_locale_service.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_colors.dart';
// ⚠️ Vérifie que ce chemin correspond bien à l'emplacement réel de app_routes.dart
// dans ton projet (lib/routes/app_routes.dart).
import '../../routes/app_routes.dart';

/// Parse robuste : certains champs numériques peuvent être stockés côté
/// Firestore comme String ("450") au lieu d'un number. N'échoue jamais.
num _parseNum(dynamic value, [num fallback = 0]) {
  if (value == null) return fallback;
  if (value is num) return value;
  if (value is String) {
    return num.tryParse(value.trim().replaceAll(',', '.')) ?? fallback;
  }
  return fallback;
}

/// Formate un prix sans décimales inutiles : 12.0 -> "12", 12.5 -> "12.5"
String _fmtPrice(num v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
}

// ─────────────────────────────────────────────────────────────────────────────
//  FIRESTORE PRODUCT MODEL
// ─────────────────────────────────────────────────────────────────────────────
class FarmProduct {
  final String  id;
  final String  name;
  final String  description;
  final String  category;
  final String  imageUrl;
  final num     price;
  final num?    oldPrice;
  final String  unit;
  final int     stock;
  final bool    isAvailable;
  final String  placement;
  final DateTime? createdAt;

  const FarmProduct({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.imageUrl,
    required this.price,
    this.oldPrice,
    required this.unit,
    required this.stock,
    required this.isAvailable,
    required this.placement,
    this.createdAt,
  });

  factory FarmProduct.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return FarmProduct(
      id:          doc.id,
      name:        d['name']              as String? ?? '',
      description: d['description']       as String? ?? '',
      category:    d['category']          as String? ?? '',
      imageUrl:    d['imageUrl']          as String? ?? '',
      price:       _parseNum(d['price']),
      oldPrice:    d['oldPrice'] == null ? null : _parseNum(d['oldPrice']),
      unit:        d['unit']              as String? ?? '',
      stock:       _parseNum(d['stock']).toInt(),
      // ⚠️ Ce champ vaut `true` par défaut si absent de Firestore.
      // Ne JAMAIS filtrer côté requête avec `.where('isAvailable', isEqualTo: true)`
      // sinon tout document où ce champ n'existe pas sera silencieusement exclu.
      isAvailable: d['isAvailable']       as bool?   ?? true,
      placement:   (d['product placement'] as String? ?? '').trim(),
      createdAt:   d['createdAt'] is Timestamp
          ? (d['createdAt'] as Timestamp).toDate()
          : null,
    );
  }

  bool get isBestSeller => placement.toLowerCase().contains('best seller');
  bool get isNew        => placement.toLowerCase().contains('new');
  bool get isPromo      => oldPrice != null && oldPrice! > price;
  int  get discountPct  =>
      isPromo ? (((oldPrice! - price) / oldPrice!) * 100).round() : 0;
}

// ─────────────────────────────────────────────────────────────────────────────
//  FORMULE MODEL  (collection Firestore "formules": title, imageUrl)
// ─────────────────────────────────────────────────────────────────────────────
class FormuleMeta {
  final String id;
  final String title;
  final String imageUrl;

  const FormuleMeta({
    required this.id,
    required this.title,
    required this.imageUrl,
  });

  factory FormuleMeta.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    // ⚠️ Le champ Firestore s'appelle "imageURL" (U et R L majuscules) — on
    // accepte aussi "imageUrl" au cas où la casse changerait un jour.
    String imageUrl = '';
    for (final key in const ['imageURL', 'imageUrl', 'imageurl']) {
      final v = d[key];
      if (v is String && v.isNotEmpty) { imageUrl = v; break; }
    }
    return FormuleMeta(
      id:       doc.id,
      title:    d['title'] as String? ?? '',
      imageUrl: imageUrl,
    );
  }
}

/// Style visuel (couleur / emoji / accroche) associé à chaque formule,
/// déduit du titre Firestore pour rester cohérent sans champs supplémentaires.
class _FormuleStyle {
  final Color  color;
  final String emoji;
  final String tagline;
  const _FormuleStyle(this.color, this.emoji, this.tagline);
}

_FormuleStyle _styleForFormule(String title) {
  final t = title.toLowerCase();
  if (t.contains('beldi')) {
    return const _FormuleStyle(Color(0xFF9A6B24), '🌾', 'Le goût authentique');
  }
  if (t.contains('sain') || t.contains('sahi') || t.contains('healthy')) {
    return const _FormuleStyle(AppColors.primary, '🥗', 'Équilibre & bien-être');
  }
  if (t.contains('saison')) {
    return const _FormuleStyle(AppColors.accent, '🍂', 'Au rythme des saisons');
  }
  return const _FormuleStyle(AppColors.primaryDark, '🌿', 'Notre sélection');
}

// ─────────────────────────────────────────────────────────────────────────────
//  CATEGORY META  (UI only — no products count from here)
// ─────────────────────────────────────────────────────────────────────────────
class _CatMeta {
  final String id;
  final String name;
  final String subtitle;
  final String emoji;
  final Color  color;
  final Color  colorLight;
  final List<String> subFilters;

  const _CatMeta({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.emoji,
    required this.color,
    required this.colorLight,
    required this.subFilters,
  });

  String localizedName(BuildContext context) {
    final trans = context.tr('cat_$id');
    return trans != 'cat_$id' ? trans : name;
  }

  String localizedSubtitle(BuildContext context) {
    final trans = context.tr('cat_${id}_sub');
    return trans != 'cat_${id}_sub' ? trans : subtitle;
  }
}

const _kMeta = <_CatMeta>[
  _CatMeta(
    id: 'legumes', name: 'Légumes', subtitle: 'Frais du terroir',
    emoji: '🥦', color: AppColors.primary, colorLight: Color(0xFFE8F5EE),
    subFilters: ['Tout', 'Légumes verts', 'Légumes de saison', 'Légumes Couscous', 'Racines', 'Best Seller'],
  ),
  _CatMeta(
    id: 'fruits', name: 'Fruits', subtitle: 'Cueillis à maturité',
    emoji: '🍊', color: AppColors.accent, colorLight: Color(0xFFFFF3E0),
    subFilters: ['Tout', 'Agrumes', 'Fruits d\'été', 'Fruits secs', 'Best Seller'],
  ),
  _CatMeta(
    id: 'herbes', name: 'Herbes & Épices', subtitle: 'Arômes du Maroc',
    emoji: '🌿', color: AppColors.primaryLight, colorLight: Color(0xFFEDF7F2),
    subFilters: ['Tout', 'Herbes fraîches', 'Épices', 'Mélanges', 'Best Seller'],
  ),
  _CatMeta(
    id: 'huiles', name: 'Huiles & Conserves', subtitle: 'Produits artisanaux',
    emoji: '🫒', color: Color(0xFF7D6608), colorLight: Color(0xFFFAF7E0),
    subFilters: ['Tout', 'Huiles', 'Conserves', 'Confits', 'Best Seller'],
  ),
  _CatMeta(
    id: 'laitier', name: 'Produits Laitiers', subtitle: 'Du producteur à vous',
    emoji: '🧀', color: AppColors.warning, colorLight: Color(0xFFFFF8E1),
    subFilters: ['Tout', 'Fromages', 'Laits fermentés', 'Beurre', 'Best Seller'],
  ),
  _CatMeta(
    id: 'cereales', name: 'Céréales & Légumes secs', subtitle: 'Richesses du terroir',
    emoji: '🌾', color: AppColors.secondary, colorLight: Color(0xFFEDF5F1),
    subFilters: ['Tout', 'Céréales', 'Légumes secs', 'Farines', 'Best Seller'],
  ),
  _CatMeta(
    id: 'miel', name: 'Miel & Ruche', subtitle: 'Or liquide du Maroc',
    emoji: '🍯', color: Color(0xFFE67E00), colorLight: Color(0xFFFFF3DC),
    subFilters: ['Tout', 'Miels purs', 'Pollen', 'Gelée royale', 'Best Seller'],
  ),
  _CatMeta(
    id: 'viandes', name: 'Viandes & Volailles', subtitle: 'Élevage traditionnel',
    emoji: '🥩', color: AppColors.error, colorLight: Color(0xFFFFEBEE),
    subFilters: ['Tout', 'Volailles', 'Viandes rouges', 'Charcuterie Halal', 'Best Seller'],
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
//  CATEGORIES SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});
  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen>
    with TickerProviderStateMixin {
  late final AnimationController _staggerCtrl;
  final List<Animation<double>> _itemAnims = [];

  @override
  void initState() {
    super.initState();
    _staggerCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
    for (int i = 0; i < _kMeta.length; i++) {
      final start = (i * 0.08).clamp(0.0, 0.7);
      final end   = (start + 0.35).clamp(0.0, 1.0);
      _itemAnims.add(CurvedAnimation(
        parent: _staggerCtrl,
        curve: Interval(start, end, curve: Curves.easeOutBack)));
    }
    Future.delayed(const Duration(milliseconds: 80),
        () { if (mounted) _staggerCtrl.forward(); });
  }

  @override
  void dispose() {
    _staggerCtrl.dispose();
    super.dispose();
  }

  void _openSearch() {
    showSearch(context: context, delegate: _CategorySearchDelegate());
  }

  void _openCategory(_CatMeta meta) {
    HapticFeedback.selectionClick();
    Navigator.push(context, PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (_, anim, __) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: CategoryDetailScreen(meta: meta),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final sw         = MediaQuery.of(context).size.width;
    // Largeur de référence utilisée pour TOUTES les tailles (polices, icônes,
    // paddings). On la plafonne à 480 pour éviter des éléments démesurés sur
    // grand écran (desktop / tablette) : sur mobile (sw <= 480) `rw == sw`,
    // donc le rendu mobile est strictement inchangé.
    final rw          = sw > 480 ? 480.0 : sw;
    final crossCount  = sw >= 900 ? 4 : (sw >= 600 ? 3 : 2);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          // Empêche la grille de s'étirer sur toute la largeur d'un écran
          // desktop tout en restant invisible sur mobile (largeur réelle
          // toujours < 1100).
          constraints: const BoxConstraints(maxWidth: 1100),
          child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── App bar ───────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: rw * 0.4,
            collapsedHeight: kToolbarHeight,
            pinned: true,
            stretch: true,
            backgroundColor: AppColors.primaryDark,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground],
              background: _Header(sw: rw, onSearchTap: _openSearch),
            ),
          ),

          // ── Promo banner ──────────────────────────────────────────────
          SliverToBoxAdapter(child: _PromoBanner(sw: rw)),

          // ── Les Formules ──────────────────────────────────────────────
          SliverToBoxAdapter(child: _FormulesSection(sw: rw)),

          // ── Section header (catégories) ─────────────────────────────
          SliverToBoxAdapter(child: _SectionTitle(sw: rw, count: _kMeta.length)),

          // ── Grid ──────────────────────────────────────────────────────
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
                rw * 0.04, 0, rw * 0.04, rw * 0.28),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount:   crossCount,
                mainAxisSpacing:  rw * 0.035,
                crossAxisSpacing: rw * 0.035,
                childAspectRatio: sw >= 600 ? 0.82 : 0.76,
              ),
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final cat  = _kMeta[i];
                  final anim = i < _itemAnims.length
                      ? _itemAnims[i] : _itemAnims.last;
                  return ScaleTransition(
                    scale: anim,
                    child: FadeTransition(
                      opacity: anim,
                      child: _CategoryCard(
                        meta: cat, sw: rw,
                        onTap: () => _openCategory(cat),
                      ),
                    ),
                  );
                },
                childCount: _kMeta.length,
              ),
            ),
          ),
        ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SEARCH  (icône en coin → recherche plein écran native)
// ─────────────────────────────────────────────────────────────────────────────
class _CategorySearchDelegate extends SearchDelegate<void> {
  _CategorySearchDelegate()
      : super(searchFieldLabel: AppStrings.get('search_categories_hint'));

  List<_CatMeta> get _results => _kMeta.where((c) =>
      c.name.toLowerCase().contains(query.toLowerCase()) ||
      c.subtitle.toLowerCase().contains(query.toLowerCase()) ||
      AppStrings.get('cat_${c.id}').toLowerCase().contains(query.toLowerCase()) ||
      AppStrings.get('cat_${c.id}_sub').toLowerCase().contains(query.toLowerCase())).toList();

  @override
  ThemeData appBarTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(fontFamily: 'Cairo', color: Colors.white70),
      ),
      textTheme: base.textTheme.copyWith(
        titleLarge: const TextStyle(fontFamily: 'Cairo', color: Colors.white),
      ),
    );
  }

  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        icon: const Icon(Icons.close_rounded),
        onPressed: () => query = '',
      ),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back_ios_new_rounded),
    onPressed: () => close(context, null),
  );

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    final items = query.isEmpty ? _kMeta : _results;
    if (items.isEmpty) {
      return Center(
        child: Text(AppStrings.get('no_categories_found'),
            style: const TextStyle(fontFamily: 'Cairo', color: AppColors.textLight)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final c = items[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: c.colorLight,
            child: Text(c.emoji, style: const TextStyle(fontSize: 20)),
          ),
          title: Text(c.localizedName(context),
              style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          subtitle: Text(c.localizedSubtitle(context), style: const TextStyle(fontFamily: 'Cairo')),
          onTap: () {
            close(context, null);
            Navigator.push(context, PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 350),
              pageBuilder: (_, anim, __) => SlideTransition(
                position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                    .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                child: CategoryDetailScreen(meta: c),
              ),
            ));
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  HEADER
// ─────────────────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final double sw;
  final VoidCallback onSearchTap;
  const _Header({required this.sw, required this.onSearchTap});

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [AppColors.primaryDark, AppColors.primary, AppColors.primaryLight]),
        ),
      ),
      Positioned(top: -sw * 0.15, right: -sw * 0.15,
          child: _Blob(size: sw * 0.55, opacity: 0.07)),
      Positioned(bottom: sw * 0.1, left: -sw * 0.05,
          child: _Blob(size: sw * 0.32, opacity: 0.06)),
      Positioned(bottom: 0, right: 0,
        child: Opacity(opacity: 0.06,
          child: Icon(Icons.grid_4x4_rounded,
              size: sw * 0.4, color: Colors.white))),
      SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              sw * 0.06, sw * 0.02, sw * 0.06, sw * 0.07),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Row(children: [
                Text('🇲🇦', style: TextStyle(fontSize: sw * 0.052)),
                SizedBox(width: sw * 0.02),
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: sw * 0.025, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: Text(
                    AppLocaleService.isRtl ? 'منتجات مغربية 100%' : 'Produits 100% Marocains',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: sw * 0.028,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Spacer(),
                _SearchButton(sw: sw, onTap: onSearchTap),
              ]),
              SizedBox(height: sw * 0.028),
              Text(
                context.tr('categories_title'),
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: sw * 0.07,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    ]);
  }
}

class _SearchButton extends StatelessWidget {
  final double sw;
  final VoidCallback onTap;
  const _SearchButton({required this.sw, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: sw * 0.11,
        height: sw * 0.11,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.32)),
        ),
        child: Icon(Icons.search_rounded,
            color: Colors.white, size: sw * 0.052),
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final double size, opacity;
  const _Blob({required this.size, required this.opacity});
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withOpacity(opacity)));
}

// ─────────────────────────────────────────────────────────────────────────────
//  PROMO BANNER
// ─────────────────────────────────────────────────────────────────────────────
class _PromoBanner extends StatelessWidget {
  final double sw;
  const _PromoBanner({required this.sw});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.fromLTRB(sw * 0.04, sw * 0.045, sw * 0.04, 0),
      height: sw * 0.27,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFFE65100), AppColors.accent, AppColors.warning]),
        boxShadow: [BoxShadow(
          color: AppColors.accent.withOpacity(0.28),
          blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(right: -sw * 0.03, top: -sw * 0.03,
          child: Container(
            width: sw * 0.28, height: sw * 0.28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.1)))),
        Positioned(right: sw * 0.04, bottom: 0,
          child: Text('🌿',
              style: TextStyle(fontSize: sw * 0.16))),
        Padding(
          padding: EdgeInsets.fromLTRB(
              sw * 0.05, sw * 0.04, sw * 0.33, sw * 0.04),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Saison Printanière 🌸',
                style: TextStyle(
                  fontFamily: 'Cairo', fontSize: sw * 0.037,
                  fontWeight: FontWeight.w800, color: Colors.white)),
              SizedBox(height: sw * 0.008),
              Text('Légumes frais du terroir marocain',
                style: TextStyle(
                  fontFamily: 'Cairo', fontSize: sw * 0.027,
                  color: Colors.white70)),
              SizedBox(height: sw * 0.016),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  // Redirige vers l'écran d'accueil (produits mis en avant).
                  // ⚠️ Vérifie que `Routes.home` correspond bien à la route
                  // de ta home screen dans app_routes.dart (adapte le nom si
                  // besoin, ex: Routes.homePath()).
                  context.go(Routes.home);
                },
                child: Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: sw * 0.028, vertical: sw * 0.007),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20)),
                  child: Text('Voir les offres →',
                    style: TextStyle(
                      fontFamily: 'Cairo', fontSize: sw * 0.025,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFE65100))),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  LES FORMULES  (Beldi / Sain / Saisonnier — depuis Firestore "formules")
// ─────────────────────────────────────────────────────────────────────────────
class _FormulesSection extends StatelessWidget {
  final double sw;
  const _FormulesSection({required this.sw});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(sw * 0.05, sw * 0.06, sw * 0.05, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 3, height: 18,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(4)),
            ),
            SizedBox(width: sw * 0.025),
            Expanded(
              child: Text('Les Formules',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: sw * 0.042,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
            ),
            Text('Paniers thématiques',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: sw * 0.026,
                color: AppColors.textLight)),
          ]),
          SizedBox(height: sw * 0.035),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('formules')
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return SizedBox(
                  height: sw * 0.5,
                  child: Row(
                    children: List.generate(3, (i) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                            right: i < 2 ? sw * 0.03 : 0),
                        child: _FormuleSkeleton(sw: sw),
                      ),
                    )),
                  ),
                );
              }
              if (snap.hasError) {
                return SizedBox(
                  height: sw * 0.5,
                  child: Center(
                    child: Text('Erreur de chargement des formules',
                        style: TextStyle(
                          fontFamily: 'Cairo', color: AppColors.textLight)),
                  ),
                );
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return SizedBox(
                  height: sw * 0.5,
                  child: Center(
                    child: Text('Aucune formule disponible pour le moment',
                        style: TextStyle(
                          fontFamily: 'Cairo', color: AppColors.textLight)),
                  ),
                );
              }
              final formules = docs.map((d) => FormuleMeta.fromDoc(d)).toList();
              return SizedBox(
                height: sw * 0.5,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(formules.length, (i) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                          right: i < formules.length - 1 ? sw * 0.03 : 0),
                      child: _FormuleCard(formule: formules[i], sw: sw),
                    ),
                  )),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FormuleCard extends StatelessWidget {
  final FormuleMeta formule;
  final double sw;
  const _FormuleCard({required this.formule, required this.sw});

  @override
  Widget build(BuildContext context) {
    final style = _styleForFormule(formule.title);

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        // ⚠️ On envoie l'ID du document (ex: "formulesBeldi"), pas le titre :
        // c'est une correspondance exacte et fiable, contrairement au texte
        // affiché qui peut varier.
        context.push(Routes.formulesPath(formule.id));
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(
            color: style.color.withOpacity(0.22),
            blurRadius: 16, offset: const Offset(0, 8))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(fit: StackFit.expand, children: [
            formule.imageUrl.startsWith('http')
                ? Image.network(
                    formule.imageUrl,
                    fit: BoxFit.cover,
                    frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                      if (wasSynchronouslyLoaded) return child;
                      return AnimatedOpacity(
                        opacity: frame == null ? 0 : 1,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                        child: child,
                      );
                    },
                    errorBuilder: (_, __, ___) =>
                        Container(color: style.color.withOpacity(0.18)),
                  )
                : Container(color: style.color.withOpacity(0.18)),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.78)],
                  stops: const [0.3, 1],
                ),
              ),
            ),
            Positioned(
              top: sw * 0.03, left: sw * 0.03,
              child: Container(
                width: sw * 0.09, height: sw * 0.09,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.94),
                  shape: BoxShape.circle),
                child: Center(
                  child: Text(style.emoji, style: TextStyle(fontSize: sw * 0.045)),
                ),
              ),
            ),
            Positioned(
              left: sw * 0.035, right: sw * 0.035, bottom: sw * 0.035,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(formule.title,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: sw * 0.036,
                      fontWeight: FontWeight.w800,
                      color: Colors.white),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  SizedBox(height: sw * 0.006),
                  Text(style.tagline,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: sw * 0.025,
                      color: Colors.white.withOpacity(0.85)),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  SizedBox(height: sw * 0.022),
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: sw * 0.024, vertical: sw * 0.01),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20)),
                    child: Text('Découvrir →',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: sw * 0.023,
                        fontWeight: FontWeight.w700,
                        color: style.color)),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _FormuleSkeleton extends StatelessWidget {
  final double sw;
  const _FormuleSkeleton({required this.sw});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.primaryLight.withOpacity(0.18),
      borderRadius: BorderRadius.circular(20),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  SECTION TITLE  (catégories)
// ─────────────────────────────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final double sw;
  final int count;
  const _SectionTitle({required this.sw, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(sw * 0.05, sw * 0.07, sw * 0.05, sw * 0.03),
      child: Row(children: [
        Container(
          width: 3, height: 18,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(4)),
        ),
        SizedBox(width: sw * 0.025),
        Expanded(
          child: Text(
            AppLocaleService.isRtl ? 'جميع الأقسام' : 'Toutes les catégories',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: sw * 0.042,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(
              horizontal: sw * 0.025, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.primaryLight.withOpacity(0.25),
            borderRadius: BorderRadius.circular(20)),
          child: Text(
            '$count ${context.tr('categories_title')}',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: sw * 0.027,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryDark,
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  CATEGORY CARD  (with live product count from Firestore)
// ─────────────────────────────────────────────────────────────────────────────
class _CategoryCard extends StatefulWidget {
  final _CatMeta meta;
  final double   sw;
  final VoidCallback onTap;
  const _CategoryCard({required this.meta, required this.sw, required this.onTap});
  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;
  late final Future<int> _countFuture;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 100),
      lowerBound: 0.0, upperBound: 0.03);
    // ⚡ Calculé une seule fois par carte (au lieu d'à chaque rebuild).
    // ⚠️ On ne filtre QUE par 'category' dans la requête, puis on compte
    // localement les produits `isAvailable` (via le modèle, qui traite
    // l'absence du champ comme `true`). Un `.where('isAvailable', isEqualTo: true)`
    // côté Firestore exclurait silencieusement tout produit sans ce champ,
    // ce qui donnait un compteur à 0 (et des produits invisibles côté détail).
    _countFuture = FirebaseFirestore.instance
        .collection('products')
        .where('category', isEqualTo: widget.meta.id)
        .get()
        .then((snap) => snap.docs
            .map((d) => FarmProduct.fromDoc(d))
            .where((p) => p.isAvailable)
            .length);
  }

  @override
  void dispose() { _press.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final m  = widget.meta;
    final sw = widget.sw;

    return GestureDetector(
      onTapDown:   (_) => _press.forward(),
      onTapUp:     (_) { _press.reverse(); widget.onTap(); },
      onTapCancel: ()  => _press.reverse(),
      child: AnimatedBuilder(
        animation: _press,
        builder: (_, child) =>
            Transform.scale(scale: 1.0 - _press.value, child: child),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: m.color.withOpacity(0.06)),
            boxShadow: [BoxShadow(
              color: m.color.withOpacity(0.10),
              blurRadius: 20, spreadRadius: 0,
              offset: const Offset(0, 8))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Emoji zone ──
              Expanded(
                flex: 5,
                child: Container(
                  decoration: BoxDecoration(
                    color: m.colorLight,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20))),
                  child: Stack(children: [
                    Positioned(right: -sw * 0.04, bottom: -sw * 0.04,
                      child: Container(
                        width: sw * 0.22, height: sw * 0.22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: m.color.withOpacity(0.1)))),
                    // Live count badge
                    Positioned(top: sw * 0.02, left: sw * 0.02,
                      child: FutureBuilder<int>(
                        future: _countFuture,
                        builder: (_, snap) {
                          final count = snap.data ?? 0;
                          return Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: sw * 0.018, vertical: 2),
                            decoration: BoxDecoration(
                              color: m.color,
                              borderRadius: BorderRadius.circular(20)),
                            child: Text('$count',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: sw * 0.022,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                          );
                        },
                      ),
                    ),
                    Center(child: Text(m.emoji,
                        style: TextStyle(fontSize: sw * 0.13))),
                  ]),
                ),
              ),
              // ── Info zone ──
              Expanded(
                flex: 4,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      sw * 0.03, sw * 0.02, sw * 0.03, sw * 0.025),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.localizedName(context),
                        style: TextStyle(
                          fontFamily: 'Cairo', fontSize: sw * 0.034,
                          fontWeight: FontWeight.w800, color: m.color),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                      SizedBox(height: sw * 0.005),
                      Text(
                        m.localizedSubtitle(context),
                        style: TextStyle(
                          fontFamily: 'Cairo', fontSize: sw * 0.026,
                          color: AppColors.textLight),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                      const Spacer(),
                      Wrap(spacing: 3, runSpacing: 3,
                        children: m.subFilters.skip(1).take(2).map((tag) =>
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: sw * 0.014, vertical: 2),
                            decoration: BoxDecoration(
                              color: m.color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6)),
                            child: Text(tag,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: sw * 0.021,
                                fontWeight: FontWeight.w700,
                                color: m.color)),
                          )).toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  CATEGORY DETAIL SCREEN  — Firestore-powered
// ─────────────────────────────────────────────────────────────────────────────
class CategoryDetailScreen extends StatefulWidget {
  final _CatMeta meta;
  const CategoryDetailScreen({super.key, required this.meta});
  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  String _activeFilter = 'Tout';

  /// ⚠️ On ne filtre QUE par 'category' côté Firestore (requête simple, sans
  /// index composite requis). Les filtres suivants sont volontairement
  /// appliqués côté client dans `_applyLocalFilter` :
  ///  - `isAvailable` : un `.where('isAvailable', isEqualTo: true)` exclurait
  ///    silencieusement tout produit où ce champ n'existe pas dans Firestore.
  ///  - le tri par date : un `.orderBy('createdAt')` exclut lui aussi tout
  ///    document sans ce champ — c'était la cause principale des produits
  ///    qui n'apparaissaient pas du tout.
  ///  - 'Best Seller' : le champ `product placement` contenait parfois des
  ///    variations de casse/espaces ("best seller ", "Best Seller"...), donc
  ///    on le compare via `isBestSeller` (comparaison insensible à la casse).
  Stream<QuerySnapshot> _buildStream() {
    return FirebaseFirestore.instance
        .collection('products')
        .where('category', isEqualTo: widget.meta.id)
        .snapshots();
  }

  List<FarmProduct> _applyLocalFilter(List<FarmProduct> all) {
    Iterable<FarmProduct> list = all.where((p) => p.isAvailable);

    switch (_activeFilter) {
      case 'Tout':
        break;
      case 'Best Seller':
        list = list.where((p) => p.isBestSeller);
        break;
      default:
        final kw = _activeFilter.toLowerCase();
        list = list.where((p) =>
          p.name.toLowerCase().contains(kw) ||
          p.description.toLowerCase().contains(kw) ||
          p.placement.toLowerCase().contains(kw));
    }
    final result = list.toList();
    // Tri côté client : les plus récents en premier, ceux sans date à la fin.
    result.sort((a, b) {
      if (a.createdAt == null && b.createdAt == null) return 0;
      if (a.createdAt == null) return 1;
      if (b.createdAt == null) return -1;
      return b.createdAt!.compareTo(a.createdAt!);
    });
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final m  = widget.meta;
    final sw = MediaQuery.of(context).size.width;
    // Même principe que sur l'écran des catégories : on plafonne la
    // référence de taille pour éviter des cartes/textes géants sur desktop,
    // tout en laissant `sw` piloter le nombre de colonnes de la grille.
    final rw = sw > 480 ? 480.0 : sw;
    final crossCount = sw >= 900 ? 4 : (sw >= 600 ? 3 : 2);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: rw * 0.38,
            collapsedHeight: kToolbarHeight,
            pinned: true,
            backgroundColor: m.color,
            elevation: 0,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white, size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: _DetailHeader(meta: m, sw: rw)),
          ),

          SliverPersistentHeader(
            pinned: true,
            delegate: _FilterDelegate(
              filters: m.subFilters,
              active:  _activeFilter,
              color:   m.color,
              onSelect: (f) => setState(() => _activeFilter = f),
              sw: rw,
            ),
          ),

          StreamBuilder<QuerySnapshot>(
            stream: _buildStream(),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator(
                      color: m.color)),
                );
              }
              if (snap.hasError) {
                return SliverFillRemaining(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: rw * 0.18, height: rw * 0.18,
                            decoration: BoxDecoration(
                              color: AppColors.error.withOpacity(0.1),
                              shape: BoxShape.circle),
                            child: Icon(Icons.wifi_off_rounded,
                                color: AppColors.error, size: rw * 0.09),
                          ),
                          SizedBox(height: rw * 0.03),
                          Text('Erreur de chargement',
                              style: TextStyle(
                                fontFamily: 'Cairo', fontWeight: FontWeight.w700,
                                fontSize: rw * 0.036,
                                color: AppColors.textPrimary)),
                          SizedBox(height: rw * 0.01),
                          Text('${snap.error}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Cairo', fontSize: rw * 0.028,
                                color: AppColors.textLight)),
                        ],
                      ),
                    ),
                  ),
                );
              }

              final rawDocs = snap.data?.docs ?? [];
              final allProducts = rawDocs
                  .map((d) => FarmProduct.fromDoc(d))
                  .toList();
              final products = _applyLocalFilter(allProducts);

              final countRow = SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      rw * 0.05, rw * 0.04, rw * 0.05, rw * 0.02),
                  child: Row(children: [
                    Text(
                      '${products.length} produit${products.length > 1 ? 's' : ''}',
                      style: TextStyle(
                        fontFamily: 'Cairo', fontSize: rw * 0.032,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textLight)),
                  ]),
                ),
              );

              if (products.isEmpty) {
                return SliverFillRemaining(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: rw * 0.24, height: rw * 0.24,
                        decoration: BoxDecoration(
                          color: m.colorLight, shape: BoxShape.circle),
                        child: Center(
                          child: Text('🔍', style: TextStyle(fontSize: rw * 0.1))),
                      ),
                      SizedBox(height: rw * 0.04),
                      Text('Aucun produit dans cette catégorie',
                        style: TextStyle(
                          fontFamily: 'Cairo', fontSize: rw * 0.038,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                      SizedBox(height: rw * 0.012),
                      Text('Revenez bientôt, de nouveaux produits arrivent 🌱',
                        style: TextStyle(
                          fontFamily: 'Cairo', fontSize: rw * 0.028,
                          color: AppColors.textLight)),
                    ],
                  ),
                );
              }

              return SliverMainAxisGroup(slivers: [
                countRow,
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                      rw * 0.04, 0, rw * 0.04, rw * 0.28),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount:   crossCount,
                      mainAxisSpacing:  rw * 0.03,
                      crossAxisSpacing: rw * 0.03,
                      childAspectRatio: 0.7,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _ProductCard(
                          product: products[i], meta: m, sw: rw),
                      childCount: products.length,
                    ),
                  ),
                ),
              ]);
            },
          ),
        ],
          ),
        ),
      ),
    );
  }
}

// ── Detail header ─────────────────────────────────────────────────────────────
class _DetailHeader extends StatelessWidget {
  final _CatMeta meta;
  final double   sw;
  const _DetailHeader({required this.meta, required this.sw});

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [meta.color.withOpacity(0.82), meta.color]))),
      Positioned(top: -sw * 0.08, right: -sw * 0.08,
          child: _Blob(size: sw * 0.44, opacity: 0.1)),
      Positioned(bottom: sw * 0.03, left: sw * 0.02,
          child: _Blob(size: sw * 0.2, opacity: 0.08)),
      Positioned(right: sw * 0.05, bottom: sw * 0.04,
        child: Text(meta.emoji,
            style: TextStyle(fontSize: sw * 0.2))),
      SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              sw * 0.05, kToolbarHeight + 4, sw * 0.32, sw * 0.04),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(meta.name,
                style: TextStyle(
                  fontFamily: 'Cairo', fontSize: sw * 0.062,
                  fontWeight: FontWeight.w800, color: Colors.white)),
              Text(meta.subtitle,
                style: TextStyle(
                  fontFamily: 'Cairo', fontSize: sw * 0.031,
                  color: Colors.white.withOpacity(0.78))),
            ],
          ),
        ),
      ),
    ]);
  }
}

// ── Pinned filter row ─────────────────────────────────────────────────────────
class _FilterDelegate extends SliverPersistentHeaderDelegate {
  final List<String>        filters;
  final String              active;
  final Color               color;
  final ValueChanged<String> onSelect;
  final double              sw;

  _FilterDelegate({
    required this.filters, required this.active,
    required this.color,   required this.onSelect,
    required this.sw,
  });

  @override double get minExtent => 52;
  @override double get maxExtent => 52;
  @override bool shouldRebuild(_FilterDelegate o) =>
      o.active != active || o.filters != filters;

  @override
  Widget build(BuildContext ctx, double shrink, bool overlaps) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: overlaps
            ? [BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8, offset: const Offset(0, 2))]
            : null,
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
            horizontal: sw * 0.04, vertical: sw * 0.018),
        itemCount: filters.length,
        separatorBuilder: (_, __) => SizedBox(width: sw * 0.02),
        itemBuilder: (_, i) {
          final f  = filters[i];
          final sel = f == active;
          return GestureDetector(
            onTap: () => onSelect(f),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(
                  horizontal: sw * 0.038, vertical: 4),
              decoration: BoxDecoration(
                color: sel ? color : color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: sel ? color : color.withOpacity(0.2))),
              child: Text(f,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: sw * 0.029,
                  fontWeight: FontWeight.w700,
                  color: sel ? Colors.white : color)),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PRODUCT CARD  (Firestore data) — tap → fiche produit
// ─────────────────────────────────────────────────────────────────────────────
class _ProductCard extends StatefulWidget {
  final FarmProduct product;
  final _CatMeta    meta;
  final double      sw;
  const _ProductCard({
    required this.product, required this.meta, required this.sw});
  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  bool _inCart = false;
  bool _fav    = false;

  void _openProduct() {
    HapticFeedback.selectionClick();
    context.push(Routes.productPath(widget.product.id));
  }

  @override
  Widget build(BuildContext context) {
    final p   = widget.product;
    final col = widget.meta.color;
    final bg  = widget.meta.colorLight;
    final sw  = widget.sw;

    return GestureDetector(
      onTap: _openProduct,
      child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: col.withOpacity(0.05)),
        boxShadow: [BoxShadow(
          color: col.withOpacity(0.08),
          blurRadius: 16, spreadRadius: 0,
          offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Image / emoji zone ──
          Stack(children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18)),
              child: Container(
                height: sw * 0.28,
                width: double.infinity,
                color: bg,
                child: p.imageUrl.startsWith('http')
                    ? Image.network(
                        p.imageUrl,
                        fit: BoxFit.cover,
                        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                          if (wasSynchronouslyLoaded) return child;
                          return AnimatedOpacity(
                            opacity: frame == null ? 0 : 1,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                            child: child,
                          );
                        },
                        errorBuilder: (_, __, ___) => Center(
                          child: Text(widget.meta.emoji,
                              style: TextStyle(fontSize: sw * 0.12))),
                      )
                    : Center(child: Text(widget.meta.emoji,
                        style: TextStyle(fontSize: sw * 0.12))),
              ),
            ),

            // Promo badge — botanical/natural style with leaf accent + %
            if (p.isPromo)
              Positioned(
                top: sw * 0.02,
                left: sw * 0.02,
                child: Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: sw * 0.018, vertical: sw * 0.008),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2E7D32).withOpacity(0.35),
                        blurRadius: 6, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('🌿',
                        style: TextStyle(fontSize: sw * 0.022)),
                      SizedBox(width: sw * 0.008),
                      Text('-${p.discountPct}%',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: sw * 0.022,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.3)),
                    ],
                  ),
                ),
              ),

            // Fav button
            Positioned(top: sw * 0.015, right: sw * 0.015,
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _fav = !_fav);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: sw * 0.073, height: sw * 0.073,
                  decoration: BoxDecoration(
                    color: _fav
                        ? const Color(0xFFE91E63).withOpacity(0.15)
                        : Colors.white.withOpacity(0.92),
                    shape: BoxShape.circle),
                  child: Icon(
                    _fav ? Icons.favorite_rounded
                         : Icons.favorite_border_rounded,
                    size: sw * 0.036,
                    color: _fav ? const Color(0xFFE91E63)
                                : AppColors.textLight),
                ),
              ),
            ),
          ]),

          // ── Info ──
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  sw * 0.025, sw * 0.016, sw * 0.025, sw * 0.016),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: sw * 0.032,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (p.description.isNotEmpty) ...[
                    SizedBox(height: sw * 0.005),
                    Text(p.description,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: sw * 0.024,
                        color: AppColors.textLight),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                  const Spacer(),
                  if (p.stock <= 10)
                    Text('⚠ ${p.stock} restants',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: sw * 0.022,
                        color: AppColors.error,
                        fontWeight: FontWeight.w600)),
                  SizedBox(height: sw * 0.008),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${_fmtPrice(p.price)} MAD',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: sw * 0.036,
                              fontWeight: FontWeight.w800,
                              color: col)),
                          Row(children: [
                            if (p.oldPrice != null) ...[
                              Text('${_fmtPrice(p.oldPrice!)} MAD',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: sw * 0.022,
                                  color: AppColors.textLight,
                                  decoration: TextDecoration.lineThrough)),
                              SizedBox(width: sw * 0.01),
                            ],
                            Text('/ ${p.unit}',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: sw * 0.022,
                                color: AppColors.textLight)),
                          ]),
                        ],
                      )),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() => _inCart = !_inCart);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: sw * 0.088, height: sw * 0.088,
                          decoration: BoxDecoration(
                            color: _inCart ? col : col.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10)),
                          child: Icon(
                            _inCart ? Icons.check_rounded : Icons.add_rounded,
                            color: _inCart ? Colors.white : col,
                            size: sw * 0.046),
                        ),
                      ),
                    ],
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