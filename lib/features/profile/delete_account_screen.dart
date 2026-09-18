// lib/features/profile/delete_account_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mrbeldi/core/theme/app_colors.dart';
import 'package:mrbeldi/features/auth/login_screen.dart' show GoogleAuthService;

/// Écran de suppression de compte MrBeldi.
///
/// ⚠️ Ce flux ne supprime PLUS aucune donnée en direct. Il se contente de :
///   1. Vérifier l'identité du compte (Google, si non connecté).
///   2. Informer l'utilisateur de ce qu'il va perdre + lui faire cocher une
///      case de confirmation explicite ("J'ai compris et je souhaite
///      continuer"), comme le fait Google avant de supprimer un compte.
///   3. Vérifier qu'aucune commande n'est en cours de livraison
///      (collection `orders`, champs `userId` + `status`).
///   4. Demander (en option) le motif du départ.
///   5. Écrire une "demande de suppression" dans la collection
///      `deleted_accounts` (avec date de purge légale à J+30), PUIS
///      déconnecter automatiquement l'utilisateur.
///
/// La logique métier (Firestore/Auth) est isolée dans [AccountDeletionService]
/// afin que le widget ne s'occupe que de l'affichage — plus facile à tester
/// et à maintenir, comme le préconisent les guides d'architecture Flutter.
///
/// ✏️ La fonctionnalité d'email de confirmation a été retirée : aucune
/// écriture n'est plus faite dans une collection `mail`, et aucune
/// extension "Trigger Email" n'est requise pour ce flux.
///
/// La suppression réelle des données (Firestore + Firebase Auth) doit être
/// effectuée côté serveur (Cloud Function planifiée) le jour de la purge,
/// en se basant sur les documents `deleted_accounts` dont `status` vaut
/// `pending_purge` et `finalDeletionDate` est atteinte. Si l'utilisateur se
/// reconnecte avant cette date, il suffit de supprimer/mettre à jour son
/// document `deleted_accounts` pour annuler la purge.
///
/// ⚠️ IMPORTANT — Règles de sécurité Firestore requises pour `deleted_accounts`
/// (sans elles, l'écriture ci-dessous échoue avec PERMISSION_DENIED) :
///
/// match /deleted_accounts/{userId} {
///   allow create: if request.auth != null
///                 && request.auth.uid == userId
///                 && request.auth.uid == request.resource.data.userId;
///   allow read: if request.auth != null && request.auth.uid == userId;
///   allow update, delete: if false; // seule une Cloud Function (Admin SDK) peut modifier/supprimer
/// }
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key, AccountDeletionService? service})
      : _service = service;

  final AccountDeletionService? _service;

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

/// Motifs de départ proposés à l'utilisateur (étape optionnelle).
const List<String> kLeavingReasons = [
  'Les prix sont trop élevés',
  "L'application est difficile à utiliser",
  "Problèmes de livraison et d'expédition",
  'J\'ai trouvé une autre application',
  'Raisons de sécurité liées à la confidentialité',
  'Autre raison',
];

const List<String> _frenchMonths = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

/// Libellés des étapes affichées dans la ligne de progression.
const List<String> _stepLabels = [
  'Compte',
  'Confirmation',
  'Motif',
  'Terminé',
];

// ─────────────────────────────────────────────────────────────────────────────
//  IDENTITÉ VISUELLE PARTAGÉE — mêmes dégradés / rayons / ombres que
//  profile_screen.dart, pour que cet écran s'intègre parfaitement au reste
//  de l'application (même famille de police "Cairo", mêmes cartes blanches
//  à liseré vert, mêmes badges circulaires en dégradé).
// ─────────────────────────────────────────────────────────────────────────────
const List<Color> _kBrandGradient = [
  Color(0xFF1F5F3E),
  Color(0xFF2E8B57),
  Color(0xFF3A9E68),
];
const List<Color> _kWarningGradient = [Color(0xFFE85D4A), Color(0xFFC62828)];
const List<Color> _kGoldGradient = [Color(0xFFFFD770), Color(0xFFE8A93A)];

const Duration _kStepTransition = Duration(milliseconds: 280);
const Curve _kStepCurve = Curves.easeOutCubic;

