// lib/features/auth/login_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:go_router/go_router.dart';
import 'package:mrbeldi/core/theme/app_colors.dart';
import 'package:mrbeldi/core/services/local_cart_service.dart';
import 'package:mrbeldi/routes/app_routes.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
//  Google Auth Service  –  google_sign_in 6.x
// ─────────────────────────────────────────────────────────────────────────────
class GoogleAuthService {
  static final _auth = FirebaseAuth.instance;
  static final _googleSignIn = GoogleSignIn(
    // iOS يحتاج clientId الخاص بتطبيق iOS (من GoogleService-Info.plist)
    clientId: defaultTargetPlatform == TargetPlatform.iOS
        ? '913108065792-dmm6j3j1sh0dt5j02g80m9c93hqa0pfn.apps.googleusercontent.com'
        : null,
    serverClientId:
        '913108065792-e1l84omkct8d8rrighkeud3jruv9krpc.apps.googleusercontent.com',
    scopes: ['email', 'profile'],
  );

  static Future<UserCredential?> signIn() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      return await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      // ✅ CORRECTIF : si le ID token Google est "stale" ou invalide,
      // on force une déconnexion locale pour que la prochaine tentative
      // de l'utilisateur récupère un token frais depuis Google, au lieu
      // de rejouer indéfiniment le même credential périmé.
      if (e.code == 'invalid-credential') {
        await _googleSignIn.signOut();
      }
      debugPrint('Google Sign-In Error: $e');
      return null;
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
      return null;
    }
  }

  static Future<void> signOut() async {
    await Future.wait([_auth.signOut(), _googleSignIn.signOut()]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  LOGIN SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  final String redirectTo;
  const LoginScreen({super.key, this.redirectTo = '/profile'});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = false;

  // entrance animation
  late final AnimationController _ctrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();

    // Si l'utilisateur est déjà connecté, on le redirige directement.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (FirebaseAuth.instance.currentUser != null) {
        context.go(widget.redirectTo);
      }
    });

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // ── Google Sign-In ────────────────────────────────────────────────────────
  //
  // ✅ AJOUT : avant toute écriture dans users/{uid}, on vérifie si ce
  // compte figure dans deleted_accounts/{uid} (programmé pour suppression
  // via l'app admin). Si oui, on affiche une boîte de dialogue proposant
  // à l'utilisateur soit de poursuivre la connexion (auquel cas son uid
  // est enregistré dans cancelled_deletions, pour que l'admin sache que
  // l'utilisateur est revenu sur sa décision), soit de confirmer la
  // suppression (auquel cas on le déconnecte simplement — la suppression
  // effective reste gérée côté admin, comme convenu).
  Future<void> _signInWithGoogle() async {
    setState(() => _loading = true);
    try {
      final result = await GoogleAuthService.signIn();
      if (!mounted) return;

      if (result != null && result.user != null) {
        final user = result.user!;

        // Étape 1 : vérifier si ce compte est programmé pour suppression,
        // AVANT de créer/toucher quoi que ce soit dans users/{uid}.
        final isScheduledForDeletion = await _checkScheduledForDeletion(
          user.uid,
        );
        if (!mounted) return;

        if (isScheduledForDeletion) {
          final wantsToContinue = await _showDeletionScheduledDialog();
          if (!mounted) return;

          if (wantsToContinue != true) {
            // L'utilisateur confirme la suppression : on ne le laisse pas
            // entrer dans l'app. On se contente de le déconnecter ; le
            // nettoyage de deleted_accounts est géré par l'app admin.
            await GoogleAuthService.signOut();
            return;
          }

          // L'utilisateur choisit de revenir sur la suppression et de
          // poursuivre la connexion : on supprime son document de
          // deleted_accounts pour qu'il ne soit plus considéré comme
          // programmé pour suppression.
          await _removeFromDeletedAccounts(user.uid);
          if (!mounted) return;
        }

        // Séquence explicite (sequential) : on s'assure d'abord que
        // users/{uid} existe (ou on le laisse tel quel s'il existe déjà),
        // puis on lance la synchronisation du panier local. Cela évite
        // tout conflit de timing entre deux écritures indépendantes
        // survenant presque au même moment.
        await _ensureUserDocument(user);
        if (!mounted) return;

        await LocalCartService.syncToFirestore(user.uid);
        if (!mounted) return;

        context.go(widget.redirectTo);
      } else {
        _showError('Connexion annulée. Veuillez réessayer.');
      }
    } catch (e) {
      _showError('Erreur de connexion. Veuillez réessayer.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Vérifie deleted_accounts/{uid} ────────────────────────────────────────
  Future<bool> _checkScheduledForDeletion(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('deleted_accounts')
          .doc(uid)
          .get();
      return doc.exists;
    } catch (e) {
      debugPrint('⚠️ Erreur de vérification deleted_accounts/$uid: $e');
      // Un échec technique (réseau, etc.) ne doit pas bloquer une
      // connexion normale : on considère le compte comme non programmé.
      return false;
    }
  }

  // ── Supprime le document deleted_accounts/{uid} ───────────────────────────
  // Appelé quand l'utilisateur choisit de revenir sur la suppression et de
  // poursuivre sa connexion : son compte ne doit plus être considéré comme
  // programmé pour suppression.
  Future<void> _removeFromDeletedAccounts(String uid) async {
    try {
      await FirebaseFirestore.instance
          .collection('deleted_accounts')
          .doc(uid)
          .delete();
    } catch (e) {
      debugPrint('⚠️ Erreur suppression deleted_accounts/$uid: $e');
      // Si la suppression échoue (ex. permission-denied), on ne bloque
      // pas la connexion, mais le compte restera visible comme "programmé
      // pour suppression" lors de la prochaine connexion.
    }
  }

  // ── Boîte de dialogue : compte programmé pour suppression ────────────────
  Future<bool?> _showDeletionScheduledDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Compte programmé pour suppression',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'Ce compte est actuellement programmé pour suppression. '
          'Souhaitez-vous annuler la suppression et poursuivre la connexion, '
          'ou confirmer la suppression ?',
          style: TextStyle(fontFamily: 'Cairo', height: 1.5),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Confirmer la suppression',
              style: TextStyle(color: AppColors.error, fontFamily: 'Cairo'),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Poursuivre la connexion',
              style: TextStyle(color: Colors.white, fontFamily: 'Cairo'),
            ),
          ),
        ],
      ),
    );
  }

  // ── Crée le document users/{uid} s'il n'existe pas encore ────────────────
  //
  // ✅ CORRECTIF (permission-denied permanent) : la version précédente
  // tentait, pour un document déjà existant, un `update` qui ajoutait
  // les champs manquants (`userId`, `hasUnlockedTree`, etc.). Or les
  // security rules n'autorisent l'`update` de `users/{uid}` que sur un
  // sous-ensemble strict de champs :
  //
  //   diffKeys().hasOnly(['points', 'negativePoints', 'lastDeliveryAddress'])
  //
  // Toute tentative d'ajouter `userId` ou `hasUnlockedTree` via update
  // est donc rejetée en PERMISSION_DENIED — et ce de façon permanente,
  // pas à cause d'un délai de propagation (d'où l'échec répété même
  // après plusieurs retries dans les logs).
  //
  // Solution retenue (la plus sûre, sans toucher aux security rules) :
  // on ne tente JAMAIS d'update sur un document existant depuis le
  // client. On se contente de :
  //   - `create` si le document n'existe pas encore (seule opération
  //     que les rules autorisent explicitement pour un nouvel uid, et
  //     seulement avec points/negativePoints à 0) ;
  //   - ne rien écrire si le document existe déjà — d'éventuels champs
  //     manquants (comptes très anciens) doivent être traités avec une
  //     valeur par défaut côté Dart au moment de la lecture, jamais
  //     réécrits côté serveur depuis le client.
  //
  // Si un jour il faut réellement backfill des champs manquants sur
  // d'anciens comptes, ça doit passer par une Cloud Function (Admin
  // SDK, qui contourne les security rules), pas par le client.
  //
  // On force aussi un refresh du ID token (`getIdToken(true)`) avant
  // la création, pour éviter un rejet dû au léger délai de propagation
  // de `request.auth` juste après signInWithCredential, avec un court
  // retry en filet de sécurité.
  Future<void> _ensureUserDocument(User? user, {int retries = 2}) async {
    if (user == null) return;

    // 🔑 force le refresh du token avant toute écriture sensible.
    try {
      await user.getIdToken(true);
    } catch (_) {
      // pas bloquant : on retente l'écriture ci-dessous quand même.
    }

    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        final userRef = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid);
        final snapshot = await userRef.get();

        if (!snapshot.exists) {
          // ✅ Première ouverture de compte : create autorisé par les
          // rules tant que points == 0 et negativePoints == 0.
          await userRef.set({
            'userId': user.uid,
            'email': user.email,
            'displayName': user.displayName,
            'photoUrl': user.photoURL,
            'points': 0,
            'negativePoints': 0,
            'hasUnlockedTree': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
        // ⚠️ Si le document existe déjà, on ne le touche pas ici.
        // Les champs éventuellement manquants sont gérés en mémoire
        // côté UI (valeurs par défaut à la lecture), pas réécrits.
        return; // opération terminée (create ou no-op), on sort
      } catch (e) {
        if (attempt == retries) {
          debugPrint('⚠️ Échec de création du document users/${user.uid}: $e');
          return;
        }
        await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: size.height - 100),
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(height: size.height * 0.07),

                      // ── Logo ──────────────────────────────────────────
                      _buildLogo(),

                      SizedBox(height: size.height * 0.04),

                      // ── Title ─────────────────────────────────────────
                      const Text(
                        'Bienvenue sur MrBeldi',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                          height: 1.2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Des produits frais et naturels\ndirectement du terroir marocain 🇲🇦',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      SizedBox(height: size.height * 0.05),

                      // ── Features ──────────────────────────────────────
                      _buildFeatures(),

                      SizedBox(height: size.height * 0.05),

                      // ── Google button ─────────────────────────────────
                      _buildGoogleButton(),

                      const SizedBox(height: 16),

                      // ── Divider ───────────────────────────────────────
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'ou',
                              style: TextStyle(
                                color: AppColors.textLight,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // ── Guest button ──────────────────────────────────
                      _buildGuestButton(),

                      const SizedBox(height: 24),

                      // ── Terms (avec lien cliquable vers la politique
                      // de confidentialité, qui s'ouvre en écran séparé) ─
                      _buildTermsText(context),

                      const SizedBox(height: 10),

                      // ── Lien discret vers la suppression de compte
                      // (accessible même sans connexion) ────────────────
                      _buildDeleteAccountLink(context),

                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Logo widget ───────────────────────────────────────────────────────────
  Widget _buildLogo() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // outer glow
        Container(
          width: 130,
          height: 130,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary.withOpacity(0.08),
          ),
        ),
        // inner circle
        Container(
          width: 105,
          height: 105,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.primaryDark],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Center(
            child: Text('🌿', style: TextStyle(fontSize: 50)),
          ),
        ),
        // iFarm label
        Positioned(
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primaryDark,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryDark.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Text(
              'MrBeldi',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Features row ──────────────────────────────────────────────────────────
  Widget _buildFeatures() {
    const items = [
      ('🌱', 'Bio & Local'),
      ('🚚', 'Livraison 24h'),
      ('✅', 'Certifié ONSSA'),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: items.map((item) {
        return Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.09),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(item.$1, style: const TextStyle(fontSize: 26)),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.$2,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  // ── Google Sign-In button ─────────────────────────────────────────────────
  Widget _buildGoogleButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _loading ? null : _signInWithGoogle,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          disabledBackgroundColor: Colors.white,
          elevation: 2,
          shadowColor: Colors.black.withOpacity(0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border),
          ),
        ),
        child: _loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.primary,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Google "G" logo — pas besoin d'asset
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Center(
                      child: Text(
                        'G',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF4285F4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Continuer avec Google',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ── Guest button ──────────────────────────────────────────────────────────
  Widget _buildGuestButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: _loading ? null : () => context.go('/home'),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: const Text(
          'Continuer en tant qu\'invité',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  // ── Terms + lien "Politique de confidentialité" ─────────────────────────
  // Ouvre PrivacyPolicyScreen en écran séparé via context.push (garde le
  // login screen dans la pile pour pouvoir revenir en arrière).
  Widget _buildTermsText(BuildContext context) {
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: const TextStyle(
          fontSize: 11,
          color: AppColors.textLight,
          height: 1.5,
        ),
        children: [
          const TextSpan(
            text:
                'En continuant, vous acceptez nos Conditions d\'utilisation '
                'et notre ',
          ),
          TextSpan(
            text: 'Politique de confidentialité',
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () => context.push('/privacy-policy'),
          ),
          const TextSpan(text: '.'),
        ],
      ),
    );
  }

  // ── Lien "Supprimer mon compte" ──────────────────────────────────────────
  // Discret par design (pas un bouton principal), mais toujours accessible,
  // y compris sans connexion, conformément aux exigences des stores
  // (Google Play / App Store) concernant la suppression de compte.
  Widget _buildDeleteAccountLink(BuildContext context) {
    return TextButton(
      onPressed: () => context.push(Routes.deleteAccount),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textLight,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Text(
        'Supprimer mon compte',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          color: AppColors.textLight,
          decoration: TextDecoration.underline,
          decorationColor: AppColors.textLight,
        ),
      ),
    );
  }
}
