import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../routes/app_routes.dart';
import '../categories/categories_screen.dart' show FarmProduct;

/// Parse robuste : certains champs (formPrice, price, stock...) peuvent être
/// stockés côté Firestore comme String ("450") au lieu d'un number.
/// N'échoue jamais.
num _parseNum(dynamic value, [num fallback = 0]) {
  if (value == null) return fallback;
  if (value is num) return value;
  if (value is String) {
    return num.tryParse(value.trim().replaceAll(',', '.')) ?? fallback;
  }
  return fallback;
}

/// Lit une URL d'image en acceptant plusieurs variantes de casse
/// (imageURL, imageUrl, imageurl...) car les documents Firestore ne sont
/// pas toujours homogènes.
String _readImageUrl(Map<String, dynamic> d) {
  for (final key in const ['imageURL', 'imageUrl', 'imageurl', 'image_url']) {
    final v = d[key];
    if (v is String && v.isNotEmpty) return v;
  }
  return '';
}

// ─────────────────────────────────────────────────────────────────────────────
//  ORDRE FIXE DES FORMULES
//  ⚠️ Ces ID correspondent exactement aux noms de documents Firestore que tu
//  as créés (collection "formules"). On identifie chaque formule par son ID
//  plutôt que par sa position dans la query, pour ne jamais en perdre une —
//  même si son "productIDs" est encore vide/incomplet pendant que tu le remplis.
// ─────────────────────────────────────────────────────────────────────────────
const List<String> kFormuleDocOrder = [
  'formulesBeldi',
  'formulesHealthy',
  'formulesSaison',
];

// ─────────────────────────────────────────────────────────────────────────────
//  FORMULE MODEL  (collection Firestore "formules")
//  Champs attendus : title, imageURL, description, formPrice, productIDs (array)
// ─────────────────────────────────────────────────────────────────────────────
class FormuleFull {
  final String       id; // ex: formulesBeldi
  final String       title;
  final String       imageUrl;
  final String       description;
  final num          formPrice;
  final List<String> productIDs;

  const FormuleFull({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.description,
    required this.formPrice,
    required this.productIDs,
  });

