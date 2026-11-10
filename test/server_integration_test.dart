// اختبار تدفق الطلب كاملاً مع السيرفر الحقيقي (FastAPI).
// شغّل السيرفر أولاً ثم:
//   flutter test test/server_integration_test.dart --dart-define=WAJBATI_API=http://localhost:8000
// يتم تخطي الاختبار تلقائياً إذا لم يكن WAJBATI_API محدداً أو كان السيرفر لا يعمل.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wajbati_dashboard/screens/student/student_store.dart';
import 'package:wajbati_dashboard/services/api_client.dart';
import 'package:wajbati_dashboard/services/cafeteria_admin_store.dart';

const apiUrl = String.fromEnvironment('WAJBATI_API');

const codes = {
  'كافيتريا علوم حاسوب': 'CS771SOL',
  'كافيتريا العلوم التطبيقية': 'AP882APP',
  'كافيتريا كهرومكانيك': 'EM993MEH',
  'كافيتريا طب حياتي': 'BM445BIO',
  'كافيتريا معماري': 'AR556ARC',
};

void main() {
  final api = ApiClient.instance;
  final student = StudentStore.instance;
  final admin = CafeteriaAdminStore.instance;

  test(
    'تدفق كامل مع السيرفر: تسجيل ← طلب ← لوحة التحكم ← إشعارات ← QR ← تقييم ← أعد الطلب',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await api.init();
      await api.setBaseUrl(apiUrl);
      if (!await api.ping()) {
        markTestSkipped('السيرفر لا يعمل على $apiUrl');
        return;
      }

      // 1) إنشاء حساب جديد
      final phone =
          '0779${Random().nextInt(9999999).toString().padLeft(7, '0')}';
      final uni = '${Random().nextInt(99999999) + 10000}';
      final reg = await student.register(
        name: 'طالب اختبار',
        universityId: uni,
        phone: phone,
        password: 'secret1',
      );
      expect(reg.ok, isTrue, reason: reg.message);
      student.stopWatching();

      // 2) اختيار كافيتريا مفتوحة فيها أوقات متاحة
      String? cafeteria;
      for (final c in student.cafeteriaList.where(
        (c) => c.status != CafeteriaStatus.closed,
      )) {
        await student.loadMenu(c.name);
        final item = student.menuFor(c.name)!.firstWhere((m) => m.isAvailable);
        student.clearCart();
        student.addToCart(c.name, item, quantity: 2, note: 'بدون بصل');
        if ((await student.fetchSlots(
          c.name,
        )).values.any(student.isSlotAvailable)) {
          cafeteria = c.name;
          break;
        }
      }
      if (cafeteria == null) {
        markTestSkipped('كل الكافيتريات مغلقة الآن (خارج أوقات الدوام)');
        return;
      }

      // 3) الطلب
      final slots = await student.fetchSlots(cafeteria);
      final slot = slots.entries
          .firstWhere((e) => student.isSlotAvailable(e.value))
          .key;
      final placed = await student.placeOrder(
        pickupTime: slot,
        paymentMethod: 'نقداً عند الاستلام',
      );
      expect(placed.ok, isTrue, reason: placed.message);
      final orderId = placed.message;
      expect(student.findOrder(orderId)!.status, OrderStatus.received);

      // 4) وصلت
      expect(
        (await student.markArrived(student.findOrder(orderId)!)).ok,
        isTrue,
      );

      // 5) لوحة الكافيتريا تستقبل الطلب وتغيّر حالته
      final cafeId = student.cafeterias[cafeteria]!.id;
      final login = await admin.login(cafeId, codes[cafeteria]!);
      expect(login.ok, isTrue, reason: login.message);
      final adminOrder = admin.orders.firstWhere((o) => o.id == orderId);
      expect(adminOrder.studentArrived, isTrue);
      expect(adminOrder.details, contains('بدون بصل'));
      expect(
        (await admin.setOrderStatus(adminOrder, OrderStatus.preparing)).ok,
        isTrue,
      );
      expect(
        (await admin.setOrderStatus(adminOrder, OrderStatus.ready)).ok,
        isTrue,
      );
      final scan = await admin.scan(orderId);
      expect(scan.ok, isTrue, reason: scan.message);
      expect((await admin.scan(orderId)).ok, isFalse); // مسح مكرر
      admin.logout();

      // 6) الطالب يرى التحديث والإشعارات
      await student.refresh();
      final order = student.findOrder(orderId)!;
      expect(order.status, OrderStatus.delivered);
      expect(student.notifications.length, greaterThanOrEqualTo(4));

      // 7) التقييم و"أعد الطلب"
      expect((await student.rateOrder(order, 5, 'ممتاز')).ok, isTrue);
      expect(
        (await student.rateOrder(student.findOrder(orderId)!, 4, '')).ok,
        isFalse,
      ); // مرة واحدة فقط
      final re = await student.reorder(student.findOrder(orderId)!);
      expect(re.ok, isTrue, reason: re.message);
      expect(student.cart.single.note, 'بدون بصل');

      student.logout();
    },
    skip: apiUrl.isEmpty
        ? 'حدد --dart-define=WAJBATI_API=http://localhost:8000 لتشغيله'
        : null,
  );
}
