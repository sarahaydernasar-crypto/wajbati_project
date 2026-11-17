import '../localization/localized_widgets.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_theme.dart';

class QuietSize extends StatelessWidget {
  final Widget child;
  final AlignmentGeometry alignment;
  const QuietSize({
    super.key,
    required this.child,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedSize(
      duration: AppDesign.fast,
      alignment: alignment,
      child: child,
    );
  }
}

class SoftEntrance extends StatelessWidget {
  final Widget child;
  const SoftEntrance({super.key, required this.child});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: AppDesign.motion(context),
    curve: Curves.easeOut,
    child: child,
    builder: (_, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, 5 * (1 - value)),
        child: child,
      ),
    ),
  );
}

class LoadingCards extends StatelessWidget {
  final String label;
  final int count;
  const LoadingCards({
    super.key,
    this.label = 'جارٍ تحميل البيانات...',
    this.count = 3,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    label: label.tr(context),
    child: ExcludeSemantics(
      child: SoftEntrance(
        child: ListView(
          padding: const EdgeInsets.all(AppDesign.gap),
          children: [
            LText(label, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
            for (var i = 0; i < count; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppDesign.radius),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.softGreen,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 14,
                            decoration: BoxDecoration(
                              color: AppColors.softGreen,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FractionallySizedBox(
                            widthFactor: .65,
                            child: Container(
                              height: 10,
                              decoration: BoxDecoration(
                                color: AppColors.bgCream,
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class AppNotice extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final bool error;
  const AppNotice({
    super.key,
    required this.message,
    this.onRetry,
    this.error = false,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    margin: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: error ? const Color(0xFFFBEEEC) : AppColors.softGreen,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              error ? Icons.wifi_off_outlined : Icons.info_outline,
              size: 20,
              color: error ? AppColors.danger : AppColors.darkGreen,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LText(
                message,
                style: TextStyle(
                  color: error ? AppColors.danger : AppColors.darkGreen,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
        if (onRetry != null)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const LText('إعادة المحاولة'),
            ),
          ),
      ],
    ),
  );
}