  factory FormuleFull.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return FormuleFull(
      id:          doc.id,
      title:       d['title']       as String? ?? '',
      imageUrl:    _readImageUrl(d),
      description: d['description'] as String? ?? '',
      formPrice:   _parseNum(d['formPrice']),
      productIDs: (d['productIDs'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

/// Habillage visuel + accroche marketing par formule.
/// Palette pensée pour évoquer une sensation différente à chaque fois :
///  • Beldi     → authenticité, terroir (tons terre cuite / bois brûlé)
///  • Healthy   → santé, vitalité (verts frais, énergiques)
///  • Saison    → rareté, valeur (bordeaux profond + touche or, esprit "édition limitée")
class _FormuleVisualStyle {
  final List<Color> gradient;   // dégradé principal (header, CTA, onglet actif)
  final Color        accent;     // couleur pleine (badges, numéros, checkbox)
  final String        emoji;
  final String        badge;     // accroche courte type "100% Terroir"
  final String        headline;
  final String        subheadline;

  const _FormuleVisualStyle({
    required this.gradient,
    required this.accent,
    required this.emoji,
    required this.badge,
    required this.headline,
    required this.subheadline,
  });

  /// Alias pratique pour le code existant qui veut une seule couleur.
  Color get color => accent;
}

_FormuleVisualStyle _styleForFormule(FormuleFull f) {
  final id = f.id.toLowerCase();
  final t  = f.title.toLowerCase();
  bool match(String needle) => id.contains(needle) || t.contains(needle);

  if (match('beldi')) {
    return const _FormuleVisualStyle(
      gradient: [Color(0xFF5C3A21), Color(0xFFB5651D)],
      accent:   Color(0xFF8B4513),
      emoji:    '🌾',
      badge:    '100% Terroir',
      headline: 'Beldi : goûtez à l\'authentique',
      subheadline: 'Des produits du terroir, cultivés comme autrefois.',
    );
  }
  if (match('healthy') || match('sain') || match('sahi') || match('helthy')) {
    return const _FormuleVisualStyle(
      gradient: [Color(0xFF1B5E20), Color(0xFF66BB6A)],
      accent:   Color(0xFF2E7D32),
      emoji:    '🥗',
      badge:    'Boost Santé',
      headline: 'Sain : investissez dans votre santé',
      subheadline: 'Une sélection équilibrée pour prendre soin de vous.',
    );
  }
  if (match('saison')) {
    return const _FormuleVisualStyle(
      gradient: [Color(0xFF5C1A33), Color(0xFFC9A227)],
      accent:   Color(0xFF7B1E3D),
      emoji:    '🍂',
      badge:    'Édition Limitée',
      headline: 'Saisonnier : une opportunité à ne pas manquer',
      subheadline: 'Ces produits de saison ne sont pas toujours disponibles.',
    );
  }
  return const _FormuleVisualStyle(
    gradient: [Color(0xFF2F3E32), Color(0xFF6B8F71)],
    accent:   AppColors.primaryDark,
    emoji:    '🌿',
    badge:    'Notre sélection',
    headline: 'Notre sélection du moment',
    subheadline: 'Une formule pensée pour vous.',
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  FORMULES SCREEN — onglets Beldi / Sain / Saisonnier
// ─────────────────────────────────────────────────────────────────────────────
class FormulesScreen extends StatefulWidget {
  /// Titre (ou fragment de titre / ID) de la formule à ouvrir en premier.
  /// Provient de Routes.formulesPath(...) → ex: "Beldi".
  final String initialFormule;
  const FormulesScreen({super.key, required this.initialFormule});

  @override
  State<FormulesScreen> createState() => _FormulesScreenState();
}

class _FormulesScreenState extends State<FormulesScreen> {
  PageController? _pageController; // créé une seule fois, avec le bon initialPage
  int  _activeIndex   = 0;
  bool _indexResolved = false;

  // ─────────────────────────────────────────────────────────────────────────
  //  ⚠️ FIX PRINCIPAL DU BUG "le contenu reste bloqué sur Beldi" :
  //  Avant, `FirebaseFirestore.instance.collection('formules').snapshots()`
  //  était appelé DIRECTEMENT dans `build()`. Cela crée un NOUVEL objet
  //  Stream à chaque rebuild (par ex. juste après avoir tapé sur un onglet,
  //  via `setState` dans `_goToPage`).
  //
  //  Le `StreamBuilder` compare l'identité du Stream reçu : comme ce n'est
  //  jamais le même objet, il se désabonne de l'ancien flux et se
  //  réabonne au nouveau, en repassant brièvement par
  //  `ConnectionState.waiting`. Pendant ce court instant, tout le sous-arbre
  //  (dont le `PageView`) est démonté puis reconstruit, et le `PageController`
  //  perd sa position de scroll interne. Quand il se rattache au nouveau
  //  `PageView`, Flutter réutilise `initialPage`, qui avait été figé UNE
  //  SEULE FOIS lors de la toute première construction du controller
  //  (donc l'index 0 = Beldi) — même si `_activeIndex` a bien changé entre
  //  temps. Résultat : l'onglet sélectionné change visuellement (il lit
  //  `_activeIndex` directement), mais le contenu affiché revient toujours
  //  à la formule 0.
  //
  //  Le fix : créer le Stream UNE SEULE FOIS (mémorisé dans le State),
  //  pour que son identité reste stable entre les rebuilds.
  // ─────────────────────────────────────────────────────────────────────────
  late final Stream<QuerySnapshot> _formulesStream =
      FirebaseFirestore.instance.collection('formules').snapshots();

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  void _resolveInitialIndex(List<FormuleFull> formules) {
    if (_indexResolved) return;
    final q = widget.initialFormule.trim().toLowerCase();
    if (q.isNotEmpty) {
      // 1) Correspondance EXACTE sur l'ID du document (cas fiable — c'est ce
      //    que la page catégories envoie désormais).
      int idx = formules.indexWhere((f) => f.id.toLowerCase() == q);
      // 2) Correspondance exacte sur le titre.
      if (idx < 0) {
        idx = formules.indexWhere((f) => f.title.trim().toLowerCase() == q);
      }
      // 3) Repli : correspondance partielle (dernier recours).
      if (idx < 0) {
        idx = formules.indexWhere((f) =>
            f.id.toLowerCase().contains(q) || f.title.toLowerCase().contains(q));
      }
      if (idx >= 0) _activeIndex = idx;
    }
    _indexResolved = true;
  }

  void _goToPage(int index) {
    HapticFeedback.selectionClick();
    setState(() => _activeIndex = index);
    _pageController?.animateToPage(index,
        duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.black.withOpacity(0.06),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary, size: 18),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('Nos Formules',
            style: TextStyle(
                fontFamily: 'Cairo',
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        // ✅ FIX : on utilise le Stream mémorisé (identité stable), plus
        // un `.snapshots()` recréé à chaque build.
        stream: _formulesStream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          if (snap.hasError) {
            return Center(
              child: Text('Erreur de chargement des formules',
                  style: TextStyle(fontFamily: 'Cairo', color: AppColors.textLight)),
            );
          }

          // On indexe les documents reçus par leur ID, puis on reconstruit
          // la liste dans l'ORDRE FIXE défini plus haut. Aucune formule ne
          // peut ainsi "disparaître" à cause de l'ordre par défaut de
          // Firestore ou d'une donnée encore incomplète.
          final byId = <String, DocumentSnapshot>{
            for (final d in (snap.data?.docs ?? [])) d.id: d,
          };
          final formules = kFormuleDocOrder
              .where((id) => byId.containsKey(id))
              .map((id) => FormuleFull.fromDoc(byId[id]!))
              .toList();

          if (formules.isEmpty) {
            return Center(
              child: Text('Aucune formule disponible pour le moment',
                  style: TextStyle(fontFamily: 'Cairo', color: AppColors.textLight)),
            );
          }

          _resolveInitialIndex(formules);
          if (_activeIndex >= formules.length) _activeIndex = 0;

          // Le PageController est créé UNE SEULE FOIS, directement avec
          // initialPage: _activeIndex — plus de "jumpToPage" fragile après
          // le premier frame qui pouvait échouer silencieusement.
          _pageController ??= PageController(initialPage: _activeIndex);

          return Column(
            children: [
              _FormuleTabBar(
                formules: formules,
                activeIndex: _activeIndex,
                onSelect: _goToPage,
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (i) => setState(() => _activeIndex = i),
                  children: formules
                      .map((f) => _FormuleDetailView(key: ValueKey(f.id), formule: f))
                      .toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  BARRE D'ONGLETS FIXE — "vous êtes dans Beldi", 1 clic pour changer
// ─────────────────────────────────────────────────────────────────────────────
class _FormuleTabBar extends StatelessWidget {
  final List<FormuleFull>  formules;
  final int                activeIndex;
  final ValueChanged<int>  onSelect;
  const _FormuleTabBar({
    required this.formules,
    required this.activeIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    return Container(
      padding: EdgeInsets.fromLTRB(sw * 0.035, sw * 0.01, sw * 0.035, sw * 0.032),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.black.withOpacity(0.05)),
        ),
      ),
      child: Row(
        children: List.generate(formules.length, (i) {
          final f     = formules[i];
          final style = _styleForFormule(f);
          final sel   = i == activeIndex;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: sw * 0.012),
              child: GestureDetector(
                onTap: () => onSelect(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: EdgeInsets.symmetric(vertical: sw * 0.024),
                  decoration: BoxDecoration(
                    // Chaque bouton porte SA couleur en permanence — actif =
                    // couleur pleine, inactif = teinte douce de la même
                    // couleur. Aucun bouton n'est jamais "neutre".
                    color: sel ? style.accent : style.accent.withOpacity(0.09),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: sel ? style.accent : style.accent.withOpacity(0.22)),
                    boxShadow: sel
                        ? [BoxShadow(
                            color: style.accent.withOpacity(0.28),
                            blurRadius: 10, offset: const Offset(0, 4))]
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(style.emoji, style: TextStyle(fontSize: sw * 0.05)),
                      SizedBox(height: sw * 0.008),
                      Text(
                        f.title.isNotEmpty ? f.title : style.headline,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: sw * 0.027,
                          fontWeight: FontWeight.w800,
                          color: sel ? Colors.white : style.accent),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  CONTENU D'UNE FORMULE  (header + prix + produits + CTA sticky)
// ─────────────────────────────────────────────────────────────────────────────
class _FormuleDetailView extends StatefulWidget {
  final FormuleFull formule;
  const _FormuleDetailView({super.key, required this.formule});

  @override
  State<_FormuleDetailView> createState() => _FormuleDetailViewState();
}

class _FormuleDetailViewState extends State<_FormuleDetailView> {
  final Map<String, bool> _checked = {};
  final Set<String> _manuallyRemoved = {}; // produits retirés PAR CHOIX (max 2)
  bool _stockAlertShown = false;
  bool _adding = false;

  static const int kMaxManualRemovals = 2;

  // Future mis en cache une seule fois par instance de State (donc par
  // formule, grâce à ValueKey(f.id) sur le widget parent), au lieu d'être
  // recréé à chaque build().
  late Future<List<DocumentSnapshot>> _productsFuture;
  List<String> _loadedProductIDs = const [];

  @override
  void initState() {
    super.initState();
    _loadedProductIDs = widget.formule.productIDs;
    _productsFuture = _fetchProducts(_loadedProductIDs);
  }

  @override
  void didUpdateWidget(covariant _FormuleDetailView old) {
    super.didUpdateWidget(old);
    // On ne relance la requête QUE si la liste productIDs a réellement
    // changé (comparaison de contenu, pas juste de référence).
    if (!_sameIds(old.formule.productIDs, widget.formule.productIDs)) {
      _loadedProductIDs = widget.formule.productIDs;
      _productsFuture = _fetchProducts(_loadedProductIDs);
      _checked.clear();
      _manuallyRemoved.clear();
      _stockAlertShown = false;
    }
  }

  bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<List<DocumentSnapshot>> _fetchProducts(List<String> ids) {
    return Future.wait(
      ids.map((id) => FirebaseFirestore.instance.collection('products').doc(id).get()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sw    = MediaQuery.of(context).size.width;
    final style = _styleForFormule(widget.formule);

    return FutureBuilder<List<DocumentSnapshot>>(
      future: _productsFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: style.accent));
        }
        if (snap.hasError) {
          return Center(
            child: Text('Erreur de chargement des produits',
                style: TextStyle(fontFamily: 'Cairo', color: AppColors.textLight)),
          );
        }

        final docs = (snap.data ?? []).where((d) => d.exists).toList();
        final products = docs.map((d) => FarmProduct.fromDoc(d)).toList();

        if (products.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(sw * 0.08),
              child: Text(
                'Cette formule est en cours de préparation, revenez bientôt !',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Cairo', color: AppColors.textLight)),
            ),
          );
        }

        // Initialise la sélection : cochée par défaut, décochée si rupture.
        for (final p in products) {
          _checked.putIfAbsent(p.id, () => p.isAvailable && p.stock > 0);
        }

        final unavailable =
            products.where((p) => !(p.isAvailable && p.stock > 0)).toList();
        if (unavailable.isNotEmpty && !_stockAlertShown) {
          _stockAlertShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.error,
              content: Text(
                unavailable.length == 1
                    ? '${unavailable.first.name} est en rupture de stock, retiré de la formule.'
                    : '${unavailable.length} produits sont en rupture de stock et ont été retirés.',
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
            ));
          });
        }

        // ── Calcul des prix ──
        final oldPriceSum = products.fold<num>(0, (s, p) => s + p.price);
        final discountRatio = oldPriceSum > 0
            ? (widget.formule.formPrice / oldPriceSum).clamp(0, 1)
            : 1.0;

        final selectedOriginalSum = products
            .where((p) => _checked[p.id] == true)
            .fold<num>(0, (s, p) => s + p.price);
        final currentTotal   = selectedOriginalSum * discountRatio;
        final currentSavings = selectedOriginalSum - currentTotal;
        final selectedCount  = products.where((p) => _checked[p.id] == true).length;

        return Stack(children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _FormuleHeader(formule: widget.formule, style: style, sw: sw)),
              SliverToBoxAdapter(
                child: _PriceAnchor(
                  oldPrice: oldPriceSum,
                  newPrice: currentTotal,
                  savings: currentSavings,
                  style: style, sw: sw,
                ),
              ),
              SliverToBoxAdapter(
                child: _ProductsChain(
                  products: products,
                  checked: _checked,
                  style: style,
                  sw: sw,
                  removalsLeft: kMaxManualRemovals - _manuallyRemoved.length,
                  onToggle: (p, v) => _handleToggle(context, p, v),
                ),
              ),
              SliverToBoxAdapter(child: SizedBox(height: sw * 0.34)),
            ],
          ),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: _StickyCTA(
              style: style, sw: sw,
              savings: currentSavings,
              total: currentTotal,
              selectedCount: selectedCount,
              enabled: selectedCount > 0 && !_adding,
              loading: _adding,
              onBuy: () => _addBundleToCart(
                  context, products, currentTotal, oldPriceSum),
            ),
          ),
        ]);
      },
    );
  }

  void _handleToggle(BuildContext context, FarmProduct p, bool wantChecked) {
    final available = p.isAvailable && p.stock > 0;
    if (!available) return; // produit en rupture : non modifiable

    if (!wantChecked) {
      if (_manuallyRemoved.length >= kMaxManualRemovals &&
          !_manuallyRemoved.contains(p.id)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.warning,
          content: const Text(
            'Vous pouvez retirer au maximum 2 produits de cette formule.',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
        ));
        return;
      }
      setState(() {
        _checked[p.id] = false;
        _manuallyRemoved.add(p.id);
      });
    } else {
      setState(() {
        _checked[p.id] = true;
        _manuallyRemoved.remove(p.id);
      });
    }
  }

  Future<void> _addBundleToCart(
    BuildContext context,
    List<FarmProduct> products,
    num currentTotal,
    num oldPriceSum,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      context.push(
          '${Routes.login}?from=${Uri.encodeComponent(Routes.formulesPath(widget.formule.title))}');
      return;
    }

    setState(() => _adding = true);
    try {
      final includedIds = products
          .where((p) => _checked[p.id] == true)
          .map((p) => p.id)
          .toList();
      final removedIds = products
          .where((p) => _checked[p.id] != true)
          .map((p) => p.id)
          .toList();

      // ─────────────────────────────────────────────────────────────────
      // Structure préparée pour la page panier (à finaliser plus tard).
      // La formule est ajoutée comme UN SEUL article, avec
      // `type: 'formule'` pour que la page panier sache l'afficher
      // différemment.
      // ─────────────────────────────────────────────────────────────────
      await FirebaseFirestore.instance
          .collection('carts')
          .doc(user.uid)
          .collection('items')
          .doc(widget.formule.id)
          .set({
        'type': 'formule',
        'formuleId': widget.formule.id,
        'formuleTitle': widget.formule.title,
        'formuleImageUrl': widget.formule.imageUrl,
        'unitPrice': currentTotal,
        'originalPrice': oldPriceSum,
        'includedProductIds': includedIds,
        'removedProductIds': removedIds,
        'quantity': FieldValue.increment(1),
        'addedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _styleForFormule(widget.formule).accent,
        content: const Text('Formule ajoutée au panier 🛒',
            style: TextStyle(fontFamily: 'Cairo')),
      ));
      context.go(Routes.cart);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: AppColors.error,
        content: Text('Erreur : impossible d\'ajouter au panier',
            style: TextStyle(fontFamily: 'Cairo')),
      ));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }
}

// ── Header collage + accroche marketing ─────────────────────────────────────
class _FormuleHeader extends StatelessWidget {
  final FormuleFull formule;
  final _FormuleVisualStyle style;
  final double sw;
  const _FormuleHeader({required this.formule, required this.style, required this.sw});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: sw * 0.42, // -35% par rapport à la version précédente (0.64)
      margin: EdgeInsets.fromLTRB(sw * 0.04, sw * 0.04, sw * 0.04, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(
            color: style.accent.withOpacity(0.3),
            blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(fit: StackFit.expand, children: [
          formule.imageUrl.startsWith('http')
              ? Image.network(formule.imageUrl, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                      decoration: BoxDecoration(
                          gradient: LinearGradient(colors: style.gradient))))
              : Container(
                  decoration: BoxDecoration(
                      gradient: LinearGradient(colors: style.gradient))),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.black.withOpacity(0.1), Colors.black.withOpacity(0.85)],
                stops: const [0.2, 1],
              ),
            ),
          ),
          Positioned(
            left: sw * 0.05, right: sw * 0.05, bottom: sw * 0.05,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: sw * 0.03, vertical: sw * 0.012),
                    decoration: BoxDecoration(
                        color: Colors.white, borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(style.emoji, style: TextStyle(fontSize: sw * 0.04)),
                      SizedBox(width: sw * 0.015),
                      Text(
                        formule.title.isNotEmpty ? formule.title : 'Formule',
                        style: TextStyle(
                          fontFamily: 'Cairo', fontSize: sw * 0.03,
                          fontWeight: FontWeight.w800, color: style.accent)),
                    ]),
                  ),
                  SizedBox(width: sw * 0.02),
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: sw * 0.026, vertical: sw * 0.012),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.4)),
                    ),
                    child: Text(style.badge,
                      style: TextStyle(
                        fontFamily: 'Cairo', fontSize: sw * 0.026,
                        fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ]),
                SizedBox(height: sw * 0.02),
                Text(style.headline,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Cairo', fontSize: sw * 0.046,
                    fontWeight: FontWeight.w800, color: Colors.white, height: 1.15)),
                SizedBox(height: sw * 0.01),
                Text(
                  formule.description.isNotEmpty
                      ? formule.description : style.subheadline,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Cairo', fontSize: sw * 0.028,
                    color: Colors.white.withOpacity(0.88), height: 1.35)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Ancre de prix (prix barré + prix formule + économie) ────────────────────
