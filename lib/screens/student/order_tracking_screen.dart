import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../constants/app_colors.dart';
import '../../models/order_model.dart';
import 'student_store.dart';
import 'student_widgets.dart';

void openOrderTracking(BuildContext context, String orderId) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: orderId)),
  );
}

/// صفحة تتبع الطلب بحالاته الأربع + زر "وصلت" + رمز QR للاستلام
class OrderTrackingScreen extends StatefulWidget {
  final String orderId;
  const OrderTrackingScreen({super.key, required this.orderId});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  final store = StudentStore.instance;
  bool _fetching = false;

  String get orderId => widget.orderId;

  @override
  void initState() {
    super.initState();
    if (store.findOrder(orderId) == null) _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _fetching = true);
    await store.fetchOrder(orderId);
    if (mounted) setState(() => _fetching = false);
  }

  Future<void> _cancel(OrderItem order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء الطلب؟'),
        content: const Text(
          'يمكن إلغاء الطلب ما دامت الكافيتريا لم تبدأ تحضيره.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إلغاء الطلب'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await store.cancelOrder(order);
    if (mounted) showResult(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final order = store.findOrder(orderId);
        return Scaffold(
          backgroundColor: AppColors.bgCream,
          appBar: AppBar(
            backgroundColor: AppColors.darkGreen,
            foregroundColor: Colors.white,
            title: Text(
              'طلب #$orderId',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          body: order == null
              ? (_fetching
                    ? const Center(child: CircularProgressIndicator())
                    : EmptyState(
                        icon: Icons.search_off,
                        title: 'لم يتم العثور على الطلب',
                        subtitle:
                            store.connectionError ??
                            'تأكد من اتصالك بالإنترنت وحاول مجدداً.',
                        action: FilledButton.icon(
                          onPressed: _fetch,
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ))
              : RefreshIndicator(
                  onRefresh: () async => store.checkForUpdates(),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _StatusHeader(order: order),
                      const SizedBox(height: 16),
                      if (OrderStatus.isActive(order.status) ||
                          order.status == OrderStatus.delivered)
                        _StatusTimeline(status: order.status),
                      const SizedBox(height: 16),
                      _PickupSection(order: order),
                      const SizedBox(height: 16),
                      _OrderDetails(order: order),
                      if (order.status == OrderStatus.received)
                        TextButton.icon(
                          onPressed: () => _cancel(order),
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('إلغاء الطلب'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _StatusHeader extends StatelessWidget {
  final OrderItem order;
  const _StatusHeader({required this.order});

  @override
  Widget build(BuildContext context) {
    final (emoji, text) = switch (order.status) {
      OrderStatus.received => ('📝', 'وصل طلبك للكافيتريا وبانتظار التحضير'),
      OrderStatus.preparing => ('👨‍🍳', 'يتم تحضير طلبك الآن'),
      OrderStatus.ready => ('✅', 'طلبك جاهز! توجّه للاستلام'),
      OrderStatus.cancelled => ('✖️', 'تم إلغاء الطلب'),
      OrderStatus.rejected => ('✖️', 'اعتذرت الكافيتريا عن طلبك'),
      _ => ('🎉', 'تم تسليم طلبك، بالعافية!'),
    };
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.darkGreen,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 40)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'الاستلام ${order.pickupTime == null ? '-' : formatTime(order.pickupTime!)} • ${order.cafeteriaName}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusTimeline extends StatelessWidget {
  final String status;
  const _StatusTimeline({required this.status});

  static const _icons = [
    Icons.receipt_long,
    Icons.soup_kitchen,
    Icons.shopping_bag,
    Icons.check_circle,
  ];

  @override
  Widget build(BuildContext context) {
    final current = OrderStatus.indexOf(status);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < OrderStatus.steps.length; i++) ...[
              Expanded(
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i <= current
                            ? AppColors.lightGreen
                            : Colors.grey.shade200,
                        border: i == current
                            ? Border.all(color: AppColors.orange, width: 3)
                            : null,
                      ),
                      child: Icon(
                        _icons[i],
                        color: i <= current ? Colors.white : Colors.grey,
                        size: 22,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      OrderStatus.studentLabels[OrderStatus.steps[i]]!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: i == current
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: i <= current ? AppColors.darkGreen : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              if (i < OrderStatus.steps.length - 1)
                Padding(
                  padding: const EdgeInsets.only(top: 21),
                  child: Container(
                    width: 16,
                    height: 3,
                    color: i < current
                        ? AppColors.lightGreen
                        : Colors.grey.shade300,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// زر "وصلت" ثم عرض رمز QR الذي تمسحه الكافيتريا لتأكيد التسليم
class _PickupSection extends StatelessWidget {
  final OrderItem order;
  const _PickupSection({required this.order});

  @override
  Widget build(BuildContext context) {
    final store = StudentStore.instance;

    if (order.status == OrderStatus.cancelled ||
        order.status == OrderStatus.rejected) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            order.closureReason ?? OrderStatus.studentLabels[order.status]!,
          ),
        ),
      );
    }

    if (order.status == OrderStatus.delivered) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (order.rating == null) ...[
                const Text(
                  'كيف كانت وجبتك؟',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.orange,
                  ),
                  onPressed: () => showRateOrderDialog(context, order),
                  icon: const Icon(Icons.star),
                  label: const Text('قيّم الوجبة'),
                ),
              ] else ...[
                const Text(
                  'تقييمك',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                StarRating(value: order.rating!.toDouble(), size: 28),
                if (order.ratingComment != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '"${order.ratingComment}"',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ],
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  final r = await store.reorder(order);
                  if (context.mounted) showResult(context, r);
                },
                icon: const Icon(Icons.replay),
                label: const Text('أعد الطلب'),
              ),
            ],
          ),
        ),
      );
    }

    if (!order.studentArrived) {
      final ready = order.status == OrderStatus.ready;
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                ready
                    ? 'طلبك جاهز. عند وصولك للكافيتريا اضغط "وصلت" لعرض رمز الاستلام.'
                    : 'عند وصولك للكافيتريا اضغط "وصلت" لعرض رمز QR للاستلام.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade800),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: ready
                        ? AppColors.orange
                        : AppColors.darkGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () async {
                    final r = await store.markArrived(order);
                    if (!r.ok && context.mounted) showResult(context, r);
                  },
                  icon: const Icon(Icons.where_to_vote),
                  label: const Text(
                    'وصلت',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              'أظهر هذا الرمز لموظف الكافيتريا',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppColors.darkGreen,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.darkGreen, width: 2),
              ),
              // محتوى الـ QR هو رقم الطلب، وهو ما يبحث عنه ماسح لوحة التحكم
              child: QrImageView(
                data: order.id,
                size: 220,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: AppColors.darkGreen,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: AppColors.darkGreen,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'رقم الطلب: ${order.id}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              order.status == OrderStatus.ready
                  ? 'طلبك جاهز ✅'
                  : 'طلبك لم يجهز بعد، سيتم تنبيهك فور جاهزيته',
              style: TextStyle(
                color: order.status == OrderStatus.ready
                    ? AppColors.lightGreen
                    : AppColors.orange,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderDetails extends StatelessWidget {
  final OrderItem order;
  const _OrderDetails({required this.order});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'تفاصيل الطلب',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (order.lines.isEmpty) Text(order.details),
            for (final l in order.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${l.quantity}× ',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.itemName),
                          if (l.note.isNotEmpty)
                            Text(
                              l.note,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.orange,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(formatPrice(l.total)),
                  ],
                ),
              ),
            const Divider(),
            _row('طريقة الدفع', order.paymentMethod),
            _row('وقت الطلب', order.time),
            _row('المجموع', formatPrice(order.price), bold: true),
          ],
        ),
      ),
    );
  }

  Widget _row(String a, String b, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Text(a, style: TextStyle(color: Colors.grey.shade700)),
        const Spacer(),
        Text(
          b,
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.w500,
            color: bold ? AppColors.darkGreen : null,
          ),
        ),
      ],
    ),
  );
}