// ─────────────────────────────────────────────────────────────────────────────
//  COUCHE MÉTIER — toute la logique Firestore/Auth vit ici, hors du widget.
//  Cela rend le flux testable unitairement (on peut injecter un faux
//  service dans les tests) et garde le State de l'écran concentré sur
//  l'affichage, comme le recommandent les guides d'architecture Flutter.
// ─────────────────────────────────────────────────────────────────────────────

/// Résultat d'une demande de suppression réussie.
class DeletionRequestResult {
  const DeletionRequestResult({required this.finalDeletionDate});
  final DateTime finalDeletionDate;
}

/// Erreur métier levée quand l'utilisateur a une commande non livrée.
class PendingOrderException implements Exception {
  const PendingOrderException();
}

class AccountDeletionService {
  AccountDeletionService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  User? get currentUser => _auth.currentUser;

  /// Lance le sélecteur de compte Google et vérifie que ce compte existe
  /// bien dans la collection `users`. Déconnecte automatiquement si le
  /// compte Google est valide mais inconnu de MrBeldi.
  ///
  /// Retourne l'utilisateur vérifié, ou `null` si l'utilisateur a annulé
  /// la sélection, ou lève [StateError] si le compte n'est pas un compte
  /// MrBeldi connu.
  Future<User?> verifyGoogleAccount() async {
    final result = await GoogleAuthService.signIn();
    final user = result?.user;
    if (user == null) return null;

    final doc = await _firestore.collection('users').doc(user.uid).get();
    if (!doc.exists) {
      await GoogleAuthService.signOut();
      throw StateError('account_not_found');
    }
    return user;
  }

  Future<void> switchAccount() => GoogleAuthService.signOut();

  /// True s'il existe, dans la collection `orders`, une commande de cet
  /// utilisateur dont le statut n'est pas `delivered`.
  Future<bool> hasPendingOrders(String uid) async {
    final snapshot = await _firestore
        .collection('orders')
        .where('userId', isEqualTo: uid)
        .get();

    for (final doc in snapshot.docs) {
      final status = (doc.data()['status'] as String?)?.toLowerCase();
      if (status != 'delivered') return true;
    }
    return false;
  }

  /// Enregistre la demande de suppression (collection `deleted_accounts`,
  /// purge légale à J+30) puis déconnecte l'utilisateur. Ne supprime
  /// aucune donnée en direct.
  Future<DeletionRequestResult> requestDeletion({
    required User user,
    String? reason,
  }) async {
    if (await hasPendingOrders(user.uid)) {
      throw const PendingOrderException();
    }

    final now = DateTime.now();
    final finalDeletionDate = now.add(const Duration(days: 30));

    await _firestore.collection('deleted_accounts').doc(user.uid).set({
      'userId': user.uid,
      'email': user.email,
      'displayName': user.displayName,
      'reason': reason,
      'requestedAt': FieldValue.serverTimestamp(),
      'finalDeletionDate': Timestamp.fromDate(finalDeletionDate),
      'status': 'pending_purge',
    });

    await GoogleAuthService.signOut();
    return DeletionRequestResult(finalDeletionDate: finalDeletionDate);
  }
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  late final AccountDeletionService _service =
      widget._service ?? AccountDeletionService();

  /// L'utilisateur Firebase confirmé comme éligible à la suppression.
  User? _verifiedUser;

  /// True si l'utilisateur est arrivé sur cet écran déjà connecté.
  late final bool _wasAlreadyLoggedIn;

  bool _verifying = false;

  /// True pendant tout le déroulé de la demande de suppression (du clic
  /// sur "Demander la suppression" jusqu'à l'écran final ou une annulation).
  /// Sert aussi à bloquer la navigation retour pour éviter d'interrompre
  /// une écriture Firestore en cours.
  bool _processing = false;

  /// True une fois la demande de suppression enregistrée dans Firestore
  /// et l'utilisateur déconnecté : affiche l'écran de confirmation finale.
  bool _deletionScheduled = false;
  DateTime? _finalDeletionDate;

