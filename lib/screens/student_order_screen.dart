import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../services/push_service.dart';
import '../services/password_dialog.dart';
import '../services/api_client.dart';
import 'student/cart_checkout_screens.dart';
import 'student/order_tracking_screen.dart';
import 'student/student_auth_screens.dart';
import 'student/student_store.dart';
import 'student/student_tabs.dart';

/// الشاشة الرئيسية لواجهة الطالب بعد تسجيل الدخول:
/// الرئيسية (الكافيتريات) • طلباتي • المفضلة • الإشعارات
class StudentOrderScreen extends StatefulWidget {
  const StudentOrderScreen({super.key});

  @override
  State<StudentOrderScreen> createState() => _StudentOrderScreenState();
}

class _StudentOrderScreenState extends State<StudentOrderScreen> {
  final store = StudentStore.instance;
  int _tab = 0;
  StreamSubscription<AppNotification>? _sub;
  StreamSubscription<int>? _tabSub;
  StreamSubscription<String>? _pushSub;
  StreamSubscription<void>? _pushUpdates;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    _pushSub = PushService.instance.openedOrders.listen(_openPushOrder);
    _pushUpdates = PushService.instance.updates.listen((_) => store.refresh());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = PushService.instance.pendingOrderId;
      if (id != null) _openPushOrder(id);
    });
    // فتح تبويب معيّن من شاشات أخرى (مثلاً "طلباتي" بعد إرسال الطلب)
    _tabSub = store.onTabRequest.listen((i) {
      if (mounted) setState(() => _tab = i);
    });
    // إشعار داخل التطبيق عند تغيّر حالة أي طلب
    _sub = store.onNotification.listen((n) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.darkGreen,
            duration: const Duration(seconds: 5),
            // وجود زر "عرض" يجعل الرسالة دائمة افتراضياً؛ نجعلها تختفي بعد 5 ثوانٍ
            persist: false,
            showCloseIcon: true,
            closeIconColor: Colors.white70,
            content: Row(
              children: [
                const Icon(Icons.notifications_active, color: AppColors.orange),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(n.body, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            action: n.orderId == null
                ? null
                : SnackBarAction(
                    label: 'عرض',
                    textColor: AppColors.orange,
                    onPressed: () => openOrderTracking(context, n.orderId!),
                  ),
          ),
        );
    });
  }

  @override
  void dispose() {
    _pushSub?.cancel();
    _pushUpdates?.cancel();
    _sub?.cancel();
    _tabSub?.cancel();
    super.dispose();
  }

  void _openPushOrder(String id) {
    PushService.instance.pendingOrderId = null;
    if (mounted && store.isLoggedIn) openOrderTracking(context, id);
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    _loggingOut = true;
    await PushService.instance.unregisterDevice();
    if (!mounted) return;
    // لا تبقى رسائل الحساب السابق ظاهرة بعد الخروج
    ScaffoldMessenger.of(context).clearSnackBars();
    store.logout();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const StudentLoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // حماية: لو فُتحت الشاشة بدون تسجيل دخول
    if (!store.isLoggedIn) return const StudentLoginScreen();

    const titles = ['الكافيتريات', 'طلباتي', 'المفضلة', 'الإشعارات'];

    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        // انتهت الجلسة أثناء الاستخدام ← العودة لتسجيل الدخول
        if (!store.isLoggedIn) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
            }
          });
          return const StudentLoginScreen();
        }
        return Scaffold(
          backgroundColor: AppColors.bgCream,
          appBar: AppBar(
            backgroundColor: AppColors.darkGreen,
            foregroundColor: Colors.white,
            title: Text(
              _tab == 0 ? 'وجباتي' : titles[_tab],
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            actions: [
              IconButton(
                tooltip: 'السلة',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CartScreen()),
                ),
                icon: Badge(
                  isLabelVisible: store.cartCount > 0,
                  label: Text('${store.cartCount}'),
                  backgroundColor: AppColors.orange,
                  child: const Icon(Icons.shopping_bag_outlined),
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.account_circle_outlined),
                onSelected: (v) {
                  if (v == 'logout') _logout();
                  if (v == 'password') {
                    showPasswordDialog(context, role: ApiRole.student);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    enabled: false,
                    child: Text(
                      '${store.currentStudent!.name}\n${store.currentStudent!.universityId}',
                      style: const TextStyle(color: Colors.black87),
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'password',
                    child: Text('تغيير كلمة المرور'),
                  ),
                  const PopupMenuItem(
                    value: 'logout',
                    child: Row(
                      children: [
                        Icon(Icons.logout, color: Colors.red),
                        SizedBox(width: 8),
                        Text('تسجيل الخروج'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              // ضعف أو انقطاع الاتصال بالسيرفر: رسالة واضحة + إعادة المحاولة
              if (store.connectionError != null)
                MaterialBanner(
                  backgroundColor: Colors.red.shade50,
                  leading: Icon(Icons.wifi_off, color: Colors.red.shade700),
                  content: Text(
                    '${store.connectionError!}${store.lastUpdated == null ? '' : '\nآخر تحديث ناجح: ${store.lastUpdated!.hour.toString().padLeft(2, '0')}:${store.lastUpdated!.minute.toString().padLeft(2, '0')}'}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  actions: [
                    TextButton(
                      onPressed: store.refresh,
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              Expanded(
                child: IndexedStack(
                  index: _tab,
                  children: const [
                    CafeteriasTab(),
                    MyOrdersTab(),
                    FavoritesTab(),
                    NotificationsTab(),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            indicatorColor: AppColors.orange.withValues(alpha: 0.25),
            onDestinationSelected: (i) {
              setState(() => _tab = i);
              if (i == 3) store.markAllRead();
            },
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.storefront_outlined),
                selectedIcon: Icon(Icons.storefront),
                label: 'الرئيسية',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: store.activeOrders.isNotEmpty,
                  label: Text('${store.activeOrders.length}'),
                  child: const Icon(Icons.receipt_long_outlined),
                ),
                selectedIcon: const Icon(Icons.receipt_long),
                label: 'طلباتي',
              ),
              const NavigationDestination(
                icon: Icon(Icons.favorite_border),
                selectedIcon: Icon(Icons.favorite),
                label: 'المفضلة',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: store.unreadCount > 0,
                  label: Text('${store.unreadCount}'),
                  child: const Icon(Icons.notifications_none),
                ),
                selectedIcon: const Icon(Icons.notifications),
                label: 'الإشعارات',
              ),
            ],
          ),
        );
      },
    );
  }
}
