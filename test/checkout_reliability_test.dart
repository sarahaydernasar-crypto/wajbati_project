import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wajbati_dashboard/models/order_model.dart';
import 'package:wajbati_dashboard/screens/student/student_store.dart';
import 'package:wajbati_dashboard/services/api_client.dart';

void main() {
  final store = StudentStore.instance;
  final api = ApiClient.instance;
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});
  final pickup = DateTime(2026, 11, 10, 12);
  const cafe = 'كافيتريا الاختبار';
  const account = StudentAccount(
    name: 'طالب',
    universityId: '1234',
    phone: '07700000000',
  );
  final item = MenuItemModel(
    id: 1,
    cafeteriaId: 1,
    cafeteriaName: cafe,
    name: 'وجبة',
    price: '3000',
    preptime: '10 دقائق',
  );
  late List<Map<String, dynamic>> attempts;
  late bool loseResponse;
  late Completer<void>? requestGate;

  http.Response response(Object value) => http.Response(
    jsonEncode(value),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    store.logout();
    store.stopWatching();
    SharedPreferences.setMockInitialValues({});
    attempts = [];
    loseResponse = false;
    requestGate = null;
    await api.init(
      client: MockClient((req) async {
        if (req.url.path == '/orders' && req.method == 'POST') {
          attempts.add(jsonDecode(req.body) as Map<String, dynamic>);
          if (requestGate != null) await requestGate!.future;
          if (loseResponse) throw http.ClientException('response lost');
          return response({
            'id': '123456',
            'status': 'received',
            'cafeteria_id': 1,
            'cafeteria_name': cafe,
            'student_name': 'طالب',
            'lines': [],
            'total': 3000,
            'prep_minutes': 10,
            'pickup_time': '2026-11-10T12:00',
            'created_at': '2026-11-10T11:30:00',
          });
        }
        if (req.url.path == '/me') {
          return response({
            'name': 'طالب',
            'university_id': '1234',
            'phone': '07700000000',
          });
        }
        if (req.url.path == '/cafeterias') {
          return response([
            {
              'id': 1,
              'name': cafe,
              'location': '',
              'open_hour': 7,
              'close_hour': 23,
              'status': 'open',
            },
          ]);
        }
        if (req.url.path.endsWith('/menu')) {
          return response([
            {
              'id': 1,
              'cafeteria_id': 1,
              'cafeteria_name': cafe,
              'name': 'وجبة',
              'price': 3000,
              'prep_minutes': 10,
              'available': true,
            },
          ]);
        }
        return response([]);
      }),
    );
    store.currentStudent = account;
    await api.setToken(ApiRole.student, 'test-session');
    store.cafeterias[cafe] = const CafeteriaInfo(
      id: 1,
      name: cafe,
      location: '',
      openHour: 7,
      closeHour: 23,
      status: CafeteriaStatus.open,
    );
    store.menus.clear();
    store.addToCart(cafe, item, note: 'بدون بصل');
  });

  tearDown(() async {
    await store.refresh();
    store.logout();
    store.stopWatching();
  });

  test(
    'lost checkout response retains the same attempt after restarting the session',
    () async {
      loseResponse = true;
      expect(
        (await store.placeOrder(pickupTime: pickup, paymentMethod: 'نقداً')).ok,
        isFalse,
      );
      final key = attempts.single['request_key'];
      store.logout();
      await api.setToken(ApiRole.student, 'test-session');
      await store.init();
      store.stopWatching();
      expect(store.cart.single.note, 'بدون بصل');
      loseResponse = false;
      expect(
        (await store.placeOrder(pickupTime: pickup, paymentMethod: 'نقداً')).ok,
        isTrue,
      );
      expect(attempts.last['request_key'], key);
      expect(store.cart, isEmpty);
      store.logout();
      await api.setToken(ApiRole.student, 'test-session');
      await store.init();
      store.stopWatching();
      expect(store.cart, isEmpty);
    },
  );

  test('concurrent confirmation sends one HTTP request', () async {
    requestGate = Completer<void>();
    final first = store.placeOrder(pickupTime: pickup, paymentMethod: 'نقداً');
    expect(
      (await store.placeOrder(pickupTime: pickup, paymentMethod: 'نقداً')).ok,
      isFalse,
    );
    requestGate!.complete();
    expect((await first).ok, isTrue);
    expect(attempts, hasLength(1));
  });

  test('terminal states do not appear as active orders', () {
    expect(OrderStatus.isActive(OrderStatus.cancelled), isFalse);
    expect(OrderStatus.isActive(OrderStatus.rejected), isFalse);
    expect(OrderStatus.isActive(OrderStatus.ready), isTrue);
  });
}
