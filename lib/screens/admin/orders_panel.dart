import '../../localization/localized_widgets.dart';
import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../models/order_model.dart';
import '../student/student_store.dart' show OrderStatus, formatTime;
import 'admin_widgets.dart';

class OrdersPanel extends StatefulWidget {
  final List<OrderItem> orders;
  final DateTime? now;
  final Future<void> Function(OrderItem, String) onAdvance;
  final Future<void> Function(OrderItem) onReject;
  const OrdersPanel({
    super.key,
    required this.orders,
    required this.onAdvance,
    required this.onReject,
    this.now,
  });

  @override
  State<OrdersPanel> createState() => _OrdersPanelState();
}

class _OrdersPanelState extends State<OrdersPanel> {
  String _query = '';
  String _filter = 'active';
  bool _arrivedFirst = true;
  final Set<String> _pending = {};

  bool _late(OrderItem order) =>
      OrderStatus.isActive(order.status) &&
      order.pickupTime != null &&
      (widget.now ?? DateTime.now()).isAfter(order.pickupTime!);

  Future<void> _run(OrderItem order, Future<void> Function() action) async {
    if (_pending.contains(order.id)) return;
    setState(() => _pending.add(order.id));
    try {
      await action();
    } finally {
      if (mounted) setState(() => _pending.remove(order.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.orders
        .where((o) => OrderStatus.isActive(o.status))
        .toList();
    final filtered =
        widget.orders.where((order) {
          final matches = switch (_filter) {
            'all' => true,
            'active' => OrderStatus.isActive(order.status),
            'late' => _late(order),
            _ => order.status == _filter,
          };
          return matches &&
              '${order.id} ${order.studentName} ${order.details}'
                  .toLowerCase()
                  .contains(_query.toLowerCase());
        }).toList()..sort((a, b) {
          if (_arrivedFirst && a.studentArrived != b.studentArrived) {
            return a.studentArrived ? -1 : 1;
          }
          return (a.pickupTime ?? a.date).compareTo(b.pickupTime ?? b.date);
        });
    final filters = {
      'active': 'النشطة',
      'received': 'الجديدة',
      'preparing': 'قيد التحضير',
      'ready': 'الجاهزة',
      'late': 'المتأخرة',
      'delivered': 'المسلّمة',
      'all': 'الكل',
    };
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const AdminHeading(
          title: 'طلبات الكافيتريا',
          subtitle: 'تابع التحضير والاستلام من مكان واحد. يُحدّث تلقائيًا.',
        ),
        AdminStats(
          items: [
            AdminStat(
              'طلبات نشطة',
              '${active.length}',
              Icons.receipt_long_outlined,
            ),
            AdminStat(
              'بانتظار التحضير',
              '${active.where((o) => o.status == OrderStatus.received).length}',
              Icons.soup_kitchen_outlined,
            ),
            AdminStat(
              'جاهزة للاستلام',
              '${active.where((o) => o.status == OrderStatus.ready).length}',
              Icons.shopping_bag_outlined,
            ),
            AdminStat(
              'متأخرة عن الاستلام',
              '${active.where(_late).length}',
              Icons.schedule,
              color: AppColors.orange,
            ),
          ],
        ),
        const SizedBox(height: 24),
        LTextField(
          decoration: const InputDecoration(
            hintText: 'رقم الطلب، اسم الطالب أو الوجبة',
            prefixIcon: Icon(Icons.search),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (value) => setState(() => _query = value.trim()),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final filter in filters.entries)
              ChoiceChip(
                label: LText(filter.value),
                selected: _filter == filter.key,
                onSelected: (_) => setState(() => _filter = filter.key),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            onPressed: () => setState(() => _arrivedFirst = !_arrivedFirst),
            icon: Icon(
              _arrivedFirst ? Icons.directions_walk : Icons.schedule,
              size: 18,
            ),
            label: LText(_arrivedFirst ? 'الواصلون أولًا' : 'حسب وقت الاستلام'),
          ),
        ),
        if (filtered.isEmpty)
          const AdminEmpty('لا توجد طلبات تطابق هذا العرض')
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900 ? 2 : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 16) / columns;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final order in filtered)
                    SizedBox(width: width, child: _orderCard(order)),
                ],
              );
            },
          ),
        const SizedBox(height: 20),
        LText(
          'يشمل العرض الطلبات النشطة والسجل الحديث للطلبات المنتهية.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _orderCard(OrderItem order) {
    final late = _late(order);
    final busy = _pending.contains(order.id);
    final (next, action) = switch (order.status) {
      OrderStatus.received => (OrderStatus.preparing, 'بدء التحضير'),
      OrderStatus.preparing => (OrderStatus.ready, 'جاهز للاستلام'),
      OrderStatus.ready => (OrderStatus.delivered, 'تأكيد التسليم'),
      _ => ('', ''),
    };
    final color = switch (order.status) {
      OrderStatus.received => AppColors.orange,
      OrderStatus.preparing => AppColors.lightGreen,
      OrderStatus.ready => AppColors.darkGreen,
      _ => Colors.grey.shade700,
    };
    return AdminCard(
      borderColor: late ? Colors.orange.shade300 : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              LText(
                '#${order.id}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
              AdminBadge(
                OrderStatus.studentLabels[order.status] ?? order.status,
                color: color,
              ),
              if (late)
                const AdminBadge(
                  'متأخر عن الاستلام',
                  color: AppColors.orange,
                  icon: Icons.schedule,
                ),
              if (order.studentArrived && OrderStatus.isActive(order.status))
                const AdminBadge('الطالب وصل', icon: Icons.directions_walk),
            ],
          ),
          const SizedBox(height: 14),
          LText(
            order.studentName,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(height: 6),
          LText(
            order.details,
            style: TextStyle(color: Colors.grey.shade700, height: 1.6),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              LText(
                'الاستلام: ${order.pickupTime == null ? 'غير محدد' : formatTime(order.pickupTime!)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              LText(
                adminMoney(order.price),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.darkGreen,
                ),
              ),
              LText(
                order.paymentMethod,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
          if (order.closureReason != null) ...[
            const SizedBox(height: 12),
            LText(order.closureReason!),
          ],
          if (next.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(),
            ),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () => _run(order, () => widget.onAdvance(order, next)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.darkGreen,
                  ),
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_forward, size: 18),
                  label: LText(busy ? 'جارٍ التحديث...' : action),
                ),
                if (order.status == OrderStatus.received)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => _run(order, () => widget.onReject(order)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                    ),
                    child: const LText('رفض الطلب'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
