import '../localization/localized_widgets.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_theme.dart';
import '../screens/student/student_store.dart' show formatPrice;

class CartDock extends StatelessWidget {
  final double total;
  final int count;
  final String label;
  final VoidCallback onPressed;
  final bool enabled;
  final bool bottomInset;
  final String? message;
  const CartDock({
    super.key,
    required this.total,
    required this.count,
    required this.onPressed,
    this.label = 'عرض السلة',
    this.enabled = true,
    this.bottomInset = true,
    this.message,
  });
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: AppColors.border)),
    ),
    child: SafeArea(
      top: false,
      bottom: bottomInset,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: LText(
                  message!,
                  style: TextStyle(
                    fontSize: 12,
                    color: enabled ? AppColors.muted : AppColors.danger,
                  ),
                ),
              ),
            Row(
              children: [
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LText(
                        'المجموع • $count قطعة',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: AppDesign.motion(context),
                        child: LText(
                          formatPrice(total),
                          key: ValueKey(total),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 19,
                            color: AppColors.darkGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: enabled ? onPressed : null,
                    icon: const Icon(Icons.shopping_bag_outlined, size: 20),
                    label: LText(label, textAlign: TextAlign.center),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
