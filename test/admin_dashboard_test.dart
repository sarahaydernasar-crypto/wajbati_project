import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wajbati_dashboard/models/order_model.dart';
import 'package:wajbati_dashboard/screens/admin/orders_panel.dart';
import 'package:wajbati_dashboard/screens/admin/menu_panel.dart';
import 'package:wajbati_dashboard/screens/dashboard_screen.dart';
import 'package:wajbati_dashboard/screens/student/student_store.dart';
import 'package:wajbati_dashboard/services/api_client.dart';
import 'package:wajbati_dashboard/services/cafeteria_admin_store.dart';

void main() {
  final api = ApiClient.instance;
  final store = CafeteriaAdminStore.instance;
  final now = DateTime(2026, 11, 10, 12);
  Map<String, dynamic> report(String period, {int sales = 6000}) => {
    'period': period,
    'sales': sales,
    'delivered_orders': 2,
    'created_orders': 1,
    'average_order_value': sales ~/ 2,
    'estimated_orders': 0,
    'start_date': '2026-11-04',
    'end_date': '2026-11-10',
    'series': [
      {'date': '2026-11-09', 'sales': 0, 'orders': 0},
      {'date': '2026-11-10', 'sales': sales, 'orders': 2},
    ],
    'top_items': [
      {'name': 'طبق متوفر', 'quantity': 2, 'sales': sales},
    ],
  };
  OrderItem order(String id, String status) => OrderItem(
    id: id,
    studentName: 'طالب اختبار',
    details: 'وجبة ×1',
    cafeteriaName: 'كافيتريا اختبار',
    prepTime: '5 دقائق',
    status: status,
    time: '11:30',
    price: 3000,
    date: now,
    pickupTime: now.subtract(const Duration(minutes: 10)),
  );

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await api.init(
      client: MockClient(
        (request) async => http.Response(
          jsonEncode(report(request.url.queryParameters['period'] ?? 'week')),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    store.logout();
    await api.setToken(ApiRole.cafeteria, 'admin-test-token');
    store.cafeteria = CafeteriaInfo(
      id: 1,
      name: 'كافيتريا اختبار',
      location: '',
      openHour: 7,
      closeHour: 23,
      status: CafeteriaStatus.open,
      serverTime: now,
    );
    store.loaded = true;
    store.orders = [
      order('100001', OrderStatus.received),
      order('100002', OrderStatus.ready),
      order('100003', OrderStatus.delivered),
    ];
    store.menu = [
      MenuItemModel(
        id: 1,
        name: 'طبق متوفر',
        price: '3000',
        preptime: '5 دقائق',
      ),
      MenuItemModel(
        id: 2,
        name: 'طبق غير متوفر',
        price: '2500',
        preptime: '10 دقائق',
        isAvailable: false,
      ),
    ];
    store.report = report('week');
  });

  Widget app(Widget child) => MaterialApp(
    builder: (_, child) =>
        Directionality(textDirection: TextDirection.rtl, child: child!),
    home: child,
  );

  void size(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets(
    'phone navigation separates orders, menu and delivery reports without overflow',
    (tester) async {
      size(tester, const Size(390, 844));
      await tester.pumpWidget(
        app(const DashboardScreen(cafeteriaName: 'كافيتريا اختبار')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('طلبات الكافيتريا'), findsOneWidget);
      expect(find.text('منيو الكافيتريا'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('المنيو'));
      await tester.pumpAndSettle();
      expect(find.text('منيو الكافيتريا'), findsOneWidget);
      expect(find.text('طلبات الكافيتريا'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'غير متوفر (1)'));
      await tester.pumpAndSettle();
      expect(find.text('طبق غير متوفر'), findsOneWidget);
      expect(find.text('طبق متوفر'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('التقارير'));
      await tester.pumpAndSettle();
      expect(find.text('المبيعات والتقارير'), findsOneWidget);
      expect(find.text('طلبات أُنشئت في الفترة'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'اليوم'));
      await tester.pumpAndSettle();
      expect(store.reportPeriod, 'today');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop uses a rail and menu cards preserve the add-photo dialog',
    (tester) async {
      size(tester, const Size(1440, 1000));
      await tester.pumpWidget(
        app(const DashboardScreen(cafeteriaName: 'كافيتريا اختبار')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.tap(find.text('المنيو'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('تغيير صورة طبق متوفر'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'إضافة طبق جديد'));
      await tester.pumpAndSettle();
      expect(find.text('اختر صورة للطبق'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('late filter and pending transition prevent duplicate actions', (
    tester,
  ) async {
    size(tester, const Size(390, 844));
    final gate = Completer<void>();
    var advances = 0;
    await tester.pumpWidget(
      app(
        Scaffold(
          body: OrdersPanel(
            orders: store.orders,
            now: now,
            onAdvance: (_, __) async {
              advances++;
              await gate.future;
            },
            onReject: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'المتأخرة'));
    await tester.pumpAndSettle();
    expect(find.text('#100003'), findsNothing);
    await tester.ensureVisible(find.text('بدء التحضير'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('بدء التحضير'));
    await tester.pump();
    expect(advances, 1);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'جارٍ التحديث...'),
          )
          .onPressed,
      isNull,
    );
    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('حذف الطبق يحتاج تأكيدًا ويمنع الضغط المتكرر أثناء التنفيذ', (
    tester,
  ) async {
    size(tester, const Size(390, 844));
    final items = [...store.menu];
    final gate = Completer<void>();
    var deleted = 0;
    await tester.pumpWidget(
      app(
        Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => MenuPanel(
              items: items,
              onAdd: () {},
              onEdit: (_) async {},
              onImage: (_) async {},
              onAvailability: (_, __) async {},
              onDelete: (item) async {
                deleted++;
                await gate.future;
                update(() => items.remove(item));
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('حذف طبق متوفر'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('حذف طبق متوفر'));
    await tester.pumpAndSettle();
    expect(deleted, 0);
    await tester.tap(find.text('رجوع'));
    await tester.pumpAndSettle();
    expect(deleted, 0);
    await tester.tap(find.byTooltip('حذف طبق متوفر'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'حذف الطبق'));
    await tester.pumpAndSettle();
    expect(deleted, 1);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('طبق متوفر'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test(
    'an older report response cannot replace a more recently selected period',
    () async {
      final replies = <String, Completer<http.Response>>{};
      await api.init(
        client: MockClient((request) {
          final period = request.url.queryParameters['period']!;
          return (replies[period] = Completer<http.Response>()).future;
        }),
      );
      final first = store.selectReport('today');
      final second = store.selectReport('month');
      await Future<void>.delayed(Duration.zero);
      replies['month']!.complete(
        http.Response(
          jsonEncode(report('month', sales: 9000)),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      await second;
      replies['today']!.complete(
        http.Response(
          jsonEncode(report('today', sales: 1000)),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      await first;
      expect(store.reportPeriod, 'month');
      expect(store.report['sales'], 9000);
    },
  );
}