class _PriceAnchor extends StatelessWidget {
  final num oldPrice, newPrice, savings;
  final _FormuleVisualStyle style;
  final double sw;
  const _PriceAnchor({
    required this.oldPrice, required this.newPrice, required this.savings,
    required this.style, required this.sw,
  });

  @override
  Widget build(BuildContext context) {
    final percent = oldPrice > 0
        ? (((oldPrice - newPrice) / oldPrice) * 100).round().clamp(0, 100)
        : 0;
    return Container(
      margin: EdgeInsets.fromLTRB(sw * 0.04, sw * 0.05, sw * 0.04, 0),
      padding: EdgeInsets.all(sw * 0.045),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: style.accent.withOpacity(0.15)),
        boxShadow: [BoxShadow(
            color: style.accent.withOpacity(0.08),
            blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('${oldPrice.toStringAsFixed(0)} DH',
                  style: TextStyle(
                    fontFamily: 'Cairo', fontSize: sw * 0.036,
                    color: AppColors.error,
                    decoration: TextDecoration.lineThrough,
                    fontWeight: FontWeight.w600)),
                SizedBox(width: sw * 0.02),
                Text('${newPrice.toStringAsFixed(0)} DH',
                  style: TextStyle(
                    fontFamily: 'Cairo', fontSize: sw * 0.056,
                    color: style.accent, fontWeight: FontWeight.w900)),
              ]),
              SizedBox(height: sw * 0.01),
              Text('Vous économisez ${savings.toStringAsFixed(0)} DH !',
                style: TextStyle(
                  fontFamily: 'Cairo', fontSize: sw * 0.03,
                  fontWeight: FontWeight.w700, color: AppColors.primary)),
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: sw * 0.03, vertical: sw * 0.018),
          decoration: BoxDecoration(
              color: style.accent,
              borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            const Icon(Icons.local_offer_rounded, color: Colors.white, size: 22),
            SizedBox(height: sw * 0.006),
            Text('-$percent%',
              style: TextStyle(
                fontFamily: 'Cairo', fontSize: sw * 0.03,
                fontWeight: FontWeight.w800, color: Colors.white)),
          ]),
        ),
      ]),
    );
  }
}

