import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wajbati_dashboard/screens/menu_item_editor_dialog.dart';
import 'package:wajbati_dashboard/services/api_client.dart';
import 'package:wajbati_dashboard/services/cafeteria_admin_store.dart';

void main() {
  final api = ApiClient.instance;
  late List<http.Request> requests;
  late bool rejectUpload;
  Completer<void>? pendingSave;

  setUp(() async {
    requests = [];
    rejectUpload = false;
    pendingSave = null;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await api.init(
      client: MockClient((request) async {
        requests.add(request);
        if (pendingSave != null) await pendingSave!.future;
        return http.Response(
          jsonEncode(rejectUpload ? {'detail': 'تعذّر حفظ الصورة'} : {}),
          rejectUpload ? 400 : 201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    CafeteriaAdminStore.instance.logout();
    await api.setToken(ApiRole.cafeteria, 'admin-test-token');
  });

  Future<void> open(
    WidgetTester tester,
    Future<XFile?> Function() picker,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => MenuItemEditorDialog(pickImage: picker),
                ),
                child: const Text('افتح الإضافة'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('افتح الإضافة'));
    await tester.pumpAndSettle();
  }

  Future<XFile> png(WidgetTester tester) async {
    return (await tester.runAsync(() async {
      final imageReady = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        Uint8List.fromList([255, 128, 0, 255]),
        1,
        1,
        ui.PixelFormat.rgba8888,
        imageReady.complete,
      );
      final image = await imageReady.future;
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return XFile.fromData(
        bytes!.buffer.asUint8List(),
        name: 'meal.png',
        path: 'meal.png',
        mimeType: 'image/png',
      );
    }))!;
  }

  Future<void> choose(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.text('اختر صورة للطبق'));
      // Real image decoding completes outside the fake test clock.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField).at(0), 'طبق جديد');
    await tester.enterText(find.byType(TextFormField).at(1), '4500');
    await tester.enterText(find.byType(TextFormField).at(2), '12');
  }

  testWidgets(
    'preview and atomic multipart save retain image and fields on failure',
    (tester) async {
      final file = await png(tester);
      await open(tester, () async => file);
      await choose(tester);
      expect(find.byType(Image), findsOneWidget);
      await fill(tester);
      rejectUpload = true;
      await tester.tap(find.text('إضافة إلى المنيو'));
      await tester.pumpAndSettle();
      expect(find.text('تعذّر حفظ الصورة'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('طبق جديد'), findsOneWidget);
      expect(requests.single.url.path, '/admin/menu/with-image');
      final body = utf8.decode(requests.single.bodyBytes, allowMalformed: true);
      expect(body, contains('filename="meal.png"'));
      expect(body, contains('name="price"\r\n\r\n4500'));
      rejectUpload = false;
      pendingSave = Completer<void>();
      await tester.tap(find.text('إضافة إلى المنيو'));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'جارٍ الحفظ...'),
            )
            .onPressed,
        isNull,
      );
      pendingSave!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemEditorDialog), findsNothing);
      expect(requests, hasLength(2));
    },
  );

  testWidgets(
    'removing the selected photo saves a normal item without uploading',
    (tester) async {
      final file = await png(tester);
      await open(tester, () async => file);
      await choose(tester);
      await tester.tap(find.byTooltip('إزالة الصورة'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      await fill(tester);
      await tester.tap(find.text('إضافة إلى المنيو'));
      await tester.pumpAndSettle();
      expect(requests.single.url.path, '/admin/menu');
      expect(jsonDecode(requests.single.body)['name'], 'طبق جديد');
    },
  );

  testWidgets('حفظ مكونات الطبق والمكونات الاختيارية فقط', (tester) async {
    await open(tester, () async => null);
    await fill(tester);
    await tester.enterText(
      find.byType(TextFormField).at(3),
      'شاي، ماء، سكر، سكر',
    );
    await tester.pumpAndSettle();
    final sugar = find.widgetWithText(FilterChip, 'سكر');
    await tester.ensureVisible(sugar);
    await tester.tap(sugar);
    await tester.pumpAndSettle();
    await tester.tap(find.text('إضافة إلى المنيو'));
    await tester.pumpAndSettle();
    final body = jsonDecode(requests.single.body) as Map;
    expect(body['ingredients'], ['شاي', 'ماء', 'سكر']);
    expect(body['removable_ingredients'], ['سكر']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone form scrolls and rejects oversized images before upload', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await open(
      tester,
      () async =>
          XFile.fromData(Uint8List(2 * 1024 * 1024 + 1), name: 'large.png'),
    );
    await choose(tester);
    expect(
      find.text('حجم الصورة أكبر من 2 ميغابايت. اختر صورة أصغر.'),
      findsOneWidget,
    );
    expect(requests, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
  });
}
