import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/order_model.dart';
import '../screens/student/student_store.dart'
    show CafeteriaInfo, CafeteriaStatus, ActionResult;
import 'api_client.dart';

/// حالة لوحة تحكم مسؤول الكافيتريا (مربوطة بالسيرفر)
class CafeteriaAdminStore extends ChangeNotifier {
  CafeteriaAdminStore._();
  static final CafeteriaAdminStore instance = CafeteriaAdminStore._();

  final ApiClient api = ApiClient.instance;
  static const pollInterval = Duration(seconds: 3);

  CafeteriaInfo? cafeteria;
  List<OrderItem> orders = [];
  List<MenuItemModel> menu = [];
  int weeklyRevenue = 0;
  int weeklyOrders = 0;
  Map<String, dynamic> dailySummary = {};
  Map<String, dynamic> report = {};
  String reportPeriod = 'week';
  DateTime? reportStart;
  DateTime? reportEnd;
  bool reportLoading = false;
  String? reportError;
  int _reportRequest = 0;
  String? connectionError;
  bool loaded = false;

  Timer? _poller;
  bool _refreshing = false;

  // تنبيه الطلبات الجديدة: الأرقام التي رأيناها سابقاً
  final Set<String> _seenOrderIds = {};
  final StreamController<List<OrderItem>> _newOrders =
      StreamController.broadcast();
  Stream<List<OrderItem>> get onNewOrders => _newOrders.stream;
  bool soundEnabled = true;

  void toggleSound() {
    soundEnabled = !soundEnabled;
    notifyListeners();
  }

  bool get isLoggedIn => cafeteria != null;

