// lib/features/profile/profile_screen.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mrbeldi/core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  MODEL
//  Champs Firestore attendus dans users/{uid} :
//  • displayName   : String
//  • email         : String
//  • photoUrl      : String?
//  • points        : number  — lu directement, sans transformation ni palier
//                    complexe. 1 point = 1% pour l'indicateur "Santé".
//  • followers     : number  — nombre d'abonnés (0 si absent)
//  • createdAt     : Timestamp
//
//  Champs calculés en temps réel (sous-collections) :
//  • numorders     : number  — mis à jour par Cloud Function à chaque commande
//  • numreviews    : number  — mis à jour par Cloud Function à chaque avis
// ─────────────────────────────────────────────────────────────────────────────
class UserProfile {
  final String name;
  final String email;
  final String? photoUrl;
  final int points;
  final int followers;
  final int ordersCount;
  final int reviewsCount;
  final String memberSince;

  const UserProfile({
    required this.name,
    required this.email,
    this.photoUrl,
    this.points = 0,
    this.followers = 0,
    this.ordersCount = 0,
    this.reviewsCount = 0,
    this.memberSince = '',
  });

  /// Pourcentage de "Santé" affiché dans les stats : 1 point Firestore = 1%,
  /// borné entre 0 et 100 pour l'affichage.
  int get healthPercent => points.clamp(0, 100);

  factory UserProfile.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
    User authUser,
  ) {
    final d = doc.data() ?? {};
    final ts = d['createdAt'] as Timestamp?;
    String since = '';
    if (ts != null) {
      final dt = ts.toDate();
      since = 'Membre depuis ${_monthFr(dt.month)} ${dt.year}';
    }
    return UserProfile(
      name:
          d['displayName'] as String? ?? authUser.displayName ?? 'Utilisateur',
      email: d['email'] as String? ?? authUser.email ?? '',
      photoUrl: d['photoUrl'] as String? ?? authUser.photoURL,
      // Cast sécurisé num→int : Firestore peut stocker des doubles même
      // pour des champs entiers — `as int?` crasherait.
      points: (d['points'] as num?)?.toInt() ?? 0,
      followers: (d['followers'] as num?)?.toInt() ?? 0,
      // ✏️ Champs Firestore réels dans users/{uid} : `numorders` et
      // `numreviews` (et non ordersCount/reviewsCount).
      ordersCount: (d['numorders'] as num?)?.toInt() ?? 0,
      reviewsCount: (d['numreviews'] as num?)?.toInt() ?? 0,
      memberSince: since,
    );
  }

  static String _monthFr(int m) => const [
    '',
    'Jan',
    'Fév',
    'Mar',
    'Avr',
    'Mai',
    'Juin',
    'Juil',
    'Août',
    'Sep',
    'Oct',
    'Nov',
    'Déc',
  ][m];
}

// ─────────────────────────────────────────────────────────────────────────────
//  NIVEAUX "HÉROS DE L'ALIMENTATION" — thème ludique et motivant basé
//  uniquement sur `points` (aucun sous-système séparé). Utilisé à la fois
//  pour le badge à côté du nom (header) et pour la carte Points.
//    Niveau 1 · 0-15   → Explorateur Santé
//    Niveau 2 · 16-36  → Mangeur Malin
//    Niveau 3 · 37-69  → Champion de l'Équilibre
//    Niveau 4 · 70+    → Ambassadeur du Bien-être (sommet, badges dorés)
// ─────────────────────────────────────────────────────────────────────────────
class LoyaltyLevel {
  final int index; // 1..4
  final int minPoints;
  final int?
  nextThreshold; // points requis pour le niveau suivant (null = niveau max)
  final String label;
  final String emoji;
  final String description;
  // ── Habillage "bouclier de jeu vidéo" — design distinct par niveau ──
  final IconData badgeIcon;
  final List<Color> shieldColors;
  final Color shieldBorderColor;

  const LoyaltyLevel({
    required this.index,
    required this.minPoints,
    required this.nextThreshold,
    required this.label,
    required this.emoji,
    required this.description,
    required this.badgeIcon,
    required this.shieldColors,
    required this.shieldBorderColor,
  });

  bool get isMax => nextThreshold == null;

  /// Progression (0 → 1) à l'intérieur du niveau actuel.
  double progressFor(int points) {
    if (isMax) return 1.0;
    final span = nextThreshold! - minPoints;
    if (span <= 0) return 1.0;
    return ((points - minPoints) / span).clamp(0.0, 1.0);
  }

  /// Points restants avant le niveau suivant (0 si niveau max).
  int remainingFor(int points) {
    if (isMax) return 0;
    return (nextThreshold! - points).clamp(0, nextThreshold!);
  }
}