// ── Liste chaînée et numérotée des produits ──────────────────────────────────
class _ProductsChain extends StatelessWidget {
  final List<FarmProduct>            products;
  final Map<String, bool>            checked;
  final _FormuleVisualStyle          style;
  final double                       sw;
  final int                          removalsLeft;
  final void Function(FarmProduct, bool) onToggle;
  const _ProductsChain({
    required this.products, required this.checked, required this.style,
    required this.sw, required this.removalsLeft, required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(sw * 0.04, sw * 0.06, sw * 0.04, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 3, height: 18,
                decoration: BoxDecoration(
                    color: style.accent, borderRadius: BorderRadius.circular(4))),
            SizedBox(width: sw * 0.025),
            Text('Composition de la formule',
              style: TextStyle(
                fontFamily: 'Cairo', fontSize: sw * 0.042,
                fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          ]),
          SizedBox(height: sw * 0.018),
          Text(
            removalsLeft > 0
                ? 'Chaque produit complète les autres. Vous pouvez en retirer jusqu\'à $removalsLeft.'
                : 'Limite de retrait atteinte — décochez un produit pour en retirer un autre.',
            style: TextStyle(
              fontFamily: 'Cairo', fontSize: sw * 0.028, color: AppColors.textLight)),
          SizedBox(height: sw * 0.04),
          ...List.generate(products.length, (i) {
            final p       = products[i];
            final isLast  = i == products.length - 1;
            final avail   = p.isAvailable && p.stock > 0;
            final isCheck = checked[p.id] == true;
            return Column(children: [
              _ProductChainTile(
                index: i + 1, product: p, style: style, sw: sw,
                available: avail, isChecked: isCheck,
                onChanged: (v) => onToggle(p, v),
              ),
              if (!isLast)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: sw * 0.01),
                  child: Row(children: [
                    SizedBox(width: sw * 0.062),
                    Container(width: 2, height: sw * 0.05,
                        color: style.accent.withOpacity(0.25)),
                    SizedBox(width: sw * 0.02),
                    Icon(Icons.keyboard_arrow_down_rounded,
                        color: style.accent.withOpacity(0.5), size: sw * 0.05),
                  ]),
                ),
            ]);
          }),
        ],
      ),
    );
  }
}