  /// قائمة الكافيتريات لشاشة الدخول
  Future<List<CafeteriaInfo>> fetchCafeterias() async {
    final data = await api.get('/cafeterias') as List;
    return data
        .map((e) => CafeteriaInfo.fromApi(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<ActionResult> login(int cafeteriaId, String code) async {
    try {
      final res = Map<String, dynamic>.from(
        await api.post(
              '/admin/login',
              body: {'cafeteria_id': cafeteriaId, 'code': code.trim()},
            )
            as Map,
      );
      await api.setToken(ApiRole.cafeteria, res['token'] as String);
      cafeteria = CafeteriaInfo.fromApi(
        Map<String, dynamic>.from(res['cafeteria'] as Map),
      );
      loaded = false;
      await refresh();
      _poller?.cancel();
      _poller = Timer.periodic(pollInterval, (_) => refresh());
      return const ActionResult.success();
    } on ApiException catch (e) {
      return ActionResult.failure(e.message);
    }
  }

  void logout() {
    _poller?.cancel();
    api.setToken(ApiRole.cafeteria, null);
    cafeteria = null;
    orders = [];
    menu = [];
    loaded = false;
    _reportRequest++;
    report = {};
    reportPeriod = 'week';
    reportStart = null;
    reportEnd = null;
    reportLoading = false;
    reportError = null;
    _seenOrderIds.clear();
    notifyListeners();
  }

  Future<void> refresh() async {
    final cafe = cafeteria;
    if (cafe == null || _refreshing) return;
    _refreshing = true;
    try {
      final me = await api.get('/admin/me', auth: ApiRole.cafeteria);
      cafeteria = CafeteriaInfo.fromApi(Map<String, dynamic>.from(me as Map));
      final o = await api.get('/admin/orders', auth: ApiRole.cafeteria) as List;
      orders = o
          .map((e) => OrderItem.fromApi(Map<String, dynamic>.from(e as Map)))
          .toList();
      // الطلبات الجديدة منذ آخر تحديث (لا تنبيه عند أول تحميل بعد الدخول)
      final fresh = orders
          .where((x) => x.status == 'received' && !_seenOrderIds.contains(x.id))
          .toList();
      final firstLoad = !loaded;
      _seenOrderIds.addAll(orders.map((x) => x.id));
      if (!firstLoad && fresh.isNotEmpty) _newOrders.add(fresh);
      final m = await api.get('/cafeterias/${cafe.id}/menu') as List;
      menu = m
          .map(
            (e) => MenuItemModel.fromApi(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
      final r = Map<String, dynamic>.from(
        await api.get('/admin/revenue', auth: ApiRole.cafeteria) as Map,
      );
      weeklyRevenue = r['total'] as int;
      weeklyOrders = r['orders'] as int;
      dailySummary = Map<String, dynamic>.from(
        await api.get('/admin/summary', auth: ApiRole.cafeteria) as Map,
      );
      await loadReport();
      connectionError = null;
      loaded = true;
    } on ApiException catch (e) {
      connectionError = e.message;
      if (e.isUnauthorized) logout();
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  Future<ActionResult> _run(
    Future<dynamic> Function() call, [
    String success = '',
  ]) async {
    try {
      await call();
      await refresh();
      return ActionResult.success(success);
    } on ApiException catch (e) {
      return ActionResult.failure(e.message);
    }
  }

  Future<void> selectReport(
    String period, {
    DateTime? start,
    DateTime? end,
  }) async {
    reportPeriod = period;
    reportStart = start;
    reportEnd = end;
    report = {};
    await loadReport(showLoading: true);
  }

  Future<void> loadReport({bool showLoading = false}) async {
    if (cafeteria == null) return;
    final request = ++_reportRequest;
    if (showLoading) {
      reportLoading = true;
      notifyListeners();
    }
    try {
      String day(DateTime date) =>
          '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final result = await api.get(
        '/admin/reports',
        auth: ApiRole.cafeteria,
        query: {
          'period': reportPeriod,
          if (reportStart != null) 'start_date': day(reportStart!),
          if (reportEnd != null) 'end_date': day(reportEnd!),
        },
      );
      if (request != _reportRequest) return;
      report = Map<String, dynamic>.from(result as Map);
      reportError = null;
    } on ApiException catch (e) {
      if (request == _reportRequest) reportError = e.message;
    } finally {
      if (request == _reportRequest) {
        reportLoading = false;
        notifyListeners();
      }
    }
  }

  Future<ActionResult> setOrderStatus(OrderItem order, String status) => _run(
    () => api.patch(
      '/admin/orders/${order.id}/status',
      auth: ApiRole.cafeteria,
      body: {'status': status},
    ),
  );

  Future<ActionResult> rejectOrder(OrderItem order, String reason) => _run(
    () => api.post(
      '/admin/orders/${order.id}/reject',
      auth: ApiRole.cafeteria,
      body: {'reason': reason.trim()},
    ),
    'تم رفض الطلب وإبلاغ الطالب بالسبب',
  );

  /// ماسح QR: محتوى الرمز هو رقم الطلب
  Future<ActionResult> scan(String code) async {
    try {
      final o = OrderItem.fromApi(
        Map<String, dynamic>.from(
          await api.post(
                '/admin/scan',
                auth: ApiRole.cafeteria,
                body: {'code': code.trim()},
              )
              as Map,
        ),
      );
      await refresh();
      return ActionResult.success(
        'تم تأكيد استلام الطلب رقم (${o.id}) - ${o.studentName} بنجاح!',
      );
    } on ApiException catch (e) {
      return ActionResult.failure(e.message);
    }
  }

  Future<ActionResult> setCafeteriaStatus(CafeteriaStatus? status) => _run(
    () => api.put(
      '/admin/status',
      auth: ApiRole.cafeteria,
      body: {'status': status?.name},
    ),
    status == null
        ? 'الحالة الآن تلقائية حسب الدوام والازدحام'
        : 'تم تحديث حالة الكافيتريا للطلاب',
  );

  Future<ActionResult> addMenuItem(
    String name,
    int price,
    int prepMinutes, {
    List<int>? imageBytes,
    String? imageFilename,
    List<String> ingredients = const [],
    List<String> removableIngredients = const [],
  }) => _run(
    () => imageBytes != null
        ? api.upload(
            '/admin/menu/with-image',
            imageBytes,
            imageFilename ?? 'meal.jpg',
            auth: ApiRole.cafeteria,
            fields: {
              'name': name.trim(),
              'price': '$price',
              'prep_minutes': '$prepMinutes',
              'ingredients': jsonEncode(ingredients),
              'removable_ingredients': jsonEncode(removableIngredients),
            },
          )
        : api.post(
            '/admin/menu',
            auth: ApiRole.cafeteria,
            body: {
              'name': name.trim(),
              'price': price,
              'prep_minutes': prepMinutes,
              'ingredients': ingredients,
              'removable_ingredients': removableIngredients,
            },
          ),
    'تمت إضافة الوجبة للمنيو',
  );

  Future<ActionResult> setAvailable(MenuItemModel item, bool available) => _run(
    () => api.patch(
      '/admin/menu/${item.id}',
      auth: ApiRole.cafeteria,
      body: {'available': available},
    ),
  );

  Future<ActionResult> editMenuItem(
    MenuItemModel item,
    String name,
    int price,
    int prepMinutes, {
    List<String> ingredients = const [],
    List<String> removableIngredients = const [],
  }) => _run(
    () => api.patch(
      '/admin/menu/${item.id}',
      auth: ApiRole.cafeteria,
      body: {
        'name': name.trim(),
        'price': price,
        'prep_minutes': prepMinutes,
        'ingredients': ingredients,
        'removable_ingredients': removableIngredients,
      },
    ),
    'تم تعديل الوجبة',
  );

  Future<ActionResult> uploadImage(
    MenuItemModel item,
    List<int> bytes,
    String filename,
  ) => _run(
    () => api.upload(
      '/admin/menu/${item.id}/image',
      bytes,
      filename,
      auth: ApiRole.cafeteria,
    ),
    'تم رفع صورة "${item.name}"',
  );

  Future<ActionResult> deleteImage(MenuItemModel item) => _run(
    () => api.delete('/admin/menu/${item.id}/image', auth: ApiRole.cafeteria),
    'تم حذف الصورة',
  );

  Future<ActionResult> deleteMenuItem(MenuItemModel item) => _run(
    () => api.delete('/admin/menu/${item.id}', auth: ApiRole.cafeteria),
    'تم حذف الوجبة من المنيو بنجاح!',
  );
}
