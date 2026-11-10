import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../models/order_model.dart';
import 'cart_checkout_screens.dart';
import 'menu_screen.dart';
import 'order_tracking_screen.dart';
import 'student_store.dart';
import 'student_widgets.dart';

// =====================================================================
//  1) الرئيسية: قائمة الكافيتريات مع حالتها (مفتوحة / مغلقة / مزدحمة)
// =====================================================================
class CafeteriasTab extends StatelessWidget {
  const CafeteriasTab({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StudentStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final list = store.cafeteriaList;
        // المفتوحة أولاً ثم المزدحمة ثم المغلقة
        list.sort((a, b) => a.status.index.compareTo(b.status.index));
        final active = store.activeOrders;

        if (!store.cafeteriasLoaded) {
          return store.connectionError == null
              ? const Center(child: CircularProgressIndicator())
              : EmptyState(
                  icon: Icons.wifi_off,
                  title: 'تعذّر تحميل الكافيتريات',
                  subtitle: store.connectionError,
                  action: FilledButton.icon(
                    onPressed: store.refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                );
        }

        return RefreshIndicator(
          onRefresh: store.refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'مرحباً ${store.currentStudent?.name.split(' ').first ?? ''} 👋',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkGreen,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'من أي كافيتريا تريد أن تطلب اليوم؟',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              // تتبع الطلبات أصبح في تبويب "طلباتي"؛ هنا تذكير صغير فقط
              if (active.isNotEmpty)
                Card(
                  color: AppColors.orange.withValues(alpha: 0.12),
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListTile(
                    onTap: () => store.openTab(StudentStore.ordersTab),
                    leading: const Icon(
                      Icons.delivery_dining,
                      color: AppColors.orange,
                    ),
                    title: Text(
                      active.length == 1
                          ? 'لديك طلب قيد المتابعة'
                          : 'لديك ${active.length} طلبات قيد المتابعة',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text('تابع حالتها من "طلباتي"'),
                    trailing: const Icon(Icons.chevron_left),
                  ),
                ),
              for (final c in list) _CafeteriaCard(info: c),
            ],
          ),
        );
      },
    );
  }
}

class _CafeteriaCard extends StatelessWidget {
  final CafeteriaInfo info;
  const _CafeteriaCard({required this.info});

  @override
  Widget build(BuildContext context) {
    final status = info.status;
    final closed = status == CafeteriaStatus.closed;
    final available = info.availableItems;

    return Opacity(
      opacity: closed ? 0.6 : 1,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => MenuScreen(cafeteria: info.name)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.darkGreen.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.storefront,
                    color: AppColors.darkGreen,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              info.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          CafeteriaStatusChip(status: status),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        info.location,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 12,
                        children: [
                          _meta(Icons.schedule, info.hoursLabel),
                          _meta(Icons.restaurant_menu, '$available صنف متوفر'),
                          if (status == CafeteriaStatus.busy)
                            _meta(
                              Icons.hourglass_top,
                              'انتظار أطول من المعتاد',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: Colors.grey.shade600),
      const SizedBox(width: 3),
      Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
    ],
  );
}

// =====================================================================
//  2) طلباتي: الطلبات الحالية + السجل + "أعد الطلب" + التقييم
// =====================================================================
class MyOrdersTab extends StatelessWidget {
  const MyOrdersTab({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StudentStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final active = store.activeOrders;
        final past = store.pastOrders;
        if (active.isEmpty && past.isEmpty) {
          return const EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'لا توجد طلبات بعد',
            subtitle: 'اختر كافيتريا من الصفحة الرئيسية وابدأ طلبك الأول',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (active.isNotEmpty) ...[
              _section('الطلبات الحالية'),
              for (final o in active) _OrderCard(order: o),
            ],
            if (past.isNotEmpty) ...[
              _section('سجل الطلبات'),
              for (final o in past) _OrderCard(order: o),
            ],
          ],
        );
      },
    );
  }

  Widget _section(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(
      t,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 16,
        color: AppColors.darkGreen,
      ),
    ),
  );
}

