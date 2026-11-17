import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wajbati_dashboard/main.dart';
import 'package:wajbati_dashboard/widgets/cart_dock.dart';
import 'package:wajbati_dashboard/screens/student/student_store.dart';
import 'package:wajbati_dashboard/services/api_client.dart';

/// اختبارات الواجهة مع سيرفر وهمي (MockClient) يحاكي ردود FastAPI
void main() {
  final store = StudentStore.instance;
  var serverDown = false;
  var activeOrder = false; // هل لدى الطالب طلب نشط
  var teaAvailable = false;
  var newNotification = false; // هل يرجع السيرفر إشعاراً جديداً
  var notificationId = 7; // رقم أحدث إشعار في السيرفر الوهمي
  Map<String, dynamic>? registrationBody;

  http.Response json(Object body, [int status = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json'},
  );

  final fakeServer = MockClient((req) async {
    if (serverDown) throw http.ClientException('connection refused');
    final path = req.url.path;
    switch (path) {
      case '/auth/register':
        registrationBody = Map<String, dynamic>.from(
          jsonDecode(req.body) as Map,
        );
        return json({
          'token': 'new-student-token',
          'student': {
            'id': 2,
            'name': registrationBody!['name'],
            'university_id': '',
            'phone': registrationBody!['phone'],
          },
        }, 201);
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
            'ingredients': ['خبز', 'لحم', 'بصل', 'طماطم'],
            'removable_ingredients': ['بصل', 'طماطم'],
          },
          {
            'id': 12,
            'cafeteria_id': 1,
            'cafeteria_name': 'كافيتريا علوم حاسوب',
            'name': 'شاي مهيل',
            'price': 500,
            'prep_minutes': 5,
            'available': teaAvailable,
            'emoji': '🍵',
            'image_url': null,
            'rating_avg': null,
            'rating_count': 0,
            'ingredients': ['شاي', 'ماء', 'هيل', 'سكر'],
            'removable_ingredients': ['سكر'],
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
    teaAvailable = false;
    newNotification = false;
    notificationId = 7;
    registrationBody = null;
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

  testWidgets('إنشاء الحساب دون رقم جامعي وملاحظات الطبق دون خيار السكر', (
    tester,
  ) async {
    phoneSize(tester);
    await tester.pumpWidget(const WajbatiApp());
    await tester.tap(find.text('أنشئ حساباً'));
    await tester.pumpAndSettle();
    expect(find.text('الرقم الجامعي'), findsNothing);
    expect(find.byType(TextFormField), findsNWidgets(4));
    await tester.enterText(find.byType(TextFormField).at(0), 'طالب جديد');
    await tester.enterText(find.byType(TextFormField).at(1), '07711113333');
    await tester.enterText(find.byType(TextFormField).at(2), 'secret1');
    await tester.enterText(find.byType(TextFormField).at(3), 'secret1');
    await tester.tap(find.text('إنشاء الحساب'));
    await tester.pumpAndSettle();
    store.stopWatching();
    expect(store.isLoggedIn, isTrue);
    expect(registrationBody!.containsKey('university_id'), isFalse);
    expect(registrationBody!['phone'], '07711113333');
    await tester.tap(find.text('كافيتريا علوم حاسوب'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('صمون كباب لحم'));
    await tester.pumpAndSettle();
    expect(find.text('بدون بصل'), findsOneWidget);
    expect(find.text('بدون سكر'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('الشاي يسمح بإزالة السكر فقط ويحفظ الاختيار دون تكرار', (
    tester,
  ) async {
    phoneSize(tester);
    teaAvailable = true;
    await login(tester);
    store.stopWatching();
    await tester.tap(find.text('كافيتريا علوم حاسوب'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('شاي مهيل'),
      350,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('شاي مهيل'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('شاي مهيل'));
    await tester.pumpAndSettle();
    expect(find.text('شاي، ماء، هيل، سكر'), findsOneWidget);
    expect(find.byType(FilterChip), findsOneWidget);
    expect(find.text('بدون بصل'), findsNothing);
    expect(find.text('صوص إضافي'), findsNothing);
    final sugar = find.widgetWithText(FilterChip, 'بدون سكر');
    await tester.tap(sugar);
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(sugar).selected, isTrue);
    await tester.tap(sugar);
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(sugar).selected, isFalse);
    await tester.tap(sugar);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('أضف للسلة •'));
    await tester.pumpAndSettle();
    expect(store.cart.single.note, 'بدون سكر');
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('بطاقة الطلب الحالي تعرض الحالة وتفتح التتبع مباشرة', (
    tester,
  ) async {
    phoneSize(tester);
    activeOrder = true;
    await login(tester);
    store.stopWatching();

    expect(find.text('طلبك الحالي'), findsOneWidget);
    expect(find.text('#123456'), findsOneWidget);
    expect(find.textContaining('موعد الاستلام 12:15'), findsOneWidget);
    await tester.tap(find.text('تتبع الطلب'));
    await tester.pumpAndSettle();

    expect(find.text('طلب #123456'), findsOneWidget);
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

  testWidgets('تعديل الكمية من بطاقة الطبق يحدّث السلة ويمنع تجاوز الحد', (
    tester,
  ) async {
    phoneSize(tester);
    await login(tester);
    store.stopWatching();
    await tester.tap(find.text('كافيتريا علوم حاسوب'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('أضف للسلة').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('أضف للسلة').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('زيادة كمية صمون كباب لحم'));
    await tester.pumpAndSettle();
    expect(store.cartCount, 2);
    expect(tester.widget<CartDock>(find.byType(CartDock)).total, 6000);
    store.changeQuantity(store.cart.single, 18);
    await tester.pumpAndSettle();
    expect(store.cartCount, 20);
    final plus = find.widgetWithIcon(IconButton, Icons.add);
    expect(tester.widget<IconButton>(plus).onPressed, isNull);
    store.changeQuantity(store.cart.single, -19);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('تقليل كمية صمون كباب لحم'));
    await tester.pumpAndSettle();
    expect(store.cartCount, 0);
    expect(find.text('عرض السلة'), findsNothing);
    expect(tester.takeException(), isNull);
    store.logout();
    await tester.pumpAndSettle();
  });

  testWidgets('شريط السلة ثابت ويبقى عند العودة للرئيسية وتغيير التبويب', (
    tester,
  ) async {
    phoneSize(tester);
    await login(tester);
    store.stopWatching();
    await tester.tap(find.text('كافيتريا علوم حاسوب'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('أضف للسلة').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('أضف للسلة').first);
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.byType(CartDock));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(CartDock)), before);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('عرض السلة'), findsOneWidget);
    await tester.tap(find.text('المفضلة'));
    await tester.pumpAndSettle();
    expect(find.text('عرض السلة'), findsOneWidget);
    expect(tester.widget<CartDock>(find.byType(CartDock)).count, 1);
    store.clearCart();
    await tester.pumpAndSettle();
    expect(find.text('عرض السلة'), findsNothing);
    store.logout();
    await tester.pumpAndSettle();
  });

  testWidgets('الواجهة تتكيف مع خط أكبر وتقليل الحركة', (tester) async {
    phoneSize(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await login(tester);
    store.stopWatching();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('كافيتريا علوم حاسوب'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('أضف للسلة').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('أضف للسلة').first);
    await tester.pumpAndSettle();
    expect(find.text('عرض السلة'), findsOneWidget);
    expect(tester.takeException(), isNull);
    store.logout();
    await tester.pumpAndSettle();
  });

  testWidgets('تحميل بدء التطبيق يعرض حالة واضحة وإعادة المحاولة عند الفشل', (
    tester,
  ) async {
    var attempts = 0;
    final gate = Completer<void>();
    await tester.pumpWidget(
      WajbatiBootstrap(
        initialize: () async {
          attempts++;
          if (attempts == 1) {
            await gate.future;
            throw Exception('startup failed');
          }
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('نجهّز لك وجباتي...'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('تعذّر تجهيز التطبيق. أعد المحاولة.'), findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(find.text('تسجيل الدخول'), findsOneWidget);
    expect(attempts, 2);
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
