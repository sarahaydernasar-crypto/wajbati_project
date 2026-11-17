import '../../localization/localized_widgets.dart';
import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_theme.dart';
import '../../models/order_model.dart';
import '../../widgets/app_feedback.dart';
import 'order_tracking_screen.dart';
import 'student_store.dart';
import 'student_widgets.dart';

class CurrentOrderCard extends StatelessWidget {
  final OrderItem order;
  final int activeCount;
  final VoidCallback onViewAll;
  const CurrentOrderCard({
    super.key,
    required this.order,
    required this.activeCount,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final pickup = order.pickupTime;
    final ready = order.status == OrderStatus.ready;
    final message = switch (order.status) {
      OrderStatus.ready => 'وجبتك جاهزة، توجّه إلى الكافيتريا للاستلام.',
      OrderStatus.preparing =>
        'بدأت الكافيتريا تحضير وجبتك. سنخبرك عند جاهزيتها.',
      _ => 'وصل طلبك إلى الكافيتريا وهو بانتظار بدء التحضير.',
    };
    return SoftEntrance(
      child: Card(
        margin: const EdgeInsets.only(bottom: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesign.radius),
          side: const BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openOrderTracking(context, order.id),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Icon(
                      Icons.receipt_long_outlined,
                      color: AppColors.darkGreen,
                      size: 20,
                    ),
                    const LText(
                      'طلبك الحالي',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                    LText(
                      '#${order.id}',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                    AnimatedSwitcher(
                      duration: AppDesign.motion(context),
                      child: OrderStatusChip(
                        key: ValueKey(order.status),
                        status: order.status,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                LText(
                  order.cafeteriaName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkGreen,
                  ),
                ),
                const SizedBox(height: 6),
                LText(
                  message,
                  style: const TextStyle(color: AppColors.muted, height: 1.5),
                ),
                if (pickup != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule,
                        size: 18,
                        color: AppColors.darkGreen,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: LText(
                          'موعد الاستلام ${formatTime(pickup)} • ${pickup.day}/${pickup.month}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: (OrderStatus.indexOf(order.status) + 1) / 4,
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(8),
                  color: AppColors.lightGreen,
                  backgroundColor: AppColors.softGreen,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => openOrderTracking(context, order.id),
                    icon: Icon(
                      ready
                          ? Icons.shopping_bag_outlined
                          : Icons.near_me_outlined,
                      size: 19,
                    ),
                    label: LText(ready ? 'تفاصيل الاستلام' : 'تتبع الطلب'),
                  ),
                ),
                if (activeCount > 1)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(
                      onPressed: onViewAll,
                      child: LText('عرض كل الطلبات الحالية ($activeCount)'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