const List<LoyaltyLevel> kLoyaltyLevels = [
  LoyaltyLevel(
    index: 1,
    minPoints: 0,
    nextThreshold: 16,
    label: 'Explorateur Santé',
    emoji: '🌱',
    description:
        'Vous découvrez nos produits et testez de nouvelles alternatives saines.',
    badgeIcon: Icons.eco_rounded,
    shieldColors: [Color(0xFF7ED67A), Color(0xFF2E8B57)],
    shieldBorderColor: Color(0xFFBFF0BE),
  ),
  LoyaltyLevel(
    index: 2,
    minPoints: 16,
    nextThreshold: 37,
    label: 'Mangeur Malin',
    emoji: '🎯',
    description:
        'Vous faites des choix alimentaires conscients et calculez vos calories avec précision.',
    badgeIcon: Icons.track_changes_rounded,
    shieldColors: [Color(0xFF6FD0F0), Color(0xFF1E7BB8)],
    shieldBorderColor: Color(0xFFC7ECFB),
  ),
  LoyaltyLevel(
    index: 3,
    minPoints: 37,
    nextThreshold: 70,
    label: "Champion de l'Équilibre",
    emoji: '🏅',
    description:
        'Vous vous engagez pleinement pour des repas sains et complets.',
    badgeIcon: Icons.military_tech_rounded,
    shieldColors: [Color(0xFFFFD166), Color(0xFFE8891C)],
    shieldBorderColor: Color(0xFFFFE8B0),
  ),
  LoyaltyLevel(
    index: 4,
    minPoints: 70,
    nextThreshold: null,
    label: 'Ambassadeur du Bien-être',
    emoji: '👑',
    description:
        'Le sommet de la pyramide : badges dorés et récompenses exclusives.',
    badgeIcon: Icons.workspace_premium_rounded,
    shieldColors: [Color(0xFFE0B3FF), Color(0xFF8E3FC9)],
    shieldBorderColor: Color(0xFFFFD770),
  ),
];

LoyaltyLevel loyaltyLevelForPoints(int points) {
  for (final l in kLoyaltyLevels.reversed) {
    if (points >= l.minPoints) return l;
  }
  return kLoyaltyLevels.first;
}

// ─────────────────────────────────────────────────────────────────────────────
//  BOUCLIER DE NIVEAU — remplace les emojis par un vrai badge en forme de
//  bouclier façon jeu vidéo (dégradé + liseré + icône), design différent
//  pour chaque niveau (couleurs définies dans `LoyaltyLevel.shieldColors`).
// ─────────────────────────────────────────────────────────────────────────────
class _ShieldPainter extends CustomPainter {
  final List<Color> colors;
  final Color borderColor;

  _ShieldPainter({required this.colors, required this.borderColor});

  Path _shieldPath(Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()..moveTo(w * 0.5, h * 0.02);
    path.cubicTo(w * 0.5, h * 0.02, w * 0.78, h * 0.10, w * 0.94, h * 0.14);
    path.cubicTo(w * 0.97, h * 0.15, w * 1.0, h * 0.17, w * 1.0, h * 0.20);
    path.lineTo(w * 1.0, h * 0.48);
    path.cubicTo(w * 1.0, h * 0.74, w * 0.82, h * 0.92, w * 0.5, h * 1.0);
    path.cubicTo(w * 0.18, h * 0.92, w * 0.0, h * 0.74, w * 0.0, h * 0.48);
    path.lineTo(w * 0.0, h * 0.20);
    path.cubicTo(w * 0.0, h * 0.17, w * 0.03, h * 0.15, w * 0.06, h * 0.14);
    path.cubicTo(w * 0.22, h * 0.10, w * 0.5, h * 0.02, w * 0.5, h * 0.02);
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _shieldPath(size);

    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(path, fillPaint);

    // Petit reflet en haut pour l'effet "verre/metal" façon jeu vidéo.
    final highlightPath = Path()
      ..moveTo(size.width * 0.5, size.height * 0.06)
      ..lineTo(size.width * 0.85, size.height * 0.18)
      ..lineTo(size.width * 0.5, size.height * 0.42)
      ..lineTo(size.width * 0.15, size.height * 0.18)
      ..close();
    canvas.drawPath(
      highlightPath,
      Paint()..color = Colors.white.withOpacity(0.16),
    );

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.055
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _ShieldPainter oldDelegate) =>
      oldDelegate.colors != colors || oldDelegate.borderColor != borderColor;
}

class _LevelShield extends StatelessWidget {
  final LoyaltyLevel level;
  final double size;

  const _LevelShield({required this.level, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 1.12,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size * 1.12),
            painter: _ShieldPainter(
              colors: level.shieldColors,
              borderColor: level.shieldBorderColor,
            ),
          ),
          Icon(level.badgeIcon, color: Colors.white, size: size * 0.44),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ICÔNE PIÈCE / MONNAIE — remplace partout l'ancien emoji 🌱 utilisé comme
//  symbole des "Points".
//
//  ⚠️ IMPORTANT — mise en place de l'asset (obligatoire pour que l'image
//  s'affiche) :
//    1) Copier le fichier depuis
//       C:\dev\agritech\ifarm\images\coins-removebg-preview.png
//       vers l'intérieur du projet Flutter, ex. :
//       <racine_projet>/assets/images/coins-removebg-preview.png
//       (Flutter ne peut pas charger un chemin Windows absolu à l'exécution,
//       uniquement des assets déclarés et empaquetés avec l'app.)
//    2) Déclarer le dossier dans pubspec.yaml :
//         flutter:
//           assets:
//             - assets/images/coins-removebg-preview.png
//    3) Lancer `flutter pub get` puis relancer l'app (hot reload ne suffit
//       pas pour un nouvel asset).
// ─────────────────────────────────────────────────────────────────────────────
class _CoinIcon extends StatelessWidget {
  final double size;
  const _CoinIcon({this.size = 22});