  /// Étape courante affichée dans la ligne de progression (index dans
  /// [_stepLabels]).
  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    final current = _service.currentUser;
    _wasAlreadyLoggedIn = current != null;
    _verifiedUser = current;
    _currentStep = _wasAlreadyLoggedIn ? 1 : 0;
  }

  bool get _readyToDelete => _verifiedUser != null;

  // ── Étape 1 : vérification du compte Google (parcours "non connecté") ──
  Future<void> _verifyGoogleAccount() async {
    setState(() => _verifying = true);
    try {
      final user = await _service.verifyGoogleAccount();
      if (!mounted) return;

      if (user == null) {
        _showSnack('Sélection du compte annulée.', isError: true);
        return;
      }

      setState(() {
        _verifiedUser = user;
        _currentStep = 1;
      });
    } on StateError {
      if (mounted) _showAccountNotFoundDialog();
    } catch (_) {
      if (mounted) {
        _showSnack('Erreur de connexion. Veuillez réessayer.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _switchAccount() async {
    await _service.switchAccount();
    if (!mounted) return;
    setState(() {
      _verifiedUser = null;
      _currentStep = 0;
    });
  }

  void _showAccountNotFoundDialog() {
    showDialog(
      context: context,
      builder: (_) => _BrandDialog(
        icon: Icons.person_off_rounded,
        iconGradient: _kWarningGradient,
        title: 'Compte introuvable',
        message:
            "Ce compte Google n'est associé à aucun compte MrBeldi. "
            'Vérifiez que vous avez sélectionné le bon compte, ou essayez-en un autre.',
        actions: [
          _DialogAction(
            label: 'Essayer un autre compte',
            onPressed: () => Navigator.pop(context),
            primary: true,
          ),
        ],
      ),
    );
  }

  // ── Étape 2+ : flux complet de la demande de suppression ────────────────

  /// Orchestre tout le parcours : "ce que vous allez perdre" (avec case à
  /// cocher de confirmation explicite) -> motif de départ (optionnel) ->
  /// enregistrement de la demande + déconnexion. La vérification des
  /// commandes en cours est déléguée au service et gérée via
  /// [PendingOrderException].
  Future<void> _startDeletionFlow() async {
    final user = _verifiedUser!;
    setState(() => _processing = true);
    try {
      // 1. Ce que vous allez perdre + confirmation explicite obligatoire.
      final wantsToContinue = await _showWhatYoullLoseDialog();
      if (wantsToContinue != true || !mounted) return;

      // 2. Motif de départ (optionnel).
      setState(() => _currentStep = 2);
      final reasonResult = await _showReasonForLeavingDialog();
      if (reasonResult == null || !mounted) {
        if (mounted) setState(() => _currentStep = 1);
        return;
      }
      final reason = reasonResult.isEmpty ? null : reasonResult;

      // 3. Enregistrement de la demande + déconnexion automatique.
      HapticFeedback.mediumImpact();
      final result = await _service.requestDeletion(user: user, reason: reason);
      if (!mounted) return;
      setState(() {
        _deletionScheduled = true;
        _finalDeletionDate = result.finalDeletionDate;
        _verifiedUser = null;
        _currentStep = 3;
      });
    } on PendingOrderException {
      if (mounted) {
        setState(() => _currentStep = 1);
        _showPendingOrderDialog();
      }
    } on FirebaseException catch (e) {
      // Erreurs Firestore/Auth typées : on distingue le cas "règles de
      // sécurité" (permission-denied) d'une erreur générique, pour donner
      // un message plus utile et faciliter le diagnostic en prod.
      if (mounted) {
        setState(() => _currentStep = 1);
        _showSnack(
          e.code == 'permission-denied'
              ? "Impossible d'enregistrer la demande (droits insuffisants). "
                  'Veuillez réessayer plus tard ou contacter le support.'
              : 'Une erreur est survenue lors du traitement de votre demande. Veuillez réessayer.',
          isError: true,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _currentStep = 1);
        _showSnack(
          'Une erreur est survenue lors du traitement de votre demande. Veuillez réessayer.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  /// Popup : liste de ce que l'utilisateur va perdre + case à cocher de
  /// confirmation explicite ("J'ai compris…"), à la manière du flux de
  /// suppression de compte Google : le bouton destructeur reste désactivé
  /// tant que la case n'est pas cochée.
  Future<bool?> _showWhatYoullLoseDialog() {
    return showDialog<bool>(
      context: context,
      builder: (_) {
        var acknowledged = false;
        return StatefulBuilder(
          builder: (context, setInnerState) {
            return AlertDialog(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                titlePadding: const EdgeInsets.fromLTRB(22, 24, 22, 4),
                contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
                title: const Text(
                  'Voici ce que vous perdrez en supprimant votre compte',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 6),
                      _buildLossItem('Points de fidélité'),
                      _buildLossItem('Coupons actifs'),
                      _buildLossItem('Historique des commandes et factures'),
                      _buildLossItem('Adresses de livraison enregistrées'),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.primary.withOpacity(0.18)),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded, size: 18, color: AppColors.primary),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Certaines données liées à des factures fiscales peuvent '
                                'être conservées sous forme archivée pendant la durée '
                                'imposée par la réglementation comptable et légale, sans '
                                'être visibles ni utilisables depuis votre compte.',
                                style: TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => setInnerState(() => acknowledged = !acknowledged),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: acknowledged
                                  ? AppColors.error.withOpacity(0.4)
                                  : AppColors.border,
                            ),
                            color: acknowledged
                                ? AppColors.error.withOpacity(0.05)
                                : Colors.transparent,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Checkbox(
                                value: acknowledged,
                                activeColor: AppColors.error,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                onChanged: (v) => setInnerState(() => acknowledged = v ?? false),
                              ),
                              const Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(top: 12),
                                  child: Text(
                                    "Je comprends que cette action supprimera définitivement "
                                    "mes données et qu'elle est irréversible après 30 jours.",
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
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
                actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                actionsAlignment: MainAxisAlignment.spaceBetween,
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text(
                      'Annuler',
                      style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700, color: AppColors.textLight),
                    ),
                  ),
                  TextButton(
                    onPressed: acknowledged ? () => Navigator.pop(context, true) : null,
                    child: Text(
                      'Continuer la suppression',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        color: acknowledged ? AppColors.error : AppColors.textLight.withOpacity(0.5),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
    );
  }

  Widget _buildLossItem(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.close_rounded, size: 14, color: AppColors.error),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  void _showPendingOrderDialog() {
    showDialog(
      context: context,
      builder: (_) => _BrandDialog(
        icon: Icons.local_shipping_rounded,
        iconGradient: _kWarningGradient,
        title: 'Suppression impossible pour le moment',
        message:
            "Vous avez une commande qui n'a pas encore été livrée. Veuillez "
            'attendre la livraison de votre commande avant de faire une '
            'demande de suppression de compte.',
        actions: [
          _DialogAction(
            label: "D'accord",
            onPressed: () => Navigator.pop(context),
            primary: true,
          ),
        ],
      ),
    );
  }

  /// Popup : motif de départ, optionnel — choix unique parmi
  /// [kLeavingReasons] (avec champ libre pour "Autre raison"), ou aucune
  /// sélection. Retourne :
  /// - `null` si l'utilisateur annule tout le flux de suppression,
  /// - `''` (chaîne vide) si l'utilisateur passe cette étape sans motif,
  /// - le motif choisi sinon.
  Future<String?> _showReasonForLeavingDialog() {
    String? selected;
    final otherController = TextEditingController();

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isOther = selected == kLeavingReasons.last;
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              titlePadding: const EdgeInsets.fromLTRB(22, 24, 22, 4),
              contentPadding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
              title: const Text(
                'Pourquoi souhaitez-vous nous quitter ?',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6, left: 4),
                      child: Text(
                        'Cette étape est facultative.',
                        style: TextStyle(fontSize: 12, color: AppColors.textLight),
                      ),
                    ),
                    ...kLeavingReasons.map(
                      (reason) => RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: reason,
                        groupValue: selected,
                        activeColor: AppColors.primary,
                        title: Text(
                          reason,
                          style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
                        ),
                        onChanged: (value) => setDialogState(() => selected = value),
                      ),
                    ),
                    if (isOther) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: otherController,
                        maxLines: 2,
                        style: const TextStyle(fontSize: 13.5),
                        decoration: InputDecoration(
                          hintText: 'Écrivez la raison ici (facultatif)',
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              actionsAlignment: MainAxisAlignment.spaceBetween,
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, null),
                  child: const Text(
                    'Annuler la suppression',
                    style: TextStyle(fontFamily: 'Cairo', color: AppColors.textLight, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    String finalReason = '';
                    if (selected != null) {
                      finalReason = isOther && otherController.text.trim().isNotEmpty
                          ? 'Autre raison : ${otherController.text.trim()}'
                          : selected!;
                    }
                    Navigator.pop(dialogContext, finalReason);
                  },
                  child: const Text(
                    'Continuer',
                    style: TextStyle(fontFamily: 'Cairo', color: AppColors.primary, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatFrenchDate(DateTime date) {
    return '${date.day} ${_frenchMonths[date.month - 1]} ${date.year}';
  }

  void _showSnack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(msg, style: const TextStyle(fontFamily: 'Cairo'))),
          ],
        ),
        backgroundColor: isError ? AppColors.error : AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ── UI ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Empêche une sortie accidentelle de l'écran pendant qu'une écriture
      // Firestore est en cours — comportement attendu d'un flux "sensible"
      // (même logique que les écrans de paiement de Google Play).
      canPop: !_processing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _processing) {
          _showSnack('Veuillez patienter, votre demande est en cours de traitement.', isError: false);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          automaticallyImplyLeading: !_deletionScheduled,
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
          title: const Text(
            'Supprimer mon compte',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildProgressBar(),
                const SizedBox(height: 24),
                AnimatedSwitcher(
                  duration: _kStepTransition,
                  switchInCurve: _kStepCurve,
                  switchOutCurve: _kStepCurve,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.03),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: _deletionScheduled
                      ? _buildSuccessStep(key: const ValueKey('success'))
                      : _readyToDelete
                          ? _buildConfirmStep(key: const ValueKey('confirm'))
                          : _buildVerifyStep(key: const ValueKey('verify')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Ligne de progression indiquant l'étape courante du parcours.
  Widget _buildProgressBar() {
    return Row(
      children: List.generate(_stepLabels.length, (index) {
        final isCompleted = index < _currentStep;
        final isActive = index == _currentStep;
        final isLast = index == _stepLabels.length - 1;
        return Expanded(
          child: Row(
            children: [
              Column(
                children: [
                  AnimatedContainer(
                    duration: _kStepTransition,
                    curve: _kStepCurve,
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: (isCompleted || isActive)
                          ? const LinearGradient(colors: _kBrandGradient)
                          : null,
                      color: (isCompleted || isActive)
                          ? null
                          : AppColors.textLight.withOpacity(0.15),
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                    child: isCompleted
                        ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                        : Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: isActive ? Colors.white : AppColors.textLight,
                            ),
                          ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _stepLabels[index],
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10.5,
                      fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                      color: isActive ? AppColors.primary : AppColors.textLight,
                    ),
                  ),
                ],
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 18),
                    color: isCompleted ? AppColors.primary : AppColors.textLight.withOpacity(0.2),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  // Carte de base commune à toutes les étapes.
  Widget _stepCard({required Key key, required Widget child}) {
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  // Étape affichée uniquement si l'utilisateur n'est pas connecté.
  Widget _buildVerifyStep({Key? key}) {
    return _stepCard(
      key: key!,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _GradientIconBadge(icon: Icons.person_search_rounded, colors: _kBrandGradient),
          const SizedBox(height: 18),
          const Text(
            'Vérifiez votre compte',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            "Pour supprimer un compte MrBeldi, vous devez d'abord "
            'sélectionner le compte Google associé. Vous pourrez ensuite '
            'confirmer la suppression définitive de vos données.',
            style: TextStyle(fontSize: 14, height: 1.6, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _verifying ? null : _verifyGoogleAccount,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                disabledBackgroundColor: AppColors.error.withOpacity(0.6),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _verifying
                    ? const SizedBox(
                        key: ValueKey('loading'),
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text(
                        'Supprimer mon compte MrBeldi',
                        key: ValueKey('label'),
                        style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800, color: Colors.white),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: AppColors.primary),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Vous n'avez pas besoin d'être connecté à l'application "
                    'pour effectuer cette demande.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Étape de confirmation : déclenche le flux complet de demande de
  // suppression (perte de données -> motif -> enregistrement).
  Widget _buildConfirmStep({Key? key}) {
    final user = _verifiedUser!;
    return _stepCard(
      key: key!,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_wasAlreadyLoggedIn) _buildVerifiedAccountBanner(user),
          if (!_wasAlreadyLoggedIn) const SizedBox(height: 20),
          const _GradientIconBadge(icon: Icons.warning_rounded, colors: _kWarningGradient),
          const SizedBox(height: 18),
          const Text(
            'Que se passe-t-il quand vous supprimez votre compte ?',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          _buildConsequenceItem('Vos données personnelles (nom, email, adresses) seront définitivement supprimées.'),
          _buildConsequenceItem("Votre historique de commandes ne sera plus accessible depuis l'application."),
          _buildConsequenceItem('Vos points de fidélité seront perdus.'),
          _buildConsequenceItem('Cette action est irréversible après le délai de 30 jours.'),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _processing ? null : _startDeletionFlow,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                disabledBackgroundColor: AppColors.error.withOpacity(0.6),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _processing
                    ? const SizedBox(
                        key: ValueKey('loading'),
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text(
                        'Demander la suppression',
                        key: ValueKey('label'),
                        style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800, color: Colors.white),
                      ),
              ),
            ),
          ),
          if (!_wasAlreadyLoggedIn) ...[
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: _processing ? null : _switchAccount,
                child: const Text(
                  "Ce n'est pas votre compte ? Changer de compte",
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 12.5, color: AppColors.textLight),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConsequenceItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 5, color: AppColors.error),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13.5, height: 1.6, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifiedAccountBanner(User user) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.2), blurRadius: 6)],
            ),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.primary.withOpacity(0.15),
              backgroundImage: user.photoURL != null ? NetworkImage(user.photoURL!) : null,
              child: user.photoURL == null
                  ? const Icon(Icons.person, color: AppColors.primary)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'COMPTE VÉRIFIÉ',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  user.email ?? user.displayName ?? user.uid,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 22),
        ],
      ),
    );
  }

  // Écran final : demande enregistrée, utilisateur déjà déconnecté. La
  // confirmation est purement in-app (aucun email envoyé).
  Widget _buildSuccessStep({Key? key}) {
    final finalDate = _finalDeletionDate!;
    final daysLeft = finalDate.difference(DateTime.now()).inDays.clamp(0, 30);
    return _stepCard(
      key: key!,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _GradientIconBadge(icon: Icons.check_rounded, colors: _kBrandGradient),
          const SizedBox(height: 18),
          const Text(
            'Suppression programmée',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Votre demande de suppression de compte a bien été enregistrée.',
            style: TextStyle(fontSize: 14, height: 1.6, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary.withOpacity(0.10), AppColors.primary.withOpacity(0.04)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withOpacity(0.18)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'La suppression définitive aura lieu automatiquement le :',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 6),
                Text(
                  _formatFrenchDate(finalDate),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Date de suppression définitive',
                  style: TextStyle(fontSize: 11, color: AppColors.textLight),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: _kGoldGradient),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$daysLeft jours restants',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF3D2B00),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.textLight.withOpacity(0.2)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.replay_rounded, size: 18, color: AppColors.textSecondary),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Vous avez changé d'avis ? Vous pouvez annuler la suppression "
                    'à tout moment durant cette période, simplement en vous '
                    'reconnectant à votre compte.',
                    style: TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: () => context.go('/login'), // ajuster selon le nom réel de la route
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text(
                "J'ai compris",
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  BADGE CIRCULAIRE EN DÉGRADÉ — même codage visuel que les boucliers de
//  niveau et le badge pièce de profile_screen.dart : cercle en dégradé,
//  ombre colorée, icône blanche centrée.
// ─────────────────────────────────────────────────────────────────────────────
class _GradientIconBadge extends StatelessWidget {
  final IconData icon;
  final List<Color> colors;
  final double size;

  const _GradientIconBadge({required this.icon, required this.colors, this.size = 60});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [
          BoxShadow(
            color: colors.last.withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.48),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  DIALOGUE DE MARQUE — remplace les AlertDialog génériques par un style
//  cohérent avec le reste de l'app (badge en dégradé, typo Cairo, bouton
//  d'action pleine largeur ou en pilule).
// ─────────────────────────────────────────────────────────────────────────────
class _DialogAction {
  final String label;
  final VoidCallback onPressed;
  final bool primary;

  const _DialogAction({required this.label, required this.onPressed, this.primary = false});
}

class _BrandDialog extends StatelessWidget {
  final IconData icon;
  final List<Color> iconGradient;
  final String title;
  final String message;
  final List<_DialogAction> actions;

  const _BrandDialog({
    required this.icon,
    required this.iconGradient,
    required this.title,
    required this.message,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 24, offset: const Offset(0, 10)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _GradientIconBadge(icon: icon, colors: iconGradient, size: 52),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(fontSize: 13.5, height: 1.6, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 22),
            ...actions.map(
              (a) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: a.primary
                      ? ElevatedButton(
                          onPressed: a.onPressed,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            a.label,
                            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                        )
                      : TextButton(
                          onPressed: a.onPressed,
                          child: Text(
                            a.label,
                            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700, color: AppColors.textLight),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}