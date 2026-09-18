// lib/features/profile/privacy_policy_screen.dart
import 'package:flutter/material.dart';
import 'package:mrbeldi/core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  PRIVACY POLICY SCREEN
//  Écran séparé affichant la politique de confidentialité en français et
//  en anglais (bouton de bascule dans l'AppBar), accessible depuis
//  login_screen.dart via '/privacy-policy'.
// ─────────────────────────────────────────────────────────────────────────────
class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  // true = French, false = English
  bool _isFrench = true;

  static const String _privacyTextFr =
      "Date d'effet : 13/08/2026\n"
      "Dernière mise à jour : 13/08/2026\n\n"
      "MrBeldi est une application d'agriculture biologique qui permet aux "
      "clients au Maroc de découvrir et d'acheter des produits biologiques "
      "cultivés localement. Cette politique de confidentialité explique "
      "comment nous collectons, utilisons, stockons, partageons et "
      "protégeons vos informations — y compris les données utilisateur "
      "Google — lorsque vous utilisez l'application mobile et le site web "
      "MrBeldi (le « Service »), exploité par GoDragon, LTD, société "
      "enregistrée au Maroc au 22, Nouaceur, Casablanca, 27182, Maroc.\n\n"
      "Cette politique s'applique à tous les utilisateurs de MrBeldi et est "
      "disponible à tout moment depuis le pied de page de votre profil et "
      "dans l'écran Paramètres > Confidentialité de l'application.\n\n"
      "Si vous n'acceptez pas cette politique de confidentialité, veuillez "
      "ne pas utiliser le Service.\n\n"
      "1. Informations que nous collectons\n\n"
      "1.1 Informations que vous fournissez directement\n"
      "MrBeldi n'utilise pas de mot de passe. La création de compte et la "
      "connexion se font exclusivement via Google Sign-In. Nous "
      "collectons également :\n"
      "• Informations de profil : numéro de téléphone (si fourni), "
      "adresse(s) de livraison, photo de profil (si vous choisissez d'en "
      "ajouter une)\n"
      "• Informations de transaction : confirmation de commandes "
      "(paiement à la livraison)\n"
      "• Communications : demandes d'assistance, avis et évaluations que "
      "vous soumettez pour des produits ou producteurs\n\n"
      "1.2 Informations collectées automatiquement\n"
      "• Informations sur l'appareil : type d'appareil, système "
      "d'exploitation, identifiants uniques, informations sur le réseau "
      "mobile\n"
      "• Données de localisation approximative ou précise (uniquement "
      "avec votre autorisation), utilisées pour afficher les fermes, "
      "coopératives et options de livraison à proximité\n\n"
      "1.3 Données utilisateur Google\n"
      "MrBeldi utilise Google Sign-In comme unique méthode de création de "
      "compte et d'authentification — il n'existe pas de mot de passe "
      "MrBeldi séparé. Lors de votre connexion, nous accédons aux données "
      "utilisateur Google suivantes, strictement limitées à ce qui est "
      "nécessaire pour fournir le Service :\n\n"
      "• Adresse e-mail de votre compte Google (scopes openid, "
      ".../userinfo.email) — pour créer et authentifier votre compte "
      "client MrBeldi, vous identifier entre vos sessions/appareils, et "
      "vous envoyer des notifications transactionnelles (confirmations de "
      "commande, mises à jour de livraison)\n"
      "• Votre nom et votre photo de profil (scope .../userinfo.profile) "
      "— pour compléter votre profil client MrBeldi et personnaliser "
      "votre expérience dans l'application\n\n"
      "MrBeldi ne demande pas l'accès à Gmail, Google Drive, Google "
      "Agenda, Google Contacts, ni à aucun autre service ou scope Google "
      "au-delà de la simple connexion. Nous ne demandons ni n'accédons à "
      "aucune donnée utilisateur Google au-delà de celles listées "
      "ci-dessus, à moins que cette politique ne soit préalablement mise "
      "à jour pour le préciser et que vous n'accordiez séparément cette "
      "autorisation supplémentaire.\n\n"
      "2. Comment nous utilisons vos informations (y compris les données "
      "Google)\n\n"
      "Nous utilisons les informations décrites ci-dessus, y compris les "
      "données utilisateur Google, uniquement pour :\n"
      "1. Créer, authentifier et sécuriser votre compte client MrBeldi "
      "via Google Sign-In\n"
      "2. Fournir les fonctionnalités principales du marché — parcourir, "
      "commander et recevoir la livraison de produits biologiques issus "
      "de producteurs locaux marocains\n"
      "3. Personnaliser votre expérience (ex. afficher les produits "
      "biologiques à proximité, recommandations pertinentes)\n"
      "4. Communiquer avec vous concernant votre compte, vos commandes et "
      "vos demandes d'assistance\n"
      "5. Maintenir la sécurité et l'intégrité du Service, y compris la "
      "prévention de la fraude et la détection des abus\n"
      "6. Améliorer et dépanner le Service (ex. analyser les rapports de "
      "plantage, les tendances d'utilisation)\n"
      "7. Respecter les obligations légales marocaines et internationales "
      "applicables\n\n"
      "Nous n'utilisons pas les données utilisateur Google pour diffuser "
      "des publicités, et nous ne les utilisons pour aucune finalité sans "
      "rapport avec la fourniture ou l'amélioration des fonctionnalités "
      "principales de MrBeldi. Nous ne vendons pas les données "
      "utilisateur Google.\n\n"
      "Les données utilisateur Google ne sont jamais utilisées pour "
      "entraîner des modèles d'IA/apprentissage automatique généralisés "
      "qui ne sont pas directement utilisés pour fournir ou améliorer les "
      "fonctionnalités destinées aux utilisateurs de MrBeldi, "
      "conformément à la politique Google API Services User Data Policy, "
      "y compris les exigences de Limited Use.\n\n"
      "3. Comment nous partageons, transférons ou divulguons vos "
      "informations\n\n"
      "Nous ne vendons pas vos données personnelles, y compris les "
      "données utilisateur Google. Nous partageons des informations "
      "uniquement dans les cas limités suivants :\n\n"
      "• Producteurs et partenaires de livraison : pour exécuter votre "
      "commande, nous partageons le minimum d'informations nécessaires "
      "(ex. votre nom, adresse de livraison et détails de la commande) "
      "avec le producteur/la coopérative locale et le partenaire de "
      "livraison concernés. Les agriculteurs et coopératives ne sont pas "
      "utilisateurs de l'application MrBeldi et n'ont pas accès à vos "
      "données Google.\n"
      "• Prestataires de services : nous partageons des données avec des "
      "fournisseurs tiers vérifiés qui exécutent des services en notre "
      "nom, notamment l'hébergement/l'infrastructure cloud (ex. Google "
      "Cloud Platform / AWS), l'envoi de SMS/e-mails, et les fournisseurs "
      "d'analyse/de rapports de plantage (ex. Firebase).";

  static const String _privacyTextEn =
      "Effective Date: 13/08/2026\n"
      "Last Updated: 13/08/2026\n\n"
      "MrBeldi is an organic agriculture application that lets clients in "
      "Morocco discover and purchase locally grown organic products. This "
      "Privacy Policy explains how we collect, use, store, share, and "
      "protect information — including Google user data — when you use "
      "the MrBeldi mobile application and website (collectively, the "
      "\"Service\"), operated by GoDragon, LTD, a company registered in "
      "Morocco at 22, Nouaceur, Casablanca, 27182, Morocco.\n\n"
      "This policy applies to all users of MrBeldi and is available at "
      "all times from our profile page footer and within the app's "
      "Settings > Privacy screen.\n\n"
      "If you do not agree with this Privacy Policy, please do not use "
      "the Service.\n\n"
      "1. Information We Collect\n\n"
      "1.1 Information You Provide Directly\n"
      "MrBeldi does not use passwords. Account creation and login are "
      "handled exclusively through Google Sign-In. We additionally "
      "collect:\n"
      "• Profile information: phone number (if provided), delivery "
      "address(es), profile photo (if you choose to add one)\n"
      "• Transaction information: order confirmations (Cash on delivery)\n"
      "• Communications: support requests, reviews, and ratings you "
      "submit for products or producers\n\n"
      "1.2 Information Collected Automatically\n"
      "• Device information: device type, operating system, unique "
      "device identifiers, mobile network information\n"
      "• Approximate or precise location data (only with your "
      "permission), used to show nearby farms, cooperatives, and "
      "delivery options\n\n"
      "1.3 Google User Data\n"
      "MrBeldi uses Google Sign-In as the sole method of account creation "
      "and authentication — there is no separate MrBeldi password. When "
      "you sign in, we access the following Google user data, limited "
      "strictly to what is necessary to provide the Service:\n\n"
      "• Your Google account email address (scopes openid, "
      ".../userinfo.email) — to create and authenticate your MrBeldi "
      "client account, identify you across sessions/devices, and send "
      "you transactional notifications (order confirmations, delivery "
      "updates)\n"
      "• Your name and profile picture (scope .../userinfo.profile) — to "
      "populate your MrBeldi client profile and personalize your in-app "
      "experience\n\n"
      "MrBeldi does not request access to Gmail, Google Drive, Google "
      "Calendar, Google Contacts, or any other Google service or scope "
      "beyond basic Sign-In. We do not request or access any Google user "
      "data beyond what is listed above unless this Policy is first "
      "updated to disclose it, and unless you separately grant that "
      "additional permission.\n\n"
      "2. How We Use Your Information (Including Google User Data)\n\n"
      "We use the information described above, including Google user "
      "data, solely to:\n"
      "1. Create, authenticate, and secure your MrBeldi client account "
      "via Google Sign-In\n"
      "2. Provide core marketplace functionality — letting you browse, "
      "order, and receive delivery of organic products sourced from "
      "local Moroccan producers\n"
      "3. Personalize your experience (e.g., showing nearby organic "
      "products, relevant recommendations)\n"
      "4. Communicate with you about your account, orders, and customer "
      "support requests\n"
      "5. Maintain the security and integrity of the Service, including "
      "fraud prevention and abuse detection\n"
      "6. Improve and troubleshoot the Service (e.g., analyzing crash "
      "reports, usage trends)\n"
      "7. Comply with applicable Moroccan and international legal "
      "obligations\n\n"
      "We do not use Google user data for serving advertisements, and we "
      "do not use Google user data for any purpose unrelated to "
      "providing or improving MrBeldi's core functionality. We do not "
      "sell Google user data.\n\n"
      "Google user data is never used to train generalized AI/ML models "
      "that are not directly used to provide or improve MrBeldi's "
      "user-facing features, in accordance with Google API Services User "
      "Data Policy, including the Limited Use requirements.\n\n"
      "3. How We Share, Transfer, or Disclose Information\n\n"
      "We do not sell your personal data, including Google user data. We "
      "share information only in the following limited circumstances:\n\n"
      "• Producers and delivery partners: To fulfill your order, we "
      "share the minimum information necessary (e.g., your name, "
      "delivery address, and order details) with the relevant local "
      "producer/cooperative and delivery partner. Farmers and "
      "cooperatives are not users of the MrBeldi app itself and do not "
      "have account access to your Google data.\n"
      "• Service providers: We share data with vetted third-party "
      "vendors who perform services on our behalf, including "
      "hosting/cloud infrastructure (e.g., Google Cloud Platform / AWS), "
      "SMS/email delivery, and analytics/crash-reporting providers (e.g., "
      "Firebase).";

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _isFrench ? 'Politique de confidentialité' : 'Privacy Policy',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: () => setState(() => _isFrench = !_isFrench),
            child: Text(
              _isFrench ? 'EN' : 'FR',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(w * 0.05),
        child: Text(
          _isFrench ? _privacyTextFr : _privacyTextEn,
          style: const TextStyle(
            fontSize: 14,
            height: 1.6,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}