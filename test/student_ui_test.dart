import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wajbati_dashboard/main.dart';
import 'package:wajbati_dashboard/screens/student/student_store.dart';
import 'package:wajbati_dashboard/services/api_client.dart';

/// اختبارات الواجهة مع سيرفر وهمي (MockClient) يحاكي ردود FastAPI
void main() {
  final store = StudentStore.instance;
  var serverDown = false;
  var activeOrder = false; // هل لدى الطالب طلب نشط
  var newNotification = false; // هل يرجع السيرفر إشعاراً جديداً
  var notificationId = 7; // رقم أحدث إشعار في السيرفر الوهمي

  http.Response json(Object body, [int status = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json'},
  );

  final fakeServer = MockClient((req) async {
    if (serverDown) throw http.ClientException('connection refused');
    final path = req.url.path;
    switch (path) {
      case '/auth/login':
        final body = jsonDecode(req.body) as Map;
        if (body['password'] != '123456') {
          return json({'detail': 'كلمة المرور غير صحيحة.'}, 401);
        }
        return json({
          'token': 'fake-token',
          'student': {
            'id': 1,
            'name': 'طالب تجريبي',
            'university_id': '2024001',
            'phone': '07700000000',
          },
        });
      case '/cafeterias':
        return json([
          {
            'id': 1,
            'name': 'كافيتريا علوم حاسوب',
            'location': 'قسم الحاسوب',
            'open_hour': 7,
            'close_hour': 23,
            'status': 'open',
            'manual_status': null,
            'active_orders': 0,
            'available_items': 2,
          },
          {
            'id': 2,
            'name': 'كافيتريا معماري',
            'location': 'المعماري',
            'open_hour': 9,
            'close_hour': 14,
            'status': 'closed',
            'manual_status': null,
            'active_orders': 0,
            'available_items': 3,
          },
        ]);
      case '/cafeterias/1/menu':
        return json([
          {
            'id': 11,
            'cafeteria_id': 1,
            'cafeteria_name': 'كافيتريا علوم حاسوب',
            'name': 'صمون كباب لحم',
            'price': 3000,
            'prep_minutes': 10,
            'available': true,
            'emoji': '🥙',
            'image_url': null,
            'rating_avg': 4.5,
            'rating_count': 2,
          },
          {
            'id': 12,
            'cafeteria_id': 1,
            'cafeteria_name': 'كافيتريا علوم حاسوب',
            'name': 'شاي مهيل',
            'price': 500,
            'prep_minutes': 5,
            'available': false,
            'emoji': '🍵',
            'image_url': null,
            'rating_avg': null,
            'rating_count': 0,
          },
        ]);
      case '/cafeterias/1/slots':
        return json([
          {'time': '2026-11-08T12:00', 'booked': 4, 'available': false},
          {'time': '2026-11-08T12:15', 'booked': 1, 'available': true},
        ]);
      case '/orders/mine':
        return json(
          activeOrder
              ? [
                  {
                    'id': '123456',
                    'status': 'preparing',
                    'cafeteria_id': 1,
                    'cafeteria_name': 'كافيتريا علوم حاسوب',
                    'student_name': 'طالب تجريبي',
                    'student_university_id': '2024001',
                    'lines': [
                      {
                        'menu_item_id': 11,
                        'item_name': 'صمون كباب لحم',
                        'unit_price': 3000,
                        'quantity': 1,
                        'note': 'بدون بصل',
                      },
                    ],
                    'total': 3000,
                    'prep_minutes': 10,
                    'pickup_time': '2026-11-08T12:15',
                    'payment_method': 'نقداً',
                    'arrived': false,
                    'rating': null,
                    'rating_comment': null,
                    'created_at': '2026-11-08T11:50:00',
                  },
                ]
              : [],
        );
      case '/notifications':
        final after =
            int.tryParse(req.url.queryParameters['after_id'] ?? '0') ?? 0;
        return json(
          newNotification && after < notificationId
              ? [
                  {
                    'id': notificationId,
                    'order_id': '123456',
                    'title': 'تحديث على طلبك #123456',
                    'body': 'بدأت الكافيتريا بتحضير طلبك',
                    'read': false,
                    'created_at': '2026-11-08T11:55:00',
                  },
                ]
              : [],
        );
      case '/favorites':
        return json([]);
    }
    return json({'detail': 'غير موجود'}, 404);
  });

  setUp(() async {
    serverDown = false;
    activeOrder = false;
    newNotification = false;
    notificationId = 7;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await ApiClient.instance.init(client: fakeServer);
    store.logout();
  });

  Future<void> login(WidgetTester tester) async {
    await tester.pumpWidget(const WajbatiApp());
    await tester.enterText(find.byType(TextFormField).at(0), '07700000000');
    await tester.enterText(find.byType(TextFormField).at(1), '123456');
    await tester.tap(find.text('تسجيل الدخول'));
    await tester.pumpAndSettle();
  }

  void phoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
  }

  testWidgets(
    'تسجيل الدخول ← الكافيتريات بحالتها ← القائمة (المنتهي واضح) ← السلة ← أوقات الاستلام',
    (tester) async {
      phoneSize(tester);
      await login(tester);
      store.stopWatching();

      expect(find.text('كافيتريا علوم حاسوب'), findsOneWidget);
      expect(find.text('مفتوحة'), findsOneWidget);
      expect(find.text('مغلقة'), findsOneWidget);

      await tester.tap(find.text('كافيتريا علوم حاسوب'));
      await tester.pumpAndSettle();
      expect(find.text('صمون كباب لحم'), findsOneWidget);
      expect(find.text('نفد'), findsOneWidget); // الشاي منتهٍ
      expect(find.text('4.5'), findsOneWidget); // متوسط التقييم من السيرفر

      await tester.tap(find.byTooltip('أضف للسلة').first);
      await tester.pumpAndSettle();
      await tester.pump(
        const Duration(seconds: 3),
      ); // انتظار اختفاء رسالة الإضافة
      await tester.pumpAndSettle();
      expect(store.cartCount, 1);

      await tester.tap(find.text('عرض السلة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('اختيار وقت الاستلام'));
      await tester.pumpAndSettle();
      expect(find.text('ممتلئ'), findsOneWidget); // 12:00 ممتلئ
      expect(find.text('متاح'), findsOneWidget); // 12:15 متاح

      store.logout();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('تتبع الطلب من "طلباتي" والرئيسية تحيل إليها', (tester) async {
    phoneSize(tester);
    activeOrder = true;
    await login(tester);
    store.stopWatching();

    // الرئيسية: تذكير صغير فقط بدل بطاقة التتبع
    expect(find.text('لديك طلب قيد المتابعة'), findsOneWidget);
    await tester.tap(find.text('لديك طلب قيد المتابعة'));
    await tester.pumpAndSettle();

    // "طلباتي": شريط الحالات الأربع + وقت الاستلام + زر "وصلت"
    expect(find.text('الطلبات الحالية'), findsOneWidget);
    for (final label in [
      'تم استلام الطلب',
      'قيد التحضير',
      'جاهز للاستلام',
      'تم التسليم',
    ]) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.textContaining('الاستلام 12:15'), findsOneWidget);
    expect(find.text('وصلت'), findsOneWidget);

    store.logout();
    await tester.pumpAndSettle();
  });

  testWidgets('إشعار الطلب يختفي وحده، ولا يبقى بعد تسجيل الخروج', (
    tester,
  ) async {
    phoneSize(tester);
    await login(tester);
    store.stopWatching();

    newNotification = true;
    await tester.runAsync(store.refresh); // وصل إشعار جديد من السيرفر
    await tester.pumpAndSettle();
    expect(find.text('تحديث على طلبك #123456'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6)); // مدة الإشعار 5 ثوانٍ
    await tester.pumpAndSettle();
    expect(find.text('تحديث على طلبك #123456'), findsNothing);

    // إشعار جديد آخر يظهر، ثم يسجّل الطالب خروجه فوراً: يجب ألا يبقى ظاهراً
    notificationId = 8;
    await tester.runAsync(store.refresh);
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    await tester.tap(find.byIcon(Icons.account_circle_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تسجيل الخروج'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('تسجيل الدخول'), findsOneWidget);
  });

  testWidgets('كلمة مرور خاطئة تعرض رسالة السيرفر', (tester) async {
    await tester.pumpWidget(const WajbatiApp());
    await tester.enterText(find.byType(TextFormField).at(0), '07700000000');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong');
    await tester.tap(find.text('تسجيل الدخول'));
    await tester.pumpAndSettle();
    expect(find.text('كلمة المرور غير صحيحة.'), findsOneWidget);
  });

  testWidgets('انقطاع السيرفر يعرض رسالة واضحة', (tester) async {
    serverDown = true;
    await tester.pumpWidget(const WajbatiApp());
    await tester.enterText(find.byType(TextFormField).at(0), '07700000000');
    await tester.enterText(find.byType(TextFormField).at(1), '123456');
    await tester.tap(find.text('تسجيل الدخول'));
    await tester.pumpAndSettle();
    expect(find.textContaining('تعذّر الاتصال بالسيرفر'), findsOneWidget);
  });

  test('السلة ترفض الكافيتريا المغلقة والأصناف المنتهية', () async {
    expect((await store.login('07700000000', '123456')).ok, isTrue);
    store.stopWatching();
    await store.loadMenu('كافيتريا علوم حاسوب');
    final menu = store.menuFor('كافيتريا علوم حاسوب')!;
    expect(
      store.addToCart('كافيتريا علوم حاسوب', menu[1]).ok,
      isFalse,
    ); // منتهٍ
    expect(
      store.addToCart('كافيتريا علوم حاسوب', menu[0], note: 'بدون بصل').ok,
      isTrue,
    );
    expect(store.addToCart('كافيتريا معماري', menu[0]).ok, isFalse); // مغلقة
    final slots = await store.fetchSlots('كافيتريا علوم حاسوب');
    expect(slots.values.where(store.isSlotAvailable).length, 1);
  });
}