  static const String assetPath = 'images/coins-removebg-preview.png';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PROFILE SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return _GuestPage();
    return _LoggedInPage(user: user);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PAGE INVITÉ
// ─────────────────────────────────────────────────────────────────────────────
class _GuestPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final w = MediaQuery.of(context).size.width;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: w * 0.07),
            child: Column(
              children: [
                SizedBox(height: h * 0.08),
                Container(
                  width: w * 0.3,
                  height: w * 0.3,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withOpacity(0.1),
                  ),
                  child: Center(
                    child: Text('🌿', style: TextStyle(fontSize: w * 0.12)),
                  ),
                ),
                SizedBox(height: h * 0.03),
                Text(
                  'Rejoignez MrBeldi !',
                  style: TextStyle(
                    fontSize: w * 0.06,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: h * 0.012),
                // ✏️ le 🌱 final est remplacé par l'icône pièce (symbole des
                // "Points"), insérée en ligne via WidgetSpan.
                Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: w * 0.035,
                      color: AppColors.textSecondary,
                      height: 1.6,
                    ),
                    children: [
                      const TextSpan(
                        text:
                            'Connectez-vous pour accéder à vos commandes,\n'
                            'vos favoris et vos Points ',
                      ),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 2),
                          child: _CoinIcon(size: w * 0.045),
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: h * 0.04),
                // ✏️ le 3e item ('🌱', ...) utilise désormais l'icône pièce
                // au lieu de l'emoji, cohérent avec le reste de l'app.
                ...[
                  ('🛒', 'Suivre vos commandes en temps réel', false),
                  ('❤️', 'Sauvegarder vos produits favoris', false),
                  ('', 'Gagner des Points à chaque achat', true),
                ].map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          e.$3
                              ? _CoinIcon(size: w * 0.06)
                              : Text(
                                  e.$1,
                                  style: TextStyle(fontSize: w * 0.055),
                                ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              e.$2,
                              style: TextStyle(
                                fontSize: w * 0.033,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(height: h * 0.04),
                SizedBox(
                  width: double.infinity,
                  height: h * 0.065,
                  child: ElevatedButton(
                    onPressed: () => context.push('/login?from=/profile'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      "Se connecter / S'inscrire",
                      style: TextStyle(
                        fontSize: w * 0.042,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: h * 0.04),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PAGE CONNECTÉ
// ─────────────────────────────────────────────────────────────────────────────
class _LoggedInPage extends StatefulWidget {
  final User user;
  const _LoggedInPage({required this.user});

  @override
  State<_LoggedInPage> createState() => _LoggedInPageState();
}

class _LoggedInPageState extends State<_LoggedInPage> {
  // Stream temps réel sur le document utilisateur
  Stream<DocumentSnapshot<Map<String, dynamic>>> get _profileStream =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .snapshots();

  // ── Popup "Félicitations 100 points" ──────────────────────────────────
  // On ne veut afficher ce popup qu'une seule fois par utilisateur (pas à
  // chaque ouverture de l'écran). L'état "déjà affiché" est mémorisé
  // localement (SharedPreferences) par uid, en plus d'un verrou en
  // mémoire pour éviter les doublons pendant qu'un même écran est ouvert.
  bool _rewardDialogHandled = false;

  // ── Déconnexion en cours ─────────────────────────────────────────────
  // Conservé pour compatibilité (ex. appel depuis un autre écran comme
  // les Paramètres) : ignore un éventuel permission-denied transitoire
  // pendant la fenêtre où l'utilisateur est en train de se déconnecter.
  bool _signingOut = false;

  String get _rewardPrefsKey => 'reward100_shown_${widget.user.uid}';

  Future<void> _maybeShowRewardDialog(int points) async {
    if (_rewardDialogHandled) return;
    if (points < 100) return;
    _rewardDialogHandled = true; // verrou immédiat contre les doublons

    final prefs = await SharedPreferences.getInstance();
    final alreadyShown = prefs.getBool(_rewardPrefsKey) ?? false;
    if (alreadyShown) return;
    await prefs.setBool(_rewardPrefsKey, true);

    if (!mounted) return;
    // On laisse le temps au premier frame de se construire avant
    // d'ouvrir le dialogue.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withOpacity(0.55),
        builder: (_) => const _Reward100Dialog(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _profileStream,
      builder: (context, snap) {
        // Pendant la déconnexion, on ignore tout nouvel état du stream
        // (y compris une éventuelle erreur permission-denied) et on
        // affiche un simple indicateur le temps que la navigation se
        // termine.
        if (_signingOut) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Indicateur de chargement initial uniquement
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // ✏️ On protège aussi contre une erreur du stream (ex.
        // permission-denied transitoire) plutôt que de la laisser
        // remonter silencieusement : on retombe sur les infos Auth.
        final profile = (snap.hasData && !snap.hasError && snap.data!.exists)
            ? UserProfile.fromFirestore(snap.data!, widget.user)
            : UserProfile(
                name: widget.user.displayName ?? 'Utilisateur',
                email: widget.user.email ?? '',
                photoUrl: widget.user.photoURL,
              );

        // Vérifie si l'utilisateur vient d'atteindre (ou a déjà atteint)
        // 100 points, et affiche le popup de félicitations une seule fois.
        _maybeShowRewardDialog(profile.points);

        return Scaffold(
          backgroundColor: AppColors.background,
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── SliverAppBar ──────────────────────────────────────────
              SliverAppBar(
                expandedHeight: h * 0.185,
                pinned: true,
                backgroundColor: AppColors.primaryDark,
                systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
                  statusBarColor: Colors.transparent,
                ),
                elevation: 0,
                actions: [
                  IconButton(
                    icon: const Icon(
                      Icons.headset_mic_outlined,
                      color: Colors.white,
                    ),
                    onPressed: () => context.push('/support'),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: Colors.white,
                    ),
                    onPressed: () => context.push('/settings'),
                  ),
                  const SizedBox(width: 4),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.pin,
                  background: _ProfileHeader(
                    profile: profile,
                    screenW: w,
                    screenH: h,
                  ),
                ),
              ),

              // ── Stats row (données réelles Firestore) ─────────────────
              // ✏️ Un petit SizedBox sépare désormais la carte du header
              // au-dessus, pour éviter tout chevauchement visuel.
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: h * 0.014),
                  child: _StatsRow(profile: profile, screenW: w),
                ),
              ),

              // ── Contenu ───────────────────────────────────────────────
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: w * 0.04),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    SizedBox(height: h * 0.02),

                    // Carte Points — affichage direct, sans palier ni bouton
                    // "Détails" (données brutes du champ `points`).
                    _SeedsCard(points: profile.points, screenW: w),
                    SizedBox(height: h * 0.025),

                    // ── Mon compte ─────────────────────────────────────
                    _SectionLabel('Mon compte'),
                    SizedBox(height: h * 0.012),
                    _MenuItem(
                      icon: Icons.shopping_bag_rounded,
                      label: 'Vos commandes',
                      badge: profile.ordersCount > 0
                          ? '${profile.ordersCount}'
                          : null,
                      color: AppColors.primary,
                      onTap: () => context.push('/orders'),
                    ),
                    _MenuItem(
                      icon: Icons.favorite_rounded,
                      label: 'Mes favoris',
                      color: const Color(0xFFE91E63),
                      onTap: () => context.go('/favourites'),
                    ),
                    _MenuItem(
                      icon: Icons.star_rounded,
                      label: 'Mes avis',
                      badge: profile.reviewsCount > 0
                          ? '${profile.reviewsCount}'
                          : null,
                      color: const Color(0xFFFFB300),
                      onTap: () => context.push('/orders'),
                    ),
                    _MenuItem(
                      icon: Icons.message_rounded,
                      label: 'Messages',
                      color: AppColors.secondary,
                      onTap: () => context.push('/support'),
                    ),

                    SizedBox(height: h * 0.025),

                    // ── Autres ─────────────────────────────────────────
                    _SectionLabel('Autres'),
                    SizedBox(height: h * 0.012),
                    _HorizontalRow(screenW: w),

                    SizedBox(height: h * 0.03),
                    Center(
                      child: Text(
                        'MrBeldi v1.0.7+9 · Maroc 🇲🇦',
                        style: TextStyle(
                          fontSize: w * 0.028,
                          color: AppColors.textLight,
                        ),
                      ),
                    ),
                    SizedBox(height: h * 0.12),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  RÉCOMPENSE 100 POINTS — popup "façon jeu vidéo" affiché une seule fois
//  lorsque l'utilisateur atteint 100 points. Design festif (fleurs, feuilles,
//  trophée animé) + CTA en pilule verte vers WhatsApp (même numéro que
//  l'écran Support), avec un message pré-rempli dédié.
// ─────────────────────────────────────────────────────────────────────────────
class _Reward100Dialog extends StatefulWidget {
  const _Reward100Dialog();

  // Même numéro WhatsApp que support_screen.dart
  static const String _whatsappNumber = '212782293139';
  static const String _rewardMessage =
      'Bonjour 👋, j\'ai atteint 100 points et je voudrais savoir comment '
      'obtenir mon propre arbre 🌳';

  static Future<void> _openWhatsApp(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final uri = Uri.parse(
      'https://wa.me/$_whatsappNumber?text=${Uri.encodeComponent(_rewardMessage)}',
    );
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('WhatsApp n\'est pas installé sur cet appareil'),
        ),
      );
    }
  }

  @override
  State<_Reward100Dialog> createState() => _Reward100DialogState();
}

class _Reward100DialogState extends State<_Reward100Dialog>
    with TickerProviderStateMixin {
  late final AnimationController _entranceCtrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  late final AnimationController _trophyCtrl;
  late final Animation<double> _trophyBounce;

  late final AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _scaleAnim = CurvedAnimation(
      parent: _entranceCtrl,
      curve: Curves.elasticOut,
    );
    _fadeAnim = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
    );

    _trophyCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _trophyBounce = Tween<double>(
      begin: -6,
      end: 6,
    ).animate(CurvedAnimation(parent: _trophyCtrl, curve: Curves.easeInOut));

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 60), () {
      if (mounted) _entranceCtrl.forward();
    });
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _trophyCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final cardW = math.min(w * 0.88, 380.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: FadeTransition(
        opacity: _fadeAnim,
        child: ScaleTransition(
          scale: _scaleAnim,
          child: Container(
            width: cardW,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 30,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Bandeau supérieur festif ──────────────────────
                    _RewardHeaderBanner(
                      cardW: cardW,
                      shimmerCtrl: _shimmerCtrl,
                    ),
                    // ── Corps ──────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 44, 22, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            '🎉 Félicitations !',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFFD770), Color(0xFFE8A93A)],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFFE8A93A,
                                  ).withOpacity(0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Text(
                              '💯 Points atteints !',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF3D2B00),
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Vous avez complété 100 points !\n'
                            'Contactez notre équipe pour finaliser la '
                            'récupération de votre cadeau exclusif 🎁',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                              height: 1.55,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 22),

                          // ── CTA pilule verte WhatsApp ──────────────
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _Reward100Dialog._openWhatsApp(context);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF25D366),
                                foregroundColor: Colors.white,
                                elevation: 4,
                                shadowColor: const Color(
                                  0xFF25D366,
                                ).withOpacity(0.5),
                                shape: const StadiumBorder(),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.phone_android_rounded, size: 20),
                                  SizedBox(width: 10),
                                  Text(
                                    'Nous contacter sur WhatsApp',
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text(
                              'Plus tard',
                              style: TextStyle(
                                color: AppColors.textLight,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // ── Trophée animé (chevauche le bandeau + le corps) ──
                Positioned(
                  top: (cardW * 0.34) - 46,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _trophyBounce,
                      builder: (_, child) => Transform.translate(
                        offset: Offset(0, _trophyBounce.value * 0.4),
                        child: child,
                      ),
                      child: Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFE082), Color(0xFFFFB300)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(color: Colors.white, width: 4),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFFB300).withOpacity(0.5),
                              blurRadius: 18,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.emoji_events_rounded,
                          color: Colors.white,
                          size: 46,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Bandeau supérieur du popup 100 points — dégradé vert + fleurs, feuilles
//  et étincelles décoratives pour un rendu festif façon jeu vidéo.
// ─────────────────────────────────────────────────────────────────────────────
class _RewardHeaderBanner extends StatelessWidget {
  final double cardW;
  final AnimationController shimmerCtrl;

  const _RewardHeaderBanner({required this.cardW, required this.shimmerCtrl});

  @override
  Widget build(BuildContext context) {
    final bannerH = cardW * 0.5;
    return SizedBox(
      height: bannerH,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // dégradé de fond
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF1F5F3E),
                  Color(0xFF2E8B57),
                  Color(0xFF52C77E),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          // cercles décoratifs
          Positioned(
            top: -30,
            left: -30,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.08),
              ),
            ),
          ),
          Positioned(
            bottom: -20,
            right: -20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.08),
              ),
            ),
          ),
          // fleurs & feuilles décoratives
          Positioned(
            top: 10,
            left: 14,
            child: Transform.rotate(
              angle: -0.3,
              child: Icon(
                Icons.local_florist_rounded,
                size: 34,
                color: Colors.white.withOpacity(0.55),
              ),
            ),
          ),
          Positioned(
            top: 18,
            right: 20,
            child: Transform.rotate(
              angle: 0.4,
              child: Icon(
                Icons.spa_rounded,
                size: 30,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          ),
          Positioned(
            bottom: 14,
            left: 26,
            child: Transform.rotate(
              angle: 0.2,
              child: Icon(
                Icons.eco_rounded,
                size: 26,
                color: Colors.white.withOpacity(0.45),
              ),
            ),
          ),
          Positioned(
            bottom: 20,
            right: 34,
            child: Transform.rotate(
              angle: -0.15,
              child: Icon(
                Icons.local_florist_rounded,
                size: 24,
                color: Colors.white.withOpacity(0.4),
              ),
            ),
          ),
          // étincelles scintillantes (façon jeu vidéo)
          AnimatedBuilder(
            animation: shimmerCtrl,
            builder: (context, child) {
              return Stack(
                children: List.generate(5, (i) {
                  final t = (shimmerCtrl.value + i * 0.2) % 1.0;
                  final opacity = (math.sin(
                    t * math.pi,
                  )).clamp(0.0, 1.0).toDouble();
                  final dx = 20.0 + (i * (cardW - 40) / 5);
                  final dy = 12.0 + (i.isEven ? 6 : 20) + (t * 10);
                  return Positioned(
                    left: dx,
                    top: dy,
                    child: Opacity(
                      opacity: opacity * 0.85,
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        size: 14 + (i % 3) * 3,
                        color: const Color(0xFFFFE082),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
          // léger dégradé sombre en bas pour lisibilité de la transition
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 30,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.white.withOpacity(0.0)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PROFILE HEADER
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileHeader extends StatelessWidget {
  final UserProfile profile;
  final double screenW;
  final double screenH;

  const _ProfileHeader({
    required this.profile,
    required this.screenW,
    required this.screenH,
  });

  @override
  Widget build(BuildContext context) {
    final avatarR = (screenW * 0.08).clamp(30.0, 38.0);
    final level = loyaltyLevelForPoints(profile.points);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Dégradé fond
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1F5F3E), Color(0xFF2E8B57), Color(0xFF3A9E68)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        // Cercles décoratifs
        Positioned(
          top: -40,
          right: -40,
          child: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.06),
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
              color: AppColors.accent.withOpacity(0.1),
            ),
          ),
        ),
        // ── Petites illustrations "nature & santé" — agrandies et plus
        // visibles, pour un cachet végétal clairement perceptible sur le
        // fond du header.
        Positioned(
          top: screenH * 0.02,
          left: screenW * 0.04,
          child: Transform.rotate(
            angle: -0.35,
            child: Icon(
              Icons.eco_rounded,
              size: screenW * 0.20,
              color: Colors.white.withOpacity(0.20),
            ),
          ),
        ),
        Positioned(
          top: screenH * 0.06,
          right: screenW * 0.22,
          child: Transform.rotate(
            angle: 0.5,
            child: Icon(
              Icons.spa_rounded,
              size: screenW * 0.15,
              color: Colors.white.withOpacity(0.18),
            ),
          ),
        ),
        Positioned(
          bottom: screenH * 0.02,
          right: screenW * 0.02,
          child: Transform.rotate(
            angle: 0.2,
            child: Icon(
              Icons.local_florist_rounded,
              size: screenW * 0.24,
              color: Colors.white.withOpacity(0.16),
            ),
          ),
        ),
        // Contenu
        SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              screenW * 0.05,
              screenH * 0.004,
              screenW * 0.05,
              screenH * 0.008,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: avatarR,
                    backgroundColor: AppColors.primaryLight,
                    backgroundImage: profile.photoUrl != null
                        ? CachedNetworkImageProvider(profile.photoUrl!)
                        : null,
                    child: profile.photoUrl == null
                        ? Text(
                            profile.name.isNotEmpty
                                ? profile.name[0].toUpperCase()
                                : 'U',
                            style: TextStyle(
                              fontSize: avatarR * 0.75,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                ),
                SizedBox(height: screenH * 0.004),
                // Nom + badge de niveau de compte (basé sur `points`)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        profile.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: (screenW * 0.052).clamp(16.0, 22.0),
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    SizedBox(width: screenW * 0.02),
                    // ── Badge de niveau (professionnel, sobre) ──────────
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFD770), Color(0xFFE8A93A)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFE8A93A).withOpacity(0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _LevelShield(level: level, size: 13),
                          const SizedBox(width: 3),
                          Text(
                            level.label,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF3D2B00),
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: screenH * 0.002),
                // Email
                Text(
                  profile.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: (screenW * 0.03).clamp(10.0, 13.0),
                    color: Colors.white.withOpacity(0.75),
                  ),
                ),
                SizedBox(height: screenH * 0.005),
                // Badge "Membre depuis"
                if (profile.memberSince.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.verified_rounded,
                          size: 12,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          profile.memberSince,
                          style: TextStyle(
                            fontSize: (screenW * 0.027).clamp(9.0, 12.0),
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  STATS ROW — données réelles depuis Firestore :
//    • Commandes → numorders
//    • Santé     → jauge façon compteur de voiture, % dérivé de `points`
//    • Avis      → numreviews (remplace l'ancien compteur d'abonnés)
// ─────────────────────────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final UserProfile profile;
  final double screenW;

  const _StatsRow({required this.profile, required this.screenW});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: screenW * 0.04),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: _StatCell(
              border: true,
              child: Column(
                children: [
                  Icon(
                    Icons.shopping_bag_rounded,
                    color: AppColors.primary,
                    size: screenW * 0.055,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${profile.ordersCount}',
                    style: TextStyle(
                      fontSize: screenW * 0.045,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'Commandes',
                    style: TextStyle(
                      fontSize: screenW * 0.026,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _StatCell(
              border: true,
              child: Column(
                children: [
                  _HealthGauge(
                    percent: profile.healthPercent,
                    size: screenW * 0.145,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Healthy Style',
                    style: TextStyle(
                      fontSize: screenW * 0.024,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _StatCell(
              border: false,
              child: Column(
                children: [
                  Icon(
                    Icons.star_rounded,
                    color: AppColors.primary,
                    size: screenW * 0.055,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${profile.reviewsCount}',
                    style: TextStyle(
                      fontSize: screenW * 0.045,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'Avis',
                    style: TextStyle(
                      fontSize: screenW * 0.026,
                      color: AppColors.textSecondary,
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

class _StatCell extends StatelessWidget {
  final Widget child;
  final bool border;
  const _StatCell({required this.child, required this.border});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: border
          ? const BoxDecoration(
              border: Border(
                right: BorderSide(color: AppColors.border, width: 1),
              ),
            )
          : null,
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  HEALTH GAUGE — jauge circulaire façon compteur de voiture, avec le
//  pourcentage de "Santé" affiché au centre (1 point Firestore = 1%).
// ─────────────────────────────────────────────────────────────────────────────
class _HealthGauge extends StatelessWidget {
  final int percent; // 0-100
  final double size;

  const _HealthGauge({required this.percent, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: percent.clamp(0, 100) / 100),
        duration: const Duration(milliseconds: 1000),
        curve: Curves.easeOutCubic,
        builder: (_, val, __) => CustomPaint(
          painter: _GaugePainter(progress: val),
          child: Center(
            child: Text(
              '${(val * 100).round()}%',
              style: TextStyle(
                fontSize: size * 0.28,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double progress; // 0..1
  _GaugePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.11;
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    const startAngle = -math.pi / 2; // départ en haut, comme un compteur
    final sweep = 2 * math.pi * progress;

    final bgPaint = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, bgPaint);

    final fgPaint = Paint()
      ..shader = const SweepGradient(
        colors: [Color(0xFFEF5350), Color(0xFFFFC107), Color(0xFF4CAF50)],
        startAngle: 0,
        endAngle: math.pi * 2,
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, startAngle, sweep, false, fgPaint);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
//  CARTE POINTS — thème "Héros de l'Alimentation" 🏆
//  Design "carte blanche organique" : fond blanc, liseré vert, accents
//  verts. Le bouclier du niveau est affiché au-dessus du nom du niveau
//  (badge façon jeu vidéo), et le bouton d'action est un vrai CTA pleine
//  largeur en bas de carte plutôt qu'un petit bouton flottant qui
//  chevauchait le contenu.
// ─────────────────────────────────────────────────────────────────────────────
class _SeedsCard extends StatefulWidget {
  final int points;
  final double screenW;

  const _SeedsCard({required this.points, required this.screenW});

  @override
  State<_SeedsCard> createState() => _SeedsCardState();
}

class _SeedsCardState extends State<_SeedsCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bumpController;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _glowAnim;

  late int _lastPoints;
  int _gainDelta = 0;
  bool _popVisible = false;
  double _popTop = 6;
  double _popOpacity = 0;

  // Bascule périodique entre la description du niveau et le message promo.
  bool _showPromo = false;
  Timer? _messageTimer;
  static const String _promoMessage =
      'Échangez vos points contre des cadeaux et réductions incroyables !';

  @override
  void initState() {
    super.initState();
    _lastPoints = widget.points;

    _bumpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.32,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.32,
          end: 0.94,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.94,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
    ]).animate(_bumpController);
    _glowAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 70),
    ]).animate(CurvedAnimation(parent: _bumpController, curve: Curves.easeOut));

    _messageTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      setState(() => _showPromo = !_showPromo);
    });
  }

  @override
  void didUpdateWidget(covariant _SeedsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.points > _lastPoints) {
      _playGainEffect(widget.points - _lastPoints);
    }
    _lastPoints = widget.points;
  }

  Future<void> _playGainEffect(int delta) async {
    setState(() {
      _gainDelta = delta;
      _popVisible = true;
      _popTop = 4;
      _popOpacity = 1;
    });
    _bumpController.forward(from: 0);

    // léger délai pour laisser l'AnimatedPositioned partir du bon point
    // de départ avant de basculer vers la position "flottante"
    await Future.delayed(const Duration(milliseconds: 40));
    if (!mounted) return;
    setState(() => _popTop = -32);

    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _popOpacity = 0);

    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() => _popVisible = false);
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    _bumpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.screenW;
    final points = widget.points;
    final level = loyaltyLevelForPoints(points);
    final progress = level.progressFor(points);
    final remaining = level.remainingFor(points);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.045, vertical: w * 0.03),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.14),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Bandeau thème "Héros de l'Alimentation" 🏆 ──
          Row(
            children: [
              Icon(
                Icons.emoji_events_rounded,
                size: w * 0.032,
                color: const Color(0xFFE8A93A),
              ),
              SizedBox(width: w * 0.012),
              Flexible(
                child: Text(
                  "Héros de l'Alimentation",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: w * 0.024,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: w * 0.018),
          Row(
            children: [
              // ── Pièce animée (bump + halo doré + "+X" flottant) ──
              AnimatedBuilder(
                animation: _bumpController,
                builder: (context, child) {
                  final coinSize = (w * 0.078 * 2.1).clamp(30.0, 44.0);
                  final badgeSize = (coinSize * 1.2).clamp(36.0, 54.0);
                  return SizedBox(
                    width: badgeSize,
                    height: badgeSize + 18, // espace pour le "+X" flottant
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.bottomCenter,
                      children: [
                        // halo doré pulsant pendant le gain
                        Positioned(
                          bottom: 0,
                          child: Container(
                            width: badgeSize,
                            height: badgeSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFFFFD770,
                                  ).withOpacity(0.55 * _glowAnim.value),
                                  blurRadius: 14,
                                  spreadRadius: 2 * _glowAnim.value,
                                ),
                              ],
                            ),
                          ),
                        ),
                        // backdrop circulaire (teinte verte douce + liseré)
                        Positioned(
                          bottom: 0,
                          child: Container(
                            width: badgeSize,
                            height: badgeSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  AppColors.primary.withOpacity(0.14),
                                  AppColors.primary.withOpacity(0.04),
                                ],
                              ),
                              border: Border.all(
                                color: AppColors.primary.withOpacity(0.35),
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Transform.scale(
                                scale: _scaleAnim.value,
                                child: _CoinIcon(size: coinSize),
                              ),
                            ),
                          ),
                        ),
                        // "+X" flottant façon pickup de pièces de jeu vidéo
                        if (_popVisible)
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 700),
                            curve: Curves.easeOut,
                            top: _popTop,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 400),
                              opacity: _popOpacity,
                              child: Text(
                                '+$_gainDelta',
                                style: TextStyle(
                                  fontSize: w * 0.036,
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFFE8A93A),
                                  shadows: const [
                                    Shadow(
                                      color: Colors.black26,
                                      blurRadius: 3,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              SizedBox(width: w * 0.03),
              // Compteur animé — valeur brute du champ `points`, sans palier
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Mes Points',
                      style: TextStyle(
                        fontSize: w * 0.028,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TweenAnimationBuilder<int>(
                      tween: IntTween(begin: 0, end: points),
                      duration: const Duration(milliseconds: 1200),
                      curve: Curves.easeOutCubic,
                      builder: (_, val, __) => Text(
                        '$val',
                        style: TextStyle(
                          fontSize: w * 0.062,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primaryDark,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // ── Badge de niveau façon jeu vidéo : bouclier au-dessus
              // du nom du niveau ──
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LevelShield(level: level, size: w * 0.13),
                  SizedBox(height: w * 0.008),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: w * 0.22),
                    child: Text(
                      level.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: w * 0.026,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        height: 1.15,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          SizedBox(height: w * 0.02),

          // ── Description agrandie : bascule périodiquement
          // (glissement latéral) entre la description du niveau et le
          // message promo d'échange de points ──
          SizedBox(
            height: w * 0.1,
            width: double.infinity,
            child: ClipRect(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                transitionBuilder: (child, animation) => SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
                child: Align(
                  key: ValueKey(_showPromo),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _showPromo ? _promoMessage : level.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: w * 0.033,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                      height: 1.28,
                    ),
                  ),
                ),
              ),
            ),
          ),

          SizedBox(height: w * 0.014),

          // ── Barre de progression vers le niveau suivant ──
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeOutCubic,
            builder: (_, val, __) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    children: [
                      Container(
                        height: w * 0.016,
                        color: AppColors.primary.withOpacity(0.1),
                      ),
                      FractionallySizedBox(
                        widthFactor: val,
                        child: Container(
                          height: w * 0.016,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF9EF5B0), Color(0xFF4CAF50)],
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: w * 0.01),
                Text(
                  level.isMax
                      ? '👑 Niveau maximum atteint'
                      : 'Encore $remaining pts pour le niveau suivant',
                  style: TextStyle(
                    fontSize: w * 0.026,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: w * 0.03),

          // ── CTA pleine largeur "Échanger mes points" — remplace le
          // petit bouton flottant qui chevauchait le contenu. Redirige
          // vers le panier ('/cart') pour utiliser les points.
          SizedBox(
            width: double.infinity,
            height: w * 0.11,
            child: ElevatedButton(
              onPressed: () => context.push('/cart'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.card_giftcard_rounded,
                    color: Colors.white,
                    size: w * 0.042,
                  ),
                  SizedBox(width: w * 0.02),
                  Text(
                    'Échanger mes points',
                    style: TextStyle(
                      fontSize: w * 0.034,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.2,
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

// ─────────────────────────────────────────────────────────────────────────────
//  MENU ITEM
// ─────────────────────────────────────────────────────────────────────────────
class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? badge;
  final Color color;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.04,
          vertical: w * 0.035,
        ),
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
          children: [
            Container(
              width: w * 0.1,
              height: w * 0.1,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: w * 0.05),
            ),
            SizedBox(width: w * 0.035),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: w * 0.037,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (badge != null)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    fontSize: w * 0.028,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: w * 0.035,
              color: AppColors.textLight,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  HORIZONTAL ROW (Historique / Adresses / Suivi)
//  ✏️ Navigation corrigée pour matcher les routes réellement déclarées dans
//  app_routes.dart : '/tracking' n'existe pas (il faut un orderId), donc
//  "Suivi" renvoie vers la liste des commandes où l'utilisateur peut choisir
//  la commande à suivre. '/addresses' est désormais bien enregistrée côté
//  routeur (voir app_routes.dart).
// ─────────────────────────────────────────────────────────────────────────────
class _HorizontalRow extends StatelessWidget {
  final double screenW;

  const _HorizontalRow({required this.screenW});

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.history_rounded, 'Historique', () => context.push('/orders')),
      (
        Icons.location_on_rounded,
        'Adresses',
        () => _showAddressNotice(context), // ← كان context.push('/addresses')
      ),
      (
        Icons.track_changes_rounded,
        'Suivi',
        // Pas de route générique '/tracking' : on passe par la liste des
        // commandes, chaque commande y ouvre son suivi via
        // '/order-tracking/:orderId'.
        () => context.push('/orders'),
      ),
    ];
    final itemW = (screenW - (screenW * 0.08) - 16) / 3;

    return Row(
      children: items.asMap().entries.map((e) {
        final isLast = e.key == items.length - 1;
        return GestureDetector(
          onTap: e.value.$3,
          child: Container(
            width: itemW,
            margin: EdgeInsets.only(right: isLast ? 0 : 8),
            padding: EdgeInsets.symmetric(vertical: screenW * 0.04),
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
              children: [
                Icon(
                  e.value.$1,
                  color: AppColors.primary,
                  size: screenW * 0.06,
                ),
                SizedBox(height: screenW * 0.015),
                Text(
                  e.value.$2,
                  style: TextStyle(
                    fontSize: screenW * 0.03,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SECTION LABEL
// ─────────────────────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: w * 0.04,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  ADDRESS NOTICE — les adresses ne sont pas stockées séparément :
//  elles sont saisies directement au moment de la commande
//  (checkout_screen.dart). Ce dialogue l'explique à l'utilisateur.
// ─────────────────────────────────────────────────────────────
void _showAddressNotice(BuildContext context) {
  showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.35),
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: const _AddressNoticeCard(),
    ),
  );
}

class _AddressNoticeCard extends StatelessWidget {
  const _AddressNoticeCard();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          // ── أوراق أشجار خضراء زخرفية أعلى اليسار ──
          Positioned(
            top: -18,
            left: -18,
            child: Transform.rotate(
              angle: -0.3,
              child: Icon(
                Icons.local_florist_rounded,
                size: 90,
                color: AppColors.primary.withOpacity(0.15),
              ),
            ),
          ),
          Positioned(
            top: 8,
            left: 32,
            child: Transform.rotate(
              angle: 0.4,
              child: Icon(
                Icons.eco_rounded,
                size: 38,
                color: AppColors.primary.withOpacity(0.25),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 42, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.location_on_rounded,
                  color: AppColors.primary,
                  size: 32,
                ),
                const SizedBox(height: 14),
                Text(
                  'Adresse de livraison',
                  style: TextStyle(
                    fontSize: w * 0.045,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Votre adresse de livraison sera précisée directement au moment de votre commande.',
                  style: TextStyle(
                    fontSize: w * 0.035,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Compris',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
