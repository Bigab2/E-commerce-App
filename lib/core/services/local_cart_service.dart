// lib/core/services/local_cart_service.dart
//
// خدمة السلة المحلية — تُستخدم فقط للزوار غير المسجلين.
// كيفما schéma carts/{uid}/items فـ Firestore، هاد الخدمة كتخزن فقط
// productId + qty + addedAt (بدون سعر ولا اسم، لتفادي أي تعارض مع
// السعر الحقيقي المقروء دائماً من products/{id}).
//
// ✅ CORRECTIF (race condition) : قبل هاد التعديل، كانت هاد الخدمة
// كتستمع بشكل مستقل لـ authStateChanges() وكتزامن السلة فوراً، فـ نفس
// الوقت اللي login_screen.dart كيكتب فيه users/{uid}. هاد التزامن بين
// جوج كتابات مستقلات زاد من احتمال الاصطدام بـ délai الطبيعي لي
// كتاخذو Firestore باش يتحقق من request.auth بعد signIn مباشرة.
//
// الحل : ماشي الخدمة لي كتقرر وقتاش تزامن، بل login_screen (أو أي
// نقطة دخول أخرى) هي لي كتنادي syncToFirestore() بشكل صريح ومتسلسل
// (sequential) من بعد ما يكمل إنشاء users/{uid}. الـ authStateChanges
// listener تبقى موجودة كـ fallback فقط (مثلاً إذا التطبيق تسكر قبل ما
// تكمل المزامنة)، ماشي كـ trigger أساسي.
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mrbeldi/core/notifications/app_notification_service.dart';

class LocalCartItem {
  final String productId;
  final int qty;
  final DateTime addedAt;

  const LocalCartItem({
    required this.productId,
    required this.qty,
    required this.addedAt,
  });

  LocalCartItem copyWith({int? qty}) => LocalCartItem(
        productId: productId,
        qty: qty ?? this.qty,
        addedAt: addedAt,
      );

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'qty': qty,
        'addedAt': addedAt.toIso8601String(),
      };

  factory LocalCartItem.fromJson(Map<String, dynamic> json) => LocalCartItem(
        productId: json['productId'] as String,
        qty: (json['qty'] as num?)?.toInt() ?? 1,
        addedAt:
            DateTime.tryParse(json['addedAt']?.toString() ?? '') ?? DateTime.now(),
      );
}

class LocalCartService {
  LocalCartService._();

  static const String _storageKey = 'local_cart_items_v1';

  static List<LocalCartItem> _cache = [];
  static bool _loaded = false;
  static bool _authListenerAttached = false;

  // يمنع تشغيل المزامنة مرتين فـ نفس الوقت (مثلاً fallback listener
  // + استدعاء صريح من login_screen يتصادفان).
  static bool _syncInProgress = false;

  static final StreamController<List<LocalCartItem>> _controller =
      StreamController<List<LocalCartItem>>.broadcast();

  // ── تحميل أولي من SharedPreferences + تفعيل fallback listener ──
  static Future<void> _ensureLoaded() async {
    _ensureAuthListener();
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        _cache = (jsonDecode(raw) as List)
            .map((e) => LocalCartItem.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _cache = [];
      }
    }
    _loaded = true;
  }

  /// ⚠️ Fallback فقط — ماشي المسار الأساسي للمزامنة.
  /// إيلا كان التطبيق مسجل الدخول أصلاً عند الفتح (مثلاً reload بعد
  /// crash قبل ما تكمل المزامنة الصريحة)، هاد الـ listener كيضمن
  /// أن السلة غادي تتزامن عاجلاً ولا آجلاً. فـ التدفق العادي (تسجيل
  /// دخول جديد من login_screen)، المزامنة كتصدر من استدعاء صريح
  /// ومتسلسل بعد _ensureUserDocument، ماشي من هنا.
  static void _ensureAuthListener() {
    if (_authListenerAttached) return;
    _authListenerAttached = true;
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        // تأخير بسيط باش نعطيو الأولوية لأي مزامنة صريحة جارية
        // (مثلاً من login_screen) قبل ما الـ fallback يدخل.
        Future.delayed(const Duration(seconds: 2), () {
          if (!_syncInProgress) {
            syncToFirestore(user.uid);
          }
        });
      }
    });
  }

  /// استدعاء اختياري ومبكر (مثلاً فـ initState) فقط لضمان تحميل
  /// الكاش وتفعيل الـ fallback listener من البداية.
  static void warmUp() {
    // ignore: discarded_futures
    _ensureLoaded();
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _storageKey, jsonEncode(_cache.map((e) => e.toJson()).toList()));
    _controller.add(List.unmodifiable(_cache));
    unawaited(AppNotificationService.recordCartInteraction());
  }

  static Future<List<LocalCartItem>> getItems() async {
    await _ensureLoaded();
    return List.unmodifiable(_cache);
  }

  /// Stream مشابه لـ StreamBuilder المستعمل مع Firestore: يصدر القيمة
  /// الحالية أولاً، ثم أي تحديث لاحق.
  static Stream<List<LocalCartItem>> watch() async* {
    await _ensureLoaded();
    yield List.unmodifiable(_cache);
    yield* _controller.stream;
  }

  static Future<void> addItem(String productId, {int qty = 1}) async {
    await _ensureLoaded();
    final idx = _cache.indexWhere((e) => e.productId == productId);
    if (idx >= 0) {
      _cache[idx] = _cache[idx].copyWith(qty: _cache[idx].qty + qty);
    } else {
      _cache.add(LocalCartItem(productId: productId, qty: qty, addedAt: DateTime.now()));
    }
    await _persist();
  }

  static Future<void> updateQty(String productId, int qty) async {
    await _ensureLoaded();
    if (qty <= 0) {
      _cache.removeWhere((e) => e.productId == productId);
    } else {
      final idx = _cache.indexWhere((e) => e.productId == productId);
      if (idx >= 0) _cache[idx] = _cache[idx].copyWith(qty: qty);
    }
    await _persist();
  }

  static Future<void> removeItem(String productId) async {
    await _ensureLoaded();
    _cache.removeWhere((e) => e.productId == productId);
    await _persist();
  }

  static Future<void> clear() async {
    await _ensureLoaded();
    _cache = [];
    await _persist();
  }

  /// تُكتب السلة المحلية فـ Firestore (carts/{uid}/items) فور نجاح
  /// تسجيل الدخول. نستعمل merge + increment باش ما نسحقوش عناصر
  /// موجودة مسبقاً فـ حساب المستخدم.
  ///
  /// ✅ CORRECTIF : قبل الكتابة، كنجبرو تحديث الـ ID Token عبر
  /// getIdToken(true) باش نضمنو بلي request.auth غادي يكون معترف بيه
  /// بشكل موثوق من طرف خادم Firestore وقت تقييم security rules —
  /// هادشي كيقلل بزاف من احتمال permission-denied بسبب délai
  /// propagation طبيعي بعد signIn. زدنا أيضاً retry بسيط كطبقة حماية
  /// إضافية إيلا فشلت أول محاولة لهاد السبب بالذات.
  static Future<void> syncToFirestore(String uid, {int retries = 2}) async {
    if (_syncInProgress) return;
    _syncInProgress = true;
    try {
      await _ensureLoaded();
      if (_cache.isEmpty) return;

      final user = FirebaseAuth.instance.currentUser;
      // تأكد بلي المستخدم الحالي فعلاً هو نفسو uid المطلوب (تفادي أي
      // حالة نادرة تبدل فيها المستخدم بين استدعاء وآخر).
      if (user == null || user.uid != uid) return;

      // 🔑 يجبر تحديث/تحقق التوكن قبل أي كتابة حساسة.
      try {
        await user.getIdToken(true);
      } catch (_) {
        // إيلا فشل تحديث التوكن (مثلاً بدون اتصال)، نكملو المحاولة
        // العادية بأي حال، الـ retry تحت غادي يتكلف بالتعامل مع الفشل.
      }

      final itemsToSync = List<LocalCartItem>.from(_cache);
      final firestore = FirebaseFirestore.instance;
      final itemsRef = firestore.collection('carts').doc(uid).collection('items');

      for (int attempt = 0; attempt <= retries; attempt++) {
        try {
          final batch = firestore.batch();
          for (final item in itemsToSync) {
            batch.set(
              itemsRef.doc(item.productId),
              {
                'productId': item.productId,
                'qty': FieldValue.increment(item.qty),
                'addedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
          }
          await batch.commit();
          await clear();
          return; // نجحت المزامنة، نخرجو
        } catch (_) {
          if (attempt == retries) {
            // فشلت كل المحاولات (مثلاً بدون اتصال) : نُبقي العناصر
            // محلياً، وستُعاد المحاولة تلقائياً عند أي حدث auth لاحق
            // (fallback listener) أو استدعاء صريح آخر.
            return;
          }
          await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
        }
      }
    } finally {
      _syncInProgress = false;
    }
  }
}