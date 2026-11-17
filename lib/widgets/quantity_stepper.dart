import '../localization/localized_widgets.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_theme.dart';

class QuantityStepper extends StatelessWidget {
  final int value;
  final VoidCallback? onIncrease;
  final VoidCallback? onDecrease;
  final String itemName;
  const QuantityStepper({
    super.key,
    required this.value,
    required this.itemName,
    required this.onIncrease,
    required this.onDecrease,
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.softGreen,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: ('تقليل كمية $itemName').tr(context),
          onPressed: onDecrease,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          iconSize: 20,
          icon: Icon(
            value == 1 ? Icons.delete_outline : Icons.remove,
            color: AppColors.darkGreen,
          ),
        ),
        Semantics(
          label: 'الكمية $value'.tr(context),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 28),
            child: AnimatedSwitcher(
              duration: AppDesign.motion(context),
              child: LText(
                '$value',
                key: ValueKey(value),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkGreen,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: ('زيادة كمية $itemName').tr(context),
          onPressed: onIncrease,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          iconSize: 20,
          icon: const Icon(Icons.add, color: AppColors.darkGreen),
        ),
      ],
    ),
  );
}