class _OrderCard extends StatelessWidget {
  final OrderItem order;
  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final store = StudentStore.instance;
    final done = !OrderStatus.isActive(order.status);
    final d = order.date;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => openOrderTracking(context, order.id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '#${order.id}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  OrderStatusChip(status: order.status),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${d.day}/${d.month} • ${formatTime(d)}',
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                order.cafeteriaName,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                order.lines.isEmpty
                    ? order.details
                    : order.lines
                          .map((l) => '${l.itemName} ×${l.quantity}')
                          .join('، '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              // تتبع الطلب مباشرة من "طلباتي"
              if (!done) ...[
                const SizedBox(height: 12),
                _MiniTracker(status: order.status),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.schedule,
                      size: 16,
                      color: AppColors.darkGreen,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'الاستلام ${order.pickupTime == null ? order.time : formatTime(order.pickupTime!)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.darkGreen,
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: order.status == OrderStatus.ready
                            ? AppColors.orange
                            : AppColors.darkGreen,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () async {
                        if (!order.studentArrived) {
                          final r = await store.markArrived(order);
                          if (!context.mounted) return;
                          if (!r.ok) {
                            showResult(context, r);
                            return;
                          }
                        }
                        if (context.mounted) {
                          openOrderTracking(context, order.id);
                        }
                      },
                      icon: Icon(
                        order.studentArrived
                            ? Icons.qr_code
                            : Icons.where_to_vote,
                        size: 18,
                      ),
                      label: Text(order.studentArrived ? 'رمز QR' : 'وصلت'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    formatPrice(order.price),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGreen,
                    ),
                  ),
                  const Spacer(),
                  if (order.status == OrderStatus.delivered &&
                      order.rating != null)
                    StarRating(value: order.rating!.toDouble(), size: 16),
                  if (order.status == OrderStatus.delivered &&
                      order.rating == null)
                    TextButton.icon(
                      onPressed: () => showRateOrderDialog(context, order),
                      icon: const Icon(Icons.star_outline, size: 18),
                      label: const Text('قيّم'),
                    ),
                  if (done)
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        final r = await store.reorder(order);
                        if (!context.mounted) return;
                        showResult(context, r);
                        if (r.ok) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CartScreen(),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.replay, size: 18),
                      label: const Text('أعد الطلب'),
                    ),
                  if (!done)
                    TextButton(
                      onPressed: () => openOrderTracking(context, order.id),
                      child: const Text('التفاصيل'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// شريط مصغّر للحالات الأربع داخل بطاقة الطلب
class _MiniTracker extends StatelessWidget {
  final String status;
  const _MiniTracker({required this.status});

  @override
  Widget build(BuildContext context) {
    final current = OrderStatus.indexOf(status);
    return Row(
      children: [
        for (var i = 0; i < OrderStatus.steps.length; i++)
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: i <= current
                        ? AppColors.lightGreen
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  OrderStatus.studentLabels[OrderStatus.steps[i]]!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: i == current
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: i <= current ? AppColors.darkGreen : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// =====================================================================
//  3) المفضلة
// =====================================================================
class FavoritesTab extends StatelessWidget {
  const FavoritesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StudentStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final items = store.favoriteItems;
        if (items.isEmpty) {
          return const EmptyState(
            icon: Icons.favorite_border,
            title: 'لا توجد أصناف مفضلة',
            subtitle: 'اضغط على ♡ بجانب أي صنف في القائمة لإضافته هنا',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final item = items[i];
            return Card(
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.all(10),
                leading: MenuItemImage(item: item, size: 52),
                title: Text(
                  item.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${item.cafeteriaName ?? ''}\n${item.isAvailable ? formatPrice(item.priceValue) : 'منتهٍ حالياً'}',
                  style: TextStyle(color: item.isAvailable ? null : Colors.red),
                ),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'إزالة من المفضلة',
                      icon: const Icon(Icons.favorite, color: Colors.red),
                      onPressed: () async {
                        final r = await store.toggleFavorite(item);
                        if (!r.ok && context.mounted) showResult(context, r);
                      },
                    ),
                    IconButton.filled(
                      tooltip: 'أضف للسلة',
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.darkGreen,
                      ),
                      onPressed: item.isAvailable
                          ? () => _addFavorite(context, item)
                          : null,
                      icon: const Icon(Icons.add_shopping_cart, size: 20),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _addFavorite(BuildContext context, MenuItemModel item) {
    final cafeteria = item.cafeteriaName;
    if (cafeteria == null) return;
    showResult(context, StudentStore.instance.addToCart(cafeteria, item));
  }
}

// =====================================================================
//  4) الإشعارات
// =====================================================================
class NotificationsTab extends StatelessWidget {
  const NotificationsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StudentStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final list = store.notifications;
        if (list.isEmpty) {
          return const EmptyState(
            icon: Icons.notifications_none,
            title: 'لا توجد إشعارات',
            subtitle: 'ستصلك هنا تحديثات حالة طلباتك أولاً بأول',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final n = list[i];
            return Card(
              margin: EdgeInsets.zero,
              color: n.read
                  ? Colors.white
                  : AppColors.orange.withValues(alpha: 0.08),
              child: ListTile(
                onTap: n.orderId == null
                    ? null
                    : () => openOrderTracking(context, n.orderId!),
                leading: const CircleAvatar(
                  backgroundColor: AppColors.darkGreen,
                  child: Icon(
                    Icons.notifications,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                title: Text(
                  n.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(n.body),
                trailing: Text(
                  formatTime(n.time),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