class _ProductChainTile extends StatelessWidget {
  final int          index;
  final FarmProduct  product;
  final _FormuleVisualStyle style;
  final double       sw;
  final bool         available;
  final bool         isChecked;
  final ValueChanged<bool> onChanged;
  const _ProductChainTile({
    required this.index, required this.product, required this.style, required this.sw,
    required this.available, required this.isChecked, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: available ? 1 : 0.55,
      child: Container(
        padding: EdgeInsets.all(sw * 0.03),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isChecked ? style.accent.withOpacity(0.3) : Colors.grey.withOpacity(0.15)),
          boxShadow: [BoxShadow(
              color: style.accent.withOpacity(0.06),
              blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(children: [
          Container(
            width: sw * 0.075, height: sw * 0.075,
            decoration: BoxDecoration(color: style.accent, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text('$index',
              style: TextStyle(
                fontFamily: 'Cairo', fontSize: sw * 0.032,
                fontWeight: FontWeight.w800, color: Colors.white)),
          ),
          SizedBox(width: sw * 0.03),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: sw * 0.14, height: sw * 0.14, color: AppColors.background,
              child: product.imageUrl.startsWith('http')
                  ? Image.network(product.imageUrl, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.image_not_supported_outlined))
                  : const Icon(Icons.eco_rounded),
            ),
          ),
          SizedBox(width: sw * 0.03),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Cairo', fontSize: sw * 0.033,
                    fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                SizedBox(height: sw * 0.005),
                Text(
                  available ? '${product.price} DH / ${product.unit}' : 'Rupture de stock',
                  style: TextStyle(
                    fontFamily: 'Cairo', fontSize: sw * 0.027,
                    fontWeight: FontWeight.w600,
                    color: available ? AppColors.textLight : AppColors.error)),
              ],
            ),
          ),
          Checkbox(
            value: isChecked,
            activeColor: style.accent,
            onChanged: available ? (v) => onChanged(v ?? false) : null,
          ),
        ]),
      ),
    );
  }
}

