import 'package:flutter/widgets.dart';
import 'app_locale_service.dart';

class AppStrings {
  static const Map<String, Map<String, String>> _localizedValues = {
    // ── Navigation ──
    'nav_home': {'ar': 'الرئيسية', 'fr': 'Accueil', 'en': 'Home'},
    'nav_categories': {'ar': 'الأقسام', 'fr': 'Catégories', 'en': 'Categories'},
    'nav_favourites': {'ar': 'المفضلة', 'fr': 'Favoris', 'en': 'Favourites'},
    'nav_cart': {'ar': 'السلة', 'fr': 'Panier', 'en': 'Cart'},
    'nav_profile': {'ar': 'حسابي', 'fr': 'Profil', 'en': 'Profile'},

    // ── Actions & Dialogs ──
    'close': {'ar': 'إغلاق', 'fr': 'Fermer', 'en': 'Close'},
    'cancel': {'ar': 'إلغاء', 'fr': 'Annuler', 'en': 'Cancel'},
    'confirm': {'ar': 'تأكيد', 'fr': 'Confirmer', 'en': 'Confirm'},
    'save': {'ar': 'حفظ', 'fr': 'Enregistrer', 'en': 'Save'},
    'error': {'ar': 'خطأ', 'fr': 'Erreur', 'en': 'Error'},
    'retry': {'ar': 'إعادة المحاولة', 'fr': 'Réessayer', 'en': 'Retry'},
    'loading': {
      'ar': 'جاري التحميل...',
      'fr': 'Chargement...',
      'en': 'Loading...',
    },

    // ── Settings Screen ──
    'settings_title': {'ar': 'الإعدادات', 'fr': 'Paramètres', 'en': 'Settings'},
    'section_preferences': {
      'ar': 'التفضيلات',
      'fr': 'Préférences',
      'en': 'Preferences',
    },
    'notifications': {
      'ar': 'الإشعارات',
      'fr': 'Notifications',
      'en': 'Notifications',
    },
    'notifications_push': {
      'ar': 'الإشعارات الفورية',
      'fr': 'Notifications push',
      'en': 'Push notifications',
    },
    'notifications_sub': {
      'ar': 'استلام تنبيهات متابعة الطلبات',
      'fr': 'Recevoir les alertes de suivi',
      'en': 'Receive tracking alerts',
    },
    'promos': {
      'ar': 'العروض والخصومات',
      'fr': 'Offres et promotions',
      'en': 'Offers & promotions',
    },
    'promos_sub': {
      'ar': 'تخفيضات ومستجدات بلدي',
      'fr': 'Bons plans et nouveautés Beldi',
      'en': 'Discounts & Beldi news',
    },
    'change_language': {
      'ar': 'تغيير اللغة',
      'fr': 'Changer la langue',
      'en': 'Change language',
    },
    'choose_language': {
      'ar': 'اختر اللغة',
      'fr': 'Choisir la langue',
      'en': 'Choose Language',
    },
    'device_language_auto': {
      'ar': 'تلقائي (لغة الجهاز)',
      'fr': 'Automatique (Langue de l\'appareil)',
      'en': 'Automatic (Device language)',
    },
    'section_account': {'ar': 'الحساب', 'fr': 'Compte', 'en': 'Account'},
    'profile_info': {
      'ar': 'معلومات الحساب',
      'fr': 'Informations du profil',
      'en': 'Profile Information',
    },
    'profile_info_sub': {
      'ar': 'الاسم، البريد، وتاريخ الانضمام',
      'fr': 'Nom, e-mail, date d\'inscription',
      'en': 'Name, email, signup date',
    },
    'account_connected': {
      'ar': 'حساب متصل',
      'fr': 'Compte connecté',
      'en': 'Connected account',
    },
    'section_about': {
      'ar': 'معلومات',
      'fr': 'Informations',
      'en': 'Information',
    },
    'about_mrbeldi': {
      'ar': 'حول مستر بلدي',
      'fr': 'À propos de MrBeldi',
      'en': 'About MrBeldi',
    },
    'terms_of_service': {
      'ar': 'شروط الاستخدام',
      'fr': 'Conditions d\'utilisation',
      'en': 'Terms of Service',
    },
    'terms_sub': {
      'ar': 'القواعد وشروط البيع',
      'fr': 'Règles et conditions de vente',
      'en': 'Rules and conditions of sale',
    },
    'privacy_policy': {
      'ar': 'سياسة الخصوصية',
      'fr': 'Politique de confidentialité',
      'en': 'Privacy Policy',
    },
    'privacy_sub': {
      'ar': 'حماية بياناتك الشخصية',
      'fr': 'Protection de vos données',
      'en': 'Personal data protection',
    },
    'about_app': {
      'ar': 'عن التطبيق',
      'fr': 'À propos de l\'application',
      'en': 'About the app',
    },
    'about_app_sub': {
      'ar': 'الإصدار ورؤية مستر بلدي',
      'fr': 'Version, vision de MrBeldi',
      'en': 'Version, vision of MrBeldi',
    },
    'support': {'ar': 'الدعم والمساعدة', 'fr': 'Support', 'en': 'Support'},
    'danger_zone': {
      'ar': 'المنطقة الحساسة',
      'fr': 'Zone sensible',
      'en': 'Sensitive zone',
    },
    'delete_account': {
      'ar': 'حذف حسابي',
      'fr': 'Supprimer mon compte',
      'en': 'Delete my account',
    },
    'delete_account_sub': {
      'ar': 'حذف نهائي ولا يمكن التراجع عنه',
      'fr': 'Suppression définitive et irréversible',
      'en': 'Permanent and irreversible deletion',
    },
    'logout': {'ar': 'تسجيل الخروج', 'fr': 'Se déconnecter', 'en': 'Log out'},
    'app_version_tag': {
      'ar': 'MrBeldi v1.0.7 · المغرب 🇲🇦',
      'fr': 'MrBeldi v1.0.7 · Maroc 🇲🇦',
      'en': 'MrBeldi v1.0.7 · Morocco 🇲🇦',
    },
    'version': {'ar': 'الإصدار', 'fr': 'Version', 'en': 'Version'},
    'name': {'ar': 'الاسم', 'fr': 'Nom', 'en': 'Name'},
    'email': {
      'ar': 'البريد الإلكتروني',
      'fr': 'Adresse e-mail',
      'en': 'Email address',
    },
    'phone': {'ar': 'رقم الهاتف', 'fr': 'Téléphone', 'en': 'Phone'},
    'account_created': {
      'ar': 'تاريخ إنشاء الحساب',
      'fr': 'Compte créé le',
      'en': 'Account created on',
    },
    'status': {'ar': 'الحالة', 'fr': 'Statut', 'en': 'Status'},
    'verified': {'ar': 'مفعّل', 'fr': 'Vérifié', 'en': 'Verified'},
    'not_verified': {
      'ar': 'غير مفعّل',
      'fr': 'Non vérifié',
      'en': 'Not verified',
    },
    'not_provided': {
      'ar': 'غير محدد',
      'fr': 'Non renseigné',
      'en': 'Not provided',
    },
    'not_available': {
      'ar': 'غير متوفر',
      'fr': 'Non disponible',
      'en': 'Not available',
    },
    'about_content': {
      'ar':
          'مستر بلدي (MrBeldi) هو تطبيق تجارة إلكترونية مبتكر يهدف أساساً إلى تقريب المستخدمين من صغار الفلاحين والمنتجين المحليين الذين يصعب الوصول إليهم، وفك العزلة عن القرى وإبراز منتجات استثنائية طبيعية ومحلية.\n\nمن بين مهامنا الأساسية، يحرص مستر بلدي قبل كل شيء على ضمان جودة كل منتج معروض وخلوه التام من المواد الكيميائية. باختصار: منتجات صحية، أصيلة، وبدون مساومة.',
      'fr':
          'MrBeldi est une application e-commerce émergente dont la vocation première est de rapprocher les utilisateurs des petits agriculteurs souvent difficiles d\'accès, de désenclaver les villages et de révéler des produits d\'exception jusque-là méconnus du grand public.\n\nParmi ses nombreuses missions, MrBeldi veille avant tout à garantir la qualité de chaque produit référencé et son absence totale de substances chimiques. En résumé : des produits sains, authentiques et sans compromis.',
      'en':
          'MrBeldi is an emerging e-commerce application whose primary mission is to connect users directly with small local farmers who are often difficult to reach, open up rural villages, and showcase exceptional products.\n\nAmong its many missions, MrBeldi ensures above all the quality of every listed product and its complete absence of chemical additives. In short: healthy, authentic products without compromise.',
    },
    'privacy_content': {
      'ar':
          'في مستر بلدي، حماية بياناتك الشخصية هي أولويتنا القصوى. تصف سياسة الخصوصية هذه كيفية جمع بياناتك واستخدامها وحمايتها وفقاً للقوانين والمعايير المعمول بها.\n\n1. جمع البيانات:\nنجمع فقط المعلومات الضرورية لحسن سير الخدمة: الاسم، البريد الإلكتروني، رقم الهاتف، وعنوان التوصيل.\n\n2. استخدام البيانات:\nتُستخدم بياناتك حصرياً لإدارة حسابك، معالجة وتوصيل طلباتك، وتحسين تجربتك.\n\n3. أمان البيانات:\nنطبق تدابير تقنية وتنظيمية صارمة لحماية معلوماتك ضد أي وصول غير مصرح به.\n\n4. مشاركة البيانات:\nلا نقوم ببيع بياناتك الشخصية لأي طرف ثالث نهائياً، وتقتصر المشاركة على الشركاء التقنيين لتنفيذ الخدمة.\n\n5. حقوقك:\nيحق لك الوصول إلى بياناتك أو طلب تصحيحها أو حذفها في أي وقت عبر التواصل مع فريق الدعم.',
      'fr':
          'Chez MrBeldi, la protection de vos données personnelles est une priorité absolue. Cette politique de confidentialité décrit la manière dont nous collectons, utilisons, stockons et protégeons vos informations, conformément aux normes en vigueur en matière de protection des données.\n\n1. Collecte des données\nNous collectons uniquement les informations nécessaires au bon fonctionnement du service : nom, adresse e-mail, numéro de téléphone, adresse de livraison et données de connexion.\n\n2. Utilisation des données\nVos données sont utilisées exclusivement pour la gestion de votre compte, le traitement de vos commandes, l\'amélioration de nos services.\n\n3. Sécurité des données\nNous mettons en œuvre des mesures techniques et organisationnelles strictes afin de protéger vos informations.\n\n4. Partage des données\nVos données personnelles ne sont jamais vendues à des tiers.\n\n5. Vos droits\nVous disposez d\'un droit d\'accès, de rectification et de suppression de vos données à tout moment via notre support.',
      'en':
          'At MrBeldi, protecting your personal data is an absolute priority. This privacy policy describes how we collect, use, store, and protect your information.\n\n1. Data Collection\nWe only collect information necessary for the service: name, email, phone number, and delivery address.\n\n2. Data Usage\nYour data is used exclusively to manage your account, process orders, and improve our services.\n\n3. Data Security\nWe implement strict technical and organizational measures to safeguard your information against unauthorized access.\n\n4. Data Sharing\nYour personal data is never sold to third parties.\n\n5. Your Rights\nYou have the right to access, rectify, or delete your personal data at any time via support.',
    },
    'terms_content': {
      'ar':
          'تحكم هذه الشروط العامة استخدام تطبيق مستر بلدي. بإنشاء حساب أو استخدام خدماتنا، فإنك توافق دون تحفظ على هذه الشروط:\n\n1. قبول الشروط:\nاستخدام التطبيق يعني القبول الكامل لهذه الشروط العامة للاستخدام.\n\n2. حساب المستخدم:\nأنت مسؤول عن المحافظة على سرية بيانات حسابك وكافة الأنشطة الصادرة عنه.\n\n3. استخدام الخدمة:\nتتعهد باستخدام التطبيق وفقاً للقوانين المعمول بها ودون الإضرار بحقوق مستر بلدي أو البائعين أو المستخدمين.\n\n4. الطلبات والأسعار:\nأي طلب يتم عبر التطبيق يُعد التزاماً بالشراء. الأسعار وأوقات التوصيل معلنة لأغراض إعلامية وتخضع للتأكيد.\n\n5. الملكية الفكرية:\nكافة محتويات التطبيق محمية بحقوق الملكية الفكرية ولا يجوز نسخها دون ترخيص مسبق.',
      'fr':
          'Les présentes conditions d\'utilisation régissent l\'accès et l\'utilisation de l\'application MrBeldi. En créant un compte ou en utilisant nos services, vous acceptez sans réserve les termes suivants.\n\n1. Acceptation des conditions\nL\'utilisation de l\'application implique l\'acceptation pleine et entière des présentes conditions générales d\'utilisation.\n\n2. Compte utilisateur\nVous êtes responsable de la confidentialité de vos identifiants de connexion et de toutes les activités effectuées depuis votre compte.\n\n3. Utilisation du service\nVous vous engagez à utiliser l\'application conformément à la loi.\n\n4. Commandes et paiements\nToute commande passée sur l\'application constitue un engagement d\'achat.\n\n5. Propriété intellectuelle\nL\'ensemble des contenus de l\'application est protégé par les droits de propriété intellectuelle.',
      'en':
          'These terms of use govern access to and use of the MrBeldi application. By creating an account or using our services, you accept these terms without reservation.\n\n1. Acceptance of Terms\nUsing the application implies full acceptance of these terms of use.\n\n2. User Account\nYou are responsible for maintaining the confidentiality of your account credentials.\n\n3. Service Use\nYou agree to use the application lawfully and without infringing the rights of MrBeldi or others.\n\n4. Orders and Payments\nAny order placed constitutes a purchase commitment.\n\n5. Intellectual Property\nAll application content is protected by intellectual property rights.',
    },

    // ── General e-commerce ──
    'out_of_stock': {
      'ar': 'نفد من المخزون',
      'fr': 'Rupture de stock',
      'en': 'Out of stock',
    },
    'add_to_cart': {
      'ar': 'أضف إلى السلة',
      'fr': 'Ajouter au panier',
      'en': 'Add to Cart',
    },
    'total': {'ar': 'المجموع', 'fr': 'Total', 'en': 'Total'},
    'free_delivery': {
      'ar': 'توصيل مجاني',
      'fr': 'Livraison gratuite',
      'en': 'Free delivery',
    },
    'bio_100': {'ar': 'طبيعي 100%', 'fr': '100% Bio', 'en': '100% Bio'},
    'guaranteed_quality': {
      'ar': 'جودة مضمونة',
      'fr': 'Qualité garantie',
      'en': 'Guaranteed quality',
    },
    'currency': {'ar': 'درهم', 'fr': 'DH', 'en': 'DH'},

    // ── Categories ──
    'categories_title': {
      'ar': 'الأقسام',
      'fr': 'Nos Catégories',
      'en': 'Our Categories',
    },
    'categories_subtitle': {
      'ar': 'منتجات طازجة وطبيعية من الأرض',
      'fr': 'Frais du terroir',
      'en': 'Fresh from the farm',
    },
    'search_categories_hint': {
      'ar': 'ابحث عن قسم...',
      'fr': 'Rechercher une catégorie...',
      'en': 'Search a category...',
    },
    'no_categories_found': {
      'ar': 'لم يتم العثور على أي قسم',
      'fr': 'Aucune catégorie trouvée',
      'en': 'No categories found',
    },
    'all': {'ar': 'الكل', 'fr': 'Tout', 'en': 'All'},
    'cat_legumes': {'ar': 'خضروات', 'fr': 'Légumes', 'en': 'Vegetables'},
    'cat_legumes_sub': {
      'ar': 'طازجة من الأرض',
      'fr': 'Frais du terroir',
      'en': 'Fresh from the land',
    },
    'cat_fruits': {'ar': 'فواكه', 'fr': 'Fruits', 'en': 'Fruits'},
    'cat_fruits_sub': {
      'ar': 'مقطوفة عند النضج',
      'fr': 'Cueillis à maturité',
      'en': 'Picked at maturity',
    },
    'cat_herbes': {
      'ar': 'أعشاب وتوابل',
      'fr': 'Herbes & Épices',
      'en': 'Herbs & Spices',
    },
    'cat_herbes_sub': {
      'ar': 'نكهات المغرب الأصيلة',
      'fr': 'Arômes du Maroc',
      'en': 'Flavors of Morocco',
    },
    'cat_huiles': {
      'ar': 'زيوت ومصبرات',
      'fr': 'Huiles & Conserves',
      'en': 'Oils & Preserves',
    },
    'cat_huiles_sub': {
      'ar': 'منتجات تقليدية وطبيعية',
      'fr': 'Produits artisanaux',
      'en': 'Artisanal products',
    },
    'cat_laitier': {
      'ar': 'منتجات الحليب',
      'fr': 'Produits Laitiers',
      'en': 'Dairy Products',
    },
    'cat_laitier_sub': {
      'ar': 'من المنتج إليك مباشرة',
      'fr': 'Du producteur à vous',
      'en': 'From producer to you',
    },
    'cat_cereales': {
      'ar': 'حبوب وقطاني',
      'fr': 'Céréales & Légumes secs',
      'en': 'Grains & Pulses',
    },
    'cat_cereales_sub': {
      'ar': 'خيرات الأرض الطبيعية',
      'fr': 'Richesses du terroir',
      'en': 'Bounty of the land',
    },
    'cat_miel': {
      'ar': 'عسل وخلايا النحل',
      'fr': 'Miel & Ruche',
      'en': 'Honey & Hive',
    },
    'cat_miel_sub': {
      'ar': 'ذهب المغرب السائل',
      'fr': 'Or liquide du Maroc',
      'en': 'Liquid gold of Morocco',
    },
    'cat_viandes': {
      'ar': 'لحوم ودواجن',
      'fr': 'Viandes & Volailles',
      'en': 'Meat & Poultry',
    },
    'cat_viandes_sub': {
      'ar': 'تربية تقليدية طبيعية',
      'fr': 'Élevage traditionnel',
      'en': 'Traditional farming',
    },

    // ── Favourites ──
    'favourites_title': {
      'ar': 'المفضلة',
      'fr': 'Mes favoris',
      'en': 'My Favorites',
    },
    'favourites_empty': {
      'ar': 'قائمة المفضلة فارغة',
      'fr': 'Votre liste est vide',
      'en': 'Your favorites list is empty',
    },
    'favourites_empty_sub': {
      'ar': 'احفظ منتجاتك المفضلة هنا للرجوع إليها لاحقاً',
      'fr':
          'Enregistrez vos produits coups de cœur pour les retrouver facilement',
      'en': 'Save your favorite products here to find them easily',
    },
    'in_stock': {'ar': 'متوفر', 'fr': 'En stock', 'en': 'In stock'},
    'explore_products': {
      'ar': 'تصفح المنتجات',
      'fr': 'Explorer les produits',
      'en': 'Explore products',
    },
    'added_to_cart': {
      'ar': 'تمت الإضافة إلى السلة',
      'fr': 'Ajouté au panier',
      'en': 'Added to cart',
    },
    'articles_saved': {
      'ar': 'منتج محفوظ',
      'fr': 'article(s) sauvegardé(s)',
      'en': 'saved item(s)',
    },
  };

  static String get(String key, [String? langCode]) {
    final code = langCode ?? AppLocaleService.currentLanguageCode;
    return _localizedValues[key]?[code] ??
        _localizedValues[key]?['fr'] ??
        _localizedValues[key]?['ar'] ??
        key;
  }
}

extension AppLocalizationExtension on BuildContext {
  String tr(String key) => AppStrings.get(key);
}
