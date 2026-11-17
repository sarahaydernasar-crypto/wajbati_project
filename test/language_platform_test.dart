import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wajbati_dashboard/main.dart';
import 'package:wajbati_dashboard/localization/app_language.dart';
import 'package:wajbati_dashboard/screens/student/student_store.dart';
import 'package:wajbati_dashboard/services/api_client.dart';

void main() {
  final api = ApiClient.instance;
  late List<http.Request> requests;
  late List<Map<String, dynamic>> cafes;
  Completer<void>? pendingCreation;

  setUp(() async {
    requests = [];
    cafes = [
      {
        'id': 1,
        'name': 'كافيتريا العلوم',
        'location': 'بناية العلوم',
        'open_hour': 8,
        'close_hour': 16,
      },
    ];
    pendingCreation = null;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await AppLanguage.instance.setLanguage('ar');
    await api.init(
      client: MockClient((request) async {
        requests.add(request);
        dynamic body;
        switch (request.url.path) {
          case '/platform/login':
            body = {'token': 'platform-session', 'username': 'admin'};
            break;
          case '/platform/me':
            expect(request.headers['Authorization'], 'Bearer platform-session');
            body = {'username': 'admin'};
            break;
          case '/platform/cafeterias':
            expect(request.headers['Authorization'], 'Bearer platform-session');
            if (request.method == 'POST') {
              if (pendingCreation != null) await pendingCreation!.future;
              final data = Map<String, dynamic>.from(
                jsonDecode(request.body) as Map,
              )..remove('code');
              cafes.add({'id': 2, ...data});
              body = cafes.last;
            } else {
              body = cafes;
            }
            break;
          default:
            body = [];
        }
        return http.Response.bytes(
          utf8.encode(jsonEncode(body)),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    StudentStore.instance.logout();
    StudentStore.instance.stopWatching();
  });

  tearDown(() async {
    await AppLanguage.instance.setLanguage('ar');
  });

  testWidgets(
    'language switches direction and labels without losing entered data or route',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const WajbatiApp());
      await tester.enterText(find.byType(TextFormField).at(0), '07711113333');
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(
        find.text('Welcome to Wajbati', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Phone number'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(TextFormField).first)),
        TextDirection.ltr,
      );
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        '07711113333',
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          AppLanguage.preferenceKey,
        ),
        'en',
      );
      await tester.tap(find.text('Create an account', findRichText: true));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'طالب جديد');
      await tester.tap(find.text('العربية'));
      await tester.pumpAndSettle();
      expect(find.text('إنشاء حساب طالب'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'طالب جديد',
      );
      expect(
        Directionality.of(tester.element(find.byType(TextFormField).first)),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('saved language and dynamic phrases are restored', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppLanguage.preferenceKey, 'en');
    await AppLanguage.instance.init();
    expect(AppLanguage.instance.isEnglish, isTrue);
    expect(AppLanguage.instance.translate('بدون سكر'), 'Without Sugar');
    expect(
      AppLanguage.instance.translate('المجموع • 3 قطعة'),
      'Total • 3 items',
    );
    expect(AppLanguage.instance.translate('3,000 د.ع'), '3,000 IQD');
    expect(
      AppLanguage.instance.translate('شاي، ماء، سكر'),
      'Tea, Water, Sugar',
    );
    expect(
      AppLanguage.instance.translate('موعد الاستلام 12:30 م • 17/11'),
      'Pickup 12:30 PM • 17/11',
    );
    expect(
      AppLanguage.instance.translate('تم إرسال طلبك #123456'),
      'Order #123456 sent',
    );
    expect(
      AppLanguage.instance.translate('تحديث على طلبك #123456'),
      'Update for order #123456',
    );
    expect(
      AppLanguage.instance.translate(
        'تم إرسال طلبك #123456 بنجاح! تابع حالته من هنا',
      ),
      'Order #123456 sent! Track it here.',
    );
  });

  testWidgets(
    'platform admin adds a cafeteria with a separate token and prevents duplicate submission',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await api.setToken(ApiRole.student, 'student-session');
      await tester.pumpWidget(const WajbatiApp());
      await tester.ensureVisible(find.text('إدارة المنصة'));
      await tester.tap(find.text('إدارة المنصة'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'platform-secret-123',
      );
      await tester.tap(find.text('تسجيل الدخول'));
      await tester.pumpAndSettle();
      expect(api.studentToken, 'student-session');
      expect(api.platformToken, 'platform-session');
      expect(find.text('إدارة الكافيتريات'), findsOneWidget);
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(
        find.text('Manage cafeterias', findRichText: true),
        findsOneWidget,
      );
      await tester.tap(find.text('Add cafeteria', findRichText: true));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'كافيتريا جديدة',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'بناية جديدة');
      await tester.enterText(find.byType(TextFormField).at(2), '9');
      await tester.enterText(find.byType(TextFormField).at(3), '18');
      await tester.enterText(find.byType(TextFormField).at(4), 'NewCafe-2026!');
      pendingCreation = Completer<void>();
      final save = find.widgetWithText(FilledButton, 'إضافة كافيتريا').last;
      await tester.tap(save);
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'جارٍ الحفظ...'),
            )
            .onPressed,
        isNull,
      );
      final posts = requests.where(
        (r) => r.url.path == '/platform/cafeterias' && r.method == 'POST',
      );
      expect(posts, hasLength(1));
      expect(jsonDecode(posts.single.body)['open_hour'], 9);
      pendingCreation!.complete();
      await tester.pumpAndSettle();
      expect(find.text('كافيتريا جديدة'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
