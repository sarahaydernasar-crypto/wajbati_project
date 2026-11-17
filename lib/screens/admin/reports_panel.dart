import '../../localization/localized_widgets.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import 'admin_widgets.dart';

class ReportsPanel extends StatelessWidget {
  final Map<String, dynamic> data;
  final String period;
  final bool loading;
  final String? error;
  final Future<void> Function(String, {DateTime? start, DateTime? end})
  onSelect;
  final VoidCallback onRetry;
  const ReportsPanel({
    super.key,
    required this.data,
    required this.period,
    required this.onSelect,
    required this.onRetry,
    this.loading = false,
    this.error,
  });

  String _day(String raw) {
    final date = DateTime.tryParse(raw);
    return date == null ? raw : '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _custom(BuildContext context) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: today,
      helpText: 'اختر فترة التقرير'.tr(context),
      saveText: 'عرض التقرير'.tr(context),
      initialDateRange: DateTimeRange(
        start: today.subtract(const Duration(days: 6)),
        end: today,
      ),
    );
    if (range == null || !context.mounted) return;
    if (range.end.difference(range.start).inDays >= 366) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LText('اختر فترة لا تتجاوز 366 يومًا')),
      );
      return;
    }
    await onSelect('custom', start: range.start, end: range.end);
  }

  @override
  Widget build(BuildContext context) {
    final top = (data['top_items'] as List? ?? []).cast<Map>();
    final series = (data['series'] as List? ?? []).cast<Map>();
    final estimated = (data['estimated_orders'] as num?)?.toInt() ?? 0;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const AdminHeading(
          title: 'المبيعات والتقارير',
          subtitle: 'المبيعات تُحسب عند تسليم الطلب، بتوقيت بغداد.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in {
              'today': 'اليوم',
              'week': 'آخر 7 أيام',
              'month': 'هذا الشهر',
              'custom': 'فترة مخصصة',
            }.entries)
              ChoiceChip(
                label: LText(entry.value),
                selected: period == entry.key,
                onSelected: (_) => entry.key == 'custom'
                    ? _custom(context)
                    : onSelect(entry.key),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (data['start_date'] != null)
          LText(
            '${_day(data['start_date'] as String)} — ${_day(data['end_date'] as String)}',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        if (error != null) ...[
          const SizedBox(height: 16),
          AdminCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LText(error!, style: TextStyle(color: Colors.red.shade700)),
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const LText('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ],
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (data.isNotEmpty) ...[
          const SizedBox(height: 20),
          AdminStats(
            items: [
              AdminStat(
                'مبيعات الطلبات المسلّمة',
                adminMoney(data['sales'] as num? ?? 0),
                Icons.payments_outlined,
              ),
              AdminStat(
                'طلبات سُلّمت في الفترة',
                '${data['delivered_orders'] ?? 0}',
                Icons.check_circle_outline,
              ),
              AdminStat(
                'متوسط قيمة الطلب المسلّم',
                adminMoney(data['average_order_value'] as num? ?? 0),
                Icons.insights,
              ),
              AdminStat(
                'طلبات أُنشئت في الفترة',
                '${data['created_orders'] ?? 0}',
                Icons.receipt_long_outlined,
              ),
            ],
          ),
          const SizedBox(height: 22),
          AdminCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LText(
                  'المبيعات اليومية',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                ),
                const SizedBox(height: 6),
                LText(
                  'قيمة الطلبات المسلّمة في كل يوم',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(height: 22),
                if (series.every((day) => (day['sales'] as num? ?? 0) == 0))
                  const AdminEmpty(
                    'لا توجد مبيعات مسلّمة خلال الفترة المختارة',
                    icon: Icons.bar_chart,
                  )
                else
                  _chart(series),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AdminCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LText(
                  'الأطباق الأكثر طلبًا',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                ),
                const SizedBox(height: 6),
                LText(
                  'من الطلبات المسلّمة خلال الفترة المختارة',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                if (top.isEmpty)
                  const AdminEmpty(
                    'ستظهر الأطباق هنا بعد تسليم الطلبات',
                    icon: Icons.restaurant_menu,
                  )
                else ...[
                  const SizedBox(height: 16),
                  for (final item in top)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: LText(
                              item['name'] as String,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              LText(
                                '${item['quantity']} وجبة',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              LText(
                                adminMoney(item['sales'] as num? ?? 0),
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          LText(
            'قد يختلف عدد الطلبات المنشأة عن المسلّمة، لأن الطلب قد يُسلّم في يوم آخر.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          if (estimated > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: LText(
                'تتضمن الفترة $estimated طلبًا قديمًا بلا وقت تسليم مسجل؛ احتُسبت بتاريخ إنشائها.',
                style: const TextStyle(fontSize: 12, color: AppColors.orange),
              ),
            ),
        ],
      ],
    );
  }

  Widget _chart(List<Map> days) => LayoutBuilder(
    builder: (context, constraints) {
      final maximum = days.fold<num>(
        0,
        (value, day) => math.max(value, day['sales'] as num),
      );
      final width = math.max(constraints.maxWidth, days.length * 48.0);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final day in days)
                Expanded(
                  child: Tooltip(
                    message:
                        '${_day(day['date'] as String)}: ${adminMoney(day['sales'] as num)}'
                            .tr(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 130,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                height: math.max(
                                  3.0,
                                  120 * (day['sales'] as num) / maximum,
                                ),
                                constraints: const BoxConstraints(maxWidth: 44),
                                decoration: BoxDecoration(
                                  color: (day['sales'] as num) == 0
                                      ? Colors.grey.shade200
                                      : AppColors.darkGreen,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          LText(
                            _day(
                              day['date'] as String,
                            ).split('/').take(2).join('/'),
                            style: const TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
