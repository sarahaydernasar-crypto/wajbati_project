import '../../localization/localized_widgets.dart';
import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_theme.dart';
import '../../models/order_model.dart';
import '../../services/api_client.dart';
import 'student_store.dart';

/// رسالة سريعة واضحة (نجاح أو خطأ)
void showStudentMessage(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Expanded(child: LText(message)),
          ],
        ),
        backgroundColor: error ? Colors.red.shade700 : AppColors.darkGreen,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: error ? 4 : 2),
      ),
    );
}

void showResult(BuildContext context, ActionResult r) {
  if (r.message.isNotEmpty) {
    showStudentMessage(context, r.message, error: !r.ok);
  }
}

/// صورة الصنف مع بديل عند عدم وجود صورة أو فشل التحميل (ضعف النت)
class MenuItemImage extends StatelessWidget {
  final MenuItemModel item;
  final double size;
  final double? width;
  final double? height;
  final double radius;
  const MenuItemImage({
    super.key,
    required this.item,
    this.size = 72,
    this.width,
    this.height,
    this.radius = 16,
  });

  @override
  Widget build(BuildContext context) {
    final imageWidth = width ?? size;
    final imageHeight = height ?? size;
    Widget placeholder({bool failed = false}) => Container(
      width: imageWidth,
      height: imageHeight,
      color: AppColors.softGreen,
      alignment: Alignment.center,
      child: Icon(
        failed ? Icons.image_not_supported_outlined : Icons.restaurant_rounded,
        size: imageHeight > 100 ? 44 : 28,
        color: AppColors.lightGreen,
      ),
    );
    Widget child = placeholder();
    final url = item.imageUrl;
    if (url != null && url.isNotEmpty) {
      child = Image.network(
        ApiClient.instance.resolveUrl(url),
        width: imageWidth,
        height: imageHeight,
        fit: BoxFit.cover,
        semanticLabel: 'صورة ${item.name}',
        frameBuilder: (_, image, frame, synchronous) => synchronous
            ? image
            : AnimatedSwitcher(
                duration: AppDesign.motion(context),
                child: frame == null ? placeholder() : image,
              ),
        loadingBuilder: (_, image, progress) =>
            progress == null ? image : placeholder(),
        errorBuilder: (_, __, ___) => placeholder(failed: true),
      );
    }
    if (!item.isAvailable) {
      child = ColorFiltered(
        colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.saturation),
        child: child,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Semantics(
        label: 'صورة ${item.name}'.tr(context),
        image: true,
        child: child,
      ),
    );
  }
}

class CafeteriaStatusChip extends StatelessWidget {
  final CafeteriaStatus status;
  const CafeteriaStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status) {
      CafeteriaStatus.open => ('مفتوحة', AppColors.lightGreen, Icons.circle),
      CafeteriaStatus.busy => ('مزدحمة', AppColors.orange, Icons.groups),
      CafeteriaStatus.closed => ('مغلقة', AppColors.muted, Icons.lock_clock),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          LText(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class OrderStatusChip extends StatelessWidget {
  final String status;
  const OrderStatusChip({super.key, required this.status});

  static Color colorFor(String status) => switch (status) {
    OrderStatus.received => AppColors.muted,
    OrderStatus.preparing => AppColors.orange,
    OrderStatus.ready => AppColors.lightGreen,
    _ => Colors.grey.shade700,
  };

  @override
  Widget build(BuildContext context) {
    final c = colorFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: LText(
        OrderStatus.studentLabels[status] ?? status,
        style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }
}

/// نجوم تقييم (للعرض أو للاختيار)
class StarRating extends StatelessWidget {
  final double value;
  final double size;
  final ValueChanged<int>? onChanged;

  const StarRating({
    super.key,
    required this.value,
    this.size = 18,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final n = i + 1;
        final icon = value >= n
            ? Icons.star_rounded
            : value >= n - 0.5
            ? Icons.star_half_rounded
            : Icons.star_outline_rounded;
        final star = Icon(icon, color: AppColors.orange, size: size);
        return onChanged == null
            ? star
            : InkResponse(
                onTap: () => onChanged!(n),
                radius: size,
                child: Padding(padding: const EdgeInsets.all(2), child: star),
              );
      }),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            LText(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              LText(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// ديالوج تقييم الطلب
Future<void> showRateOrderDialog(BuildContext context, OrderItem order) async {
  var stars = 0;
  var sending = false;
  final comment = TextEditingController();
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: const LText('قيّم وجبتك'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LText(
              order.lines.map((l) => l.itemName).join('، '),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            StarRating(
              value: stars.toDouble(),
              size: 34,
              onChanged: (v) => setD(() => stars = v),
            ),
            const SizedBox(height: 12),
            LTextField(
              controller: comment,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'ملاحظة اختيارية...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const LText('لاحقاً'),
          ),
          FilledButton(
            onPressed: stars == 0 || sending
                ? null
                : () async {
                    setD(() => sending = true);
                    final r = await StudentStore.instance.rateOrder(
                      order,
                      stars,
                      comment.text,
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) showResult(context, r);
                  },
            child: const LText('إرسال'),
          ),
        ],
      ),
    ),
  );
  // لا نستدعي dispose هنا لأن الديالوج قد يكون ما زال في حركة الإغلاق
}