// ── CTA sticky bas de page ───────────────────────────────────────────────────
class _StickyCTA extends StatelessWidget {
  final _FormuleVisualStyle style;
  final double sw;
  final num savings, total;
  final int selectedCount;
  final bool enabled;
  final bool loading;
  final VoidCallback onBuy;
  const _StickyCTA({
    required this.style, required this.sw, required this.savings, required this.total,
    required this.selectedCount, required this.enabled, required this.loading,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(sw * 0.05, sw * 0.03, sw * 0.05, sw * 0.02),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: GestureDetector(
          onTap: enabled ? onBuy : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: sw * 0.155,
            decoration: BoxDecoration(
              color: enabled ? style.accent : Colors.grey.shade400,
              borderRadius: BorderRadius.circular(18),
              boxShadow: enabled
                  ? [BoxShadow(
                      color: style.accent.withOpacity(0.3),
                      blurRadius: 14, offset: const Offset(0, 6))]
                  : [],
            ),
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.4))
                  : selectedCount == 0
                      ? Text('Sélectionnez au moins un produit',
                          style: TextStyle(
                            fontFamily: 'Cairo', fontSize: sw * 0.034,
                            fontWeight: FontWeight.w800, color: Colors.white))
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              savings > 0
                                  ? 'En achetant cette formule, économisez ${savings.toStringAsFixed(0)} DH'
                                  : 'Ajouter au panier',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Cairo', fontSize: sw * 0.036,
                                fontWeight: FontWeight.w800, color: Colors.white)),
                            SizedBox(height: sw * 0.006),
                            Text('Total : ${total.toStringAsFixed(0)} DH · $selectedCount produit${selectedCount > 1 ? 's' : ''}',
                              style: TextStyle(
                                fontFamily: 'Cairo', fontSize: sw * 0.026,
                                color: Colors.white.withOpacity(0.9))),
                          ],
                        ),
            ),
          ),
        ),
      ),
    );
  }
}