import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/foundation.dart';

import '../../models/order_model.dart';
import '../../services/api_client.dart';
import '../../services/push_service.dart';

// =====================================================================
//  حالة تطبيق الطالب (الحساب، السلة، المفضلة، الإشعارات، الطلبات)
//  مصدر البيانات: سيرفر وجباتي (FastAPI). السلة فقط محلية على الجهاز.
//  التحديثات (حالة الطلب، توفر الأصناف، الإشعارات) تُجلب كل بضع ثوانٍ.
// =====================================================================

/// حالات الطلب الأربع (نفس قيم السيرفر)
class OrderStatus {
  static const String received = 'received'; // 1. تم استلام الطلب
  static const String preparing = 'preparing'; // 2. قيد التحضير
  static const String ready = 'ready'; // 3. جاهز
  static const String delivered = 'delivered'; // 4. تم التسليم
  static const String cancelled = 'cancelled';
  static const String rejected = 'rejected';

  static const List<String> steps = [received, preparing, ready, delivered];

  static const Map<String, String> studentLabels = {
    received: 'تم استلام الطلب',
    preparing: 'قيد التحضير',
    ready: 'جاهز للاستلام',
    delivered: 'تم التسليم',
    cancelled: 'ملغي',
    rejected: 'مرفوض من الكافيتريا',
  };

  static int indexOf(String status) {
    final i = steps.indexOf(status);
    return i == -1 ? 0 : i;
  }

  static bool isActive(String status) =>
      [received, preparing, ready].contains(status);
}

enum CafeteriaStatus { open, busy, closed }

CafeteriaStatus cafeteriaStatusFrom(String? s) => switch (s) {
  'busy' => CafeteriaStatus.busy,
  'closed' => CafeteriaStatus.closed,
  _ => CafeteriaStatus.open,
};

class CafeteriaInfo {
  final int id;
  final String name;
  final String location;
  final int openHour;
  final int closeHour;
  final CafeteriaStatus status;
  final CafeteriaStatus? manualStatus;
  final int activeOrders;
  final int availableItems;

  const CafeteriaInfo({
    required this.id,
    required this.name,
    required this.location,
    required this.openHour,
    required this.closeHour,
    required this.status,
    this.manualStatus,
    this.activeOrders = 0,
    this.availableItems = 0,
  });

  factory CafeteriaInfo.fromApi(Map<String, dynamic> j) => CafeteriaInfo(
    id: j['id'] as int,
    name: j['name'] as String,
    location: (j['location'] as String?) ?? '',
    openHour: j['open_hour'] as int,
    closeHour: j['close_hour'] as int,
    status: cafeteriaStatusFrom(j['status'] as String?),
    manualStatus: j['manual_status'] == null
        ? null
        : cafeteriaStatusFrom(j['manual_status'] as String),
    activeOrders: (j['active_orders'] as int?) ?? 0,
    availableItems: (j['available_items'] as int?) ?? 0,
  );

  String get hoursLabel =>
      '${openHour.toString().padLeft(2, '0')}:00 - ${closeHour.toString().padLeft(2, '0')}:00';
}

class StudentAccount {
  final String name;
  final String universityId;
  final String phone;

  const StudentAccount({
    required this.name,
    required this.universityId,
    required this.phone,
  });

  factory StudentAccount.fromApi(Map<String, dynamic> j) => StudentAccount(
    name: j['name'] as String,
    universityId: j['university_id'] as String,
    phone: j['phone'] as String,
  );
}

class CartEntry {
  final MenuItemModel item;
  int quantity;
  String note;

  CartEntry({required this.item, this.quantity = 1, this.note = ''});

  double get total => item.priceValue * quantity;
}

class AppNotification {
  final int id;
  final String title;
  final String body;
  final DateTime time;
  final String? orderId;
  bool read;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.time,
    this.orderId,
    this.read = false,
  });

  factory AppNotification.fromApi(Map<String, dynamic> j) => AppNotification(
    id: j['id'] as int,
    title: j['title'] as String,
    body: j['body'] as String,
    time: DateTime.parse(j['created_at'] as String),
    orderId: j['order_id'] as String?,
    read: (j['read'] as bool?) ?? false,
  );
}

/// نتيجة عملية (لإظهار رسائل خطأ واضحة للطالب)
class ActionResult {
  final bool ok;
  final String message;
  const ActionResult.success([this.message = '']) : ok = true;
  const ActionResult.failure(this.message) : ok = false;
}

class StudentStore extends ChangeNotifier {
  StudentStore._();
  static final StudentStore instance = StudentStore._();

  final ApiClient api = ApiClient.instance;
  static const pollInterval = Duration(seconds: 4);

  Timer? _poller;
  bool _refreshing = false;

  /// رسالة عند فشل الاتصال بالسيرفر (تظهر كشريط في الأعلى)
  String? connectionError;
  DateTime? lastUpdated;
  bool _placingOrder = false;
  SharedPreferences? _cartPrefs;
  String? _pendingPayload;
  String? _pendingKey;
  Future<void> _cartWrites = Future.value();
  String get _cartKey => 'wajbati.cart.${api.baseUrl}.${currentStudent?.phone}';

  // ---------------- التهيئة ----------------
  /// تُستدعى عند تشغيل التطبيق: تستعيد الجلسة المحفوظة إن وجدت
  Future<void> init() async {
    if (api.studentToken == null) return;
    try {
      final me = await api.get('/me', auth: ApiRole.student);
      currentStudent = StudentAccount.fromApi(
        Map<String, dynamic>.from(me as Map),
      );
      await _afterLogin();
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await api.setToken(ApiRole.student, null); // جلسة منتهية
      } else {
        // السيرفر غير متاح الآن: نفتح التطبيق ونعيد المحاولة تلقائياً
        connectionError = e.message;
        currentStudent = const StudentAccount(
          name: '',
          universityId: '',
          phone: '',
        );
        _startPolling();
      }
    }
  }

  // ---------------- الكافيتريات ----------------
  final Map<String, CafeteriaInfo> cafeterias = {};
  List<CafeteriaInfo> get cafeteriaList => cafeterias.values.toList();
  bool cafeteriasLoaded = false;

  CafeteriaInfo? cafeteriaById(int? id) {
    for (final c in cafeterias.values) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> loadCafeterias() async {
    final data = await api.get('/cafeterias') as List;
    cafeterias
      ..clear()
      ..addEntries(
        data.map((e) {
          final c = CafeteriaInfo.fromApi(Map<String, dynamic>.from(e as Map));
          return MapEntry(c.name, c);
        }),
      );
    cafeteriasLoaded = true;
  }

  // ---------------- القوائم ----------------
  final Map<int, List<MenuItemModel>> menus = {};
  final Set<int> _watchedMenus = {}; // القوائم المفتوحة حالياً (تُحدَّث دورياً)

  List<MenuItemModel>? menuFor(String cafeteria) {
    final id = cafeterias[cafeteria]?.id;
    return id == null ? null : menus[id];
  }

  Future<ActionResult> loadMenu(String cafeteria) async {
    final id = cafeterias[cafeteria]?.id;
    if (id == null) return const ActionResult.failure('الكافيتريا غير موجودة');
    try {
      await _fetchMenu(id);
      notifyListeners();
      return const ActionResult.success();
    } on ApiException catch (e) {
      return ActionResult.failure(e.message);
    }
  }

  Future<void> _fetchMenu(int cafeteriaId) async {
    final data = await api.get('/cafeterias/$cafeteriaId/menu') as List;
    menus[cafeteriaId] = data
        .map((e) => MenuItemModel.fromApi(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  void watchMenu(String cafeteria) {
    final id = cafeterias[cafeteria]?.id;
    if (id != null) _watchedMenus.add(id);
  }

  void unwatchMenu(String cafeteria) {
    final id = cafeterias[cafeteria]?.id;
    if (id != null) _watchedMenus.remove(id);
  }

  /// أحدث نسخة من الصنف (بعد تحديث القائمة من السيرفر)
  MenuItemModel? latest(MenuItemModel item) {
    final list = menus[item.cafeteriaId];
    if (list == null) return item;
    for (final m in list) {
      if (m.id == item.id) return m;
    }
    return null; // حُذف من القائمة
  }

  // ---------------- الحساب ----------------
  StudentAccount? currentStudent;
  bool get isLoggedIn => currentStudent != null;

  static String normalizePhone(String p) => p.replaceAll(RegExp(r'[\s-]'), '');

  Future<ActionResult> register({
    required String name,
    required String universityId,
    required String phone,
    required String password,
  }) => _auth('/auth/register', {
    'name': name.trim(),
    'university_id': universityId.trim(),
    'phone': normalizePhone(phone),
    'password': password,
  }, 'تم إنشاء الحساب بنجاح');

  Future<ActionResult> login(String phone, String password) => _auth(
    '/auth/login',
    {'phone': normalizePhone(phone), 'password': password},
    '',
  );

  Future<ActionResult> _auth(
    String path,
    Map<String, dynamic> body,
    String successMessage,
  ) async {
    try {
      final res = Map<String, dynamic>.from(
        await api.post(path, body: body) as Map,
      );
      await api.setToken(ApiRole.student, res['token'] as String);
      currentStudent = StudentAccount.fromApi(
        Map<String, dynamic>.from(res['student'] as Map),
      );
      await _afterLogin();
      return ActionResult.success(successMessage);
    } on ApiException catch (e) {
      return ActionResult.failure(e.message);
    }
  }

  Future<void> _afterLogin() async {
    _lastNotificationId = 0;
    notifications.clear();
    _initialNotificationsLoaded = false;
    await refresh();
    await _loadFavorites();
    await _restoreCart();
    _startPolling();
    unawaited(PushService.instance.registerDevice());
    notifyListeners();
  }

  void logout() {
    unawaited(PushService.instance.unregisterDevice());
    _poller?.cancel();
    api.setToken(ApiRole.student, null);
    currentStudent = null;
    cart.clear();
    cartCafeteria = null;
    notifications.clear();
    myOrders = [];
    favoriteIds.clear();
    favoriteItems = [];
    connectionError = null;
    lastUpdated = null;
    _pendingKey = null;
    _pendingPayload = null;
    notifyListeners();
  }

  void _startPolling() {
    _poller?.cancel();
    _poller = Timer.periodic(pollInterval, (_) => refresh());
  }

  /// إيقاف التحديث الدوري (للاختبارات)
  void stopWatching() => _poller?.cancel();

  // ---------------- التحديث الدوري ----------------
  /// يجلب الكافيتريات والطلبات والإشعارات الجديدة والقوائم المفتوحة
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      // إعادة جلب بيانات الحساب إذا فتح التطبيق والسيرفر متوقف
      if (currentStudent != null &&
          currentStudent!.universityId.isEmpty &&
          api.studentToken != null) {
        final me = await api.get('/me', auth: ApiRole.student);
        currentStudent = StudentAccount.fromApi(
          Map<String, dynamic>.from(me as Map),
        );
        await _loadFavorites();
        await _restoreCart();
      }
      await loadCafeterias();
      if (isLoggedIn && api.studentToken != null) {
        final orders =
            await api.get('/orders/mine', auth: ApiRole.student) as List;
        myOrders = orders
            .map((e) => OrderItem.fromApi(Map<String, dynamic>.from(e as Map)))
            .toList();
        await _loadNotifications();
      }
      final cartMenu = _cartCafeteriaId;
      for (final id in {..._watchedMenus, if (cartMenu != null) cartMenu}) {
        await _fetchMenu(id);
      }
      connectionError = null;
      lastUpdated = DateTime.now();
      if (isLoggedIn) unawaited(PushService.instance.registerDevice());
    } on ApiException catch (e) {
      if (e.isUnauthorized && isLoggedIn) {
        logout();
        connectionError = 'انتهت الجلسة، الرجاء تسجيل الدخول من جديد.';
      } else {
        connectionError = e.message;
      }
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  /// للتوافق مع الشاشات (سحب للتحديث)
  Future<void> checkForUpdates() => refresh();

  // ---------------- السلة (محلية) ----------------
  Future<void> _restoreCart() async {
    _cartPrefs = await SharedPreferences.getInstance();
    final saved = _cartPrefs!.getString(_cartKey);
    if (saved == null || cart.isNotEmpty) return;
    try {
      final data = jsonDecode(saved) as Map<String, dynamic>;
      cartCafeteria = data['cafeteria'] as String?;
      for (final line in data['lines'] as List) {
        cart.add(
          CartEntry(
            item: MenuItemModel.fromApi(
              Map<String, dynamic>.from(line['item'] as Map),
            ),
            quantity: line['quantity'] as int,
            note: line['note'] as String,
          ),
        );
      }
      _pendingKey = data['request_key'] as String?;
      _pendingPayload = data['payload'] as String?;
      if (_cartCafeteriaId != null) await _fetchMenu(_cartCafeteriaId!);
    } on ApiException {
      // Keep the saved cart; the next refresh retries the menu.
    } on FormatException {
      cart.clear();
      cartCafeteria = null;
    } on TypeError {
      cart.clear();
      cartCafeteria = null;
    }
  }

  Future<void> _saveCart() {
    if (!isLoggedIn) return Future.value();
    final key = _cartKey;
    final snapshot = jsonEncode({
      'cafeteria': cartCafeteria,
      'request_key': _pendingKey,
      'payload': _pendingPayload,
      'lines': [
        for (final e in cart)
          {
            'quantity': e.quantity,
            'note': e.note,
            'item': {
              'id': e.item.id,
              'cafeteria_id': e.item.cafeteriaId,
              'cafeteria_name': e.item.cafeteriaName,
              'name': e.item.name,
              'price': e.item.priceValue,
              'prep_minutes': e.item.prepMinutes,
              'available': e.item.isAvailable,
              'image_url': e.item.imageUrl,
              'emoji': e.item.emoji,
            },
          },
      ],
    });
    _cartWrites = _cartWrites.catchError((Object _) {}).then((_) async {
      _cartPrefs ??= await SharedPreferences.getInstance();
      await _cartPrefs!.setString(key, snapshot);
    });
    return _cartWrites;
  }

  final List<CartEntry> cart = [];
  String? cartCafeteria;
  int? get _cartCafeteriaId => cafeterias[cartCafeteria]?.id;

  int get cartCount => cart.fold(0, (s, e) => s + e.quantity);
  double get cartTotal => cart.fold(0, (s, e) => s + e.total);
  int get cartMaxPrepMinutes =>
      cart.fold(0, (m, e) => e.item.prepMinutes > m ? e.item.prepMinutes : m);

  int quantityInCart(MenuItemModel item) =>
      cart.where((e) => e.item.id == item.id).fold(0, (s, e) => s + e.quantity);

  /// يرجع false إذا كانت السلة تحتوي أصنافاً من كافيتريا أخرى.
  bool canAddFrom(String cafeteria) =>
      cartCafeteria == null || cartCafeteria == cafeteria || cart.isEmpty;

  ActionResult addToCart(
    String cafeteria,
    MenuItemModel item, {
    int quantity = 1,
    String note = '',
  }) {
    final current = latest(item);
    if (current == null || !current.isAvailable) {
      return ActionResult.failure('عذراً، "${item.name}" منتهٍ حالياً.');
    }
    if (cafeterias[cafeteria]?.status == CafeteriaStatus.closed) {
      return const ActionResult.failure(
        'الكافيتريا مغلقة حالياً، لا يمكن الطلب منها.',
      );
    }
    if (!canAddFrom(cafeteria)) {
      return const ActionResult.failure(
        'السلة تحتوي أصنافاً من كافيتريا أخرى.',
      );
    }
    cartCafeteria = cafeteria;
    final existing = cart.where(
      (e) => e.item.id == item.id && e.note == note.trim(),
    );
    if (existing.isNotEmpty) {
      existing.first.quantity += quantity;
    } else {
      cart.add(CartEntry(item: current, quantity: quantity, note: note.trim()));
    }
    unawaited(_saveCart());
    notifyListeners();
    return ActionResult.success('تمت إضافة "${item.name}" إلى السلة');
  }

  void changeQuantity(CartEntry entry, int delta) {
    entry.quantity += delta;
    if (entry.quantity <= 0) cart.remove(entry);
    if (cart.isEmpty) cartCafeteria = null;
    unawaited(_saveCart());
    notifyListeners();
  }

  void updateNote(CartEntry entry, String note) {
    entry.note = note.trim();
    unawaited(_saveCart());
    notifyListeners();
  }

  void removeFromCart(CartEntry entry) {
    cart.remove(entry);
    if (cart.isEmpty) cartCafeteria = null;
    unawaited(_saveCart());
    notifyListeners();
  }

  void clearCart() {
    cart.clear();
    cartCafeteria = null;
    _pendingKey = null;
    _pendingPayload = null;
    unawaited(_saveCart());
    notifyListeners();
  }

  /// الأصناف التي نفدت أو حُذفت من القائمة بعد إضافتها للسلة
  List<CartEntry> get unavailableInCart => cart.where((e) {
    final m = latest(e.item);
    return m == null || !m.isAvailable;
  }).toList();

  // ---------------- أوقات الاستلام ----------------
  static const int slotCapacity = 4; // نفس قيمة السيرفر

  /// الأوقات من السيرفر: القيمة = عدد الطلبات المحجوزة
  Future<Map<DateTime, int>> fetchSlots(String cafeteria) async {
    final id = cafeterias[cafeteria]?.id;
    if (id == null) return {};
    final data =
        await api.get(
              '/cafeterias/$id/slots',
              query: {'prep_minutes': '$cartMaxPrepMinutes'},
            )
            as List;
    return {
      for (final s in data.cast<Map>())
        DateTime.parse(s['time'] as String): s['booked'] as int,
    };
  }

  bool isSlotAvailable(int booked) => booked < slotCapacity;

  // ---------------- الطلبات ----------------
  List<OrderItem> myOrders = [];

  List<OrderItem> get activeOrders =>
      myOrders.where((o) => OrderStatus.isActive(o.status)).toList();
  List<OrderItem> get pastOrders =>
      myOrders.where((o) => !OrderStatus.isActive(o.status)).toList();

  OrderItem? findOrder(String id) {
    for (final o in myOrders) {
      if (o.id == id) return o;
    }
    return null;
  }

  Future<ActionResult> placeOrder({
    required DateTime pickupTime,
    required String paymentMethod,
  }) async {
    if (_placingOrder) {
      return const ActionResult.failure('جارٍ إرسال الطلب، انتظر قليلًا.');
    }
    final cafeteriaId = _cartCafeteriaId;
    if (!isLoggedIn) {
      return const ActionResult.failure(
        'انتهت الجلسة، الرجاء تسجيل الدخول من جديد.',
      );
    }
    if (cafeteriaId == null || cart.isEmpty) {
      return const ActionResult.failure('السلة فارغة.');
    }
    _placingOrder = true;
    try {
      final body = <String, dynamic>{
        'cafeteria_id': cafeteriaId,
        'pickup_time': _isoMinutes(pickupTime),
        'payment_method': paymentMethod,
        'lines': [
          for (final e in cart)
            {'menu_item_id': e.item.id, 'quantity': e.quantity, 'note': e.note},
        ],
      };
      final payload = jsonEncode(body);
      if (_pendingPayload != payload || _pendingKey == null) {
        _pendingPayload = payload;
        _pendingKey = List.generate(
          24,
          (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
      }
      // Persist before sending, so a restart after a lost response uses the same key.
      await _saveCart();
      final res = await api.post(
        '/orders',
        auth: ApiRole.student,
        body: {...body, 'request_key': _pendingKey},
      );
      final order = OrderItem.fromApi(Map<String, dynamic>.from(res as Map));
      myOrders = [order, ...myOrders.where((o) => o.id != order.id)];
      clearCart();
      await _cartWrites;
      notifyListeners();
      unawaited(refresh()); // جلب إشعار "تم إرسال طلبك"
      return ActionResult.success(order.id);
    } on ApiException catch (e) {
      return ActionResult.failure(e.message);
    } finally {
      _placingOrder = false;
    }
  }

  Future<ActionResult> cancelOrder(OrderItem order) => _updateOrder(
    () => api.post('/orders/${order.id}/cancel', auth: ApiRole.student),
    success: 'تم إلغاء الطلب',
  );

  static String _isoMinutes(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-${_pad(t.month)}-${_pad(t.day)}T${_pad(t.hour)}:${_pad(t.minute)}';
  static String _pad(int v) => v.toString().padLeft(2, '0');

  Future<ActionResult> markArrived(OrderItem order) => _updateOrder(
    () => api.post('/orders/${order.id}/arrived', auth: ApiRole.student),
  );

  Future<ActionResult> rateOrder(OrderItem order, int stars, String comment) =>
      _updateOrder(
        () => api.post(
          '/orders/${order.id}/rating',
          auth: ApiRole.student,
          body: {'stars': stars, 'comment': comment.trim()},
        ),
        success: 'شكراً لتقييمك! ⭐',
      );

  Future<ActionResult> _updateOrder(
    Future<dynamic> Function() call, {
    String success = '',
  }) async {
    try {
      final updated = OrderItem.fromApi(
        Map<String, dynamic>.from(await call() as Map),
      );
      myOrders = [for (final o in myOrders) o.id == updated.id ? updated : o];
      notifyListeners();
      return ActionResult.success(success);
    } on ApiException catch (e) {
      return ActionResult.failure(e.message);
    }
  }

  /// جلب طلب غير موجود في القائمة المحلية (مثلاً من إشعار قديم)
  Future<OrderItem?> fetchOrder(String id) async {
    try {
      final o = OrderItem.fromApi(
        Map<String, dynamic>.from(
          await api.get('/orders/$id', auth: ApiRole.student) as Map,
        ),
      );
      if (findOrder(id) == null) myOrders = [...myOrders, o];
      notifyListeners();
      return o;
    } on ApiException {
      return null;
    }
  }

  /// "أعد الطلب": يضع أصناف طلب سابق في السلة (المتوفر منها فقط)
  Future<ActionResult> reorder(OrderItem order) async {
    if (order.lines.isEmpty) {
      return const ActionResult.failure('لا يمكن إعادة هذا الطلب.');
    }
    final cafe = cafeteriaById(order.cafeteriaId);
    if (cafe == null) {
      return const ActionResult.failure('الكافيتريا غير موجودة.');
    }
    if (cafe.status == CafeteriaStatus.closed) {
      return const ActionResult.failure('الكافيتريا مغلقة الآن، حاول لاحقاً.');
    }
    try {
      await _fetchMenu(cafe.id);
    } on ApiException catch (e) {
      return ActionResult.failure(e.message);
    }
    clearCart();
    final skipped = <String>[];
    for (final line in order.lines) {
      final item = menus[cafe.id]!.where(
        (m) => m.id == line.menuItemId && m.isAvailable,
      );
      if (item.isEmpty) {
        skipped.add(line.itemName);
        continue;
      }
      addToCart(
        cafe.name,
        item.first,
        quantity: line.quantity,
        note: line.note,
      );
    }
    if (cart.isEmpty) {
      return const ActionResult.failure(
        'كل أصناف هذا الطلب غير متوفرة حالياً.',
      );
    }
    return ActionResult.success(
      skipped.isEmpty
          ? 'تمت إضافة الطلب إلى السلة'
          : 'تمت الإضافة، لكن هذه الأصناف غير متوفرة: ${skipped.join('، ')}',
    );
  }

  // ---------------- المفضلة ----------------
  final Set<int> favoriteIds = {};
  List<MenuItemModel> favoriteItems = [];

  bool isFavorite(MenuItemModel item) => favoriteIds.contains(item.id);

  Future<void> _loadFavorites() async {
    try {
      final data = await api.get('/favorites', auth: ApiRole.student) as List;
      favoriteItems = data
          .map(
            (e) => MenuItemModel.fromApi(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
      favoriteIds
        ..clear()
        ..addAll(favoriteItems.map((m) => m.id!));
    } on ApiException catch (e) {
      connectionError = e.message;
    }
  }

  Future<ActionResult> toggleFavorite(MenuItemModel item) async {
    final id = item.id;
    if (id == null) return const ActionResult.failure('صنف غير صالح');
    final adding = !favoriteIds.contains(id);
    // تحديث فوري في الواجهة ثم المزامنة مع السيرفر
    adding ? favoriteIds.add(id) : favoriteIds.remove(id);
    notifyListeners();
    try {
      adding
          ? await api.put('/favorites/$id', auth: ApiRole.student)
          : await api.delete('/favorites/$id', auth: ApiRole.student);
      await _loadFavorites();
      notifyListeners();
      return const ActionResult.success();
    } on ApiException catch (e) {
      adding ? favoriteIds.remove(id) : favoriteIds.add(id); // تراجع
      notifyListeners();
      return ActionResult.failure(e.message);
    }
  }

  // ---------------- التنقل بين التبويبات ----------------
  static const int ordersTab = 1;
  final StreamController<int> _tabRequests = StreamController.broadcast();
  Stream<int> get onTabRequest => _tabRequests.stream;
  void openTab(int index) => _tabRequests.add(index);

  // ---------------- الإشعارات ----------------
  final List<AppNotification> notifications = [];
  final StreamController<AppNotification> _notificationStream =
      StreamController.broadcast();
  Stream<AppNotification> get onNotification => _notificationStream.stream;
  int _lastNotificationId = 0;
  bool _initialNotificationsLoaded = false;

  int get unreadCount => notifications.where((n) => !n.read).length;

  Future<void> _loadNotifications() async {
    final data =
        await api.get(
              '/notifications',
              auth: ApiRole.student,
              query: {'after_id': '$_lastNotificationId'},
            )
            as List;
    final fresh = data
        .map(
          (e) => AppNotification.fromApi(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
    if (fresh.isEmpty) {
      _initialNotificationsLoaded = true;
      return;
    }
    _lastNotificationId = fresh.first.id; // مرتبة من الأحدث
    notifications.insertAll(0, fresh);
    // الإشعارات القديمة عند فتح التطبيق لا تظهر كتنبيه منبثق
    if (_initialNotificationsLoaded) {
      for (final n in fresh.reversed) {
        _notificationStream.add(n);
      }
    }
    _initialNotificationsLoaded = true;
  }

  Future<void> markAllRead() async {
    if (unreadCount == 0) return;
    for (final n in notifications) {
      n.read = true;
    }
    notifyListeners();
    try {
      await api.post('/notifications/read-all', auth: ApiRole.student);
    } on ApiException {
      // غير مهم: ستُعلَّم كمقروءة في المرة القادمة
    }
  }
}

String formatTime(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour < 12 ? 'ص' : 'م'}';
}

String formatPrice(double v) {
  final s = v.toStringAsFixed(0);
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return '$buf د.ع';
}
