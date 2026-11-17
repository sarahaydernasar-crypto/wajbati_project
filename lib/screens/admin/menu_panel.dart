import '../../localization/localized_widgets.dart';
import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../models/order_model.dart';
import '../student/student_widgets.dart' show MenuItemImage;
import 'admin_widgets.dart';

class MenuPanel extends StatefulWidget {
  final List<MenuItemModel> items;
  final VoidCallback onAdd;
  final Future<void> Function(MenuItemModel) onEdit;
  final Future<void> Function(MenuItemModel) onImage;
  final Future<void> Function(MenuItemModel) onDelete;
  final Future<void> Function(MenuItemModel, bool) onAvailability;
  const MenuPanel({
    super.key,
    required this.items,
    required this.onAdd,
    required this.onEdit,
    required this.onImage,
    required this.onDelete,
    required this.onAvailability,
  });

  @override
  State<MenuPanel> createState() => _MenuPanelState();
}

class _MenuPanelState extends State<MenuPanel> {
  String _query = '';
  String _filter = 'all';
  final Set<int?> _pending = {};

  Future<void> _run(MenuItemModel item, Future<void> Function() action) async {
    if (_pending.contains(item.id)) return;
    setState(() => _pending.add(item.id));
    try {
      await action();
    } finally {
      if (mounted) setState(() => _pending.remove(item.id));
    }
  }

  Future<void> _delete(MenuItemModel item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const LText('حذف الطبق؟'),
        content: LText(
          'سيُحذف «${item.name}» من المنيو، وتبقى الطلبات السابقة محفوظة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const LText('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const LText('حذف الطبق'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(item, () => widget.onDelete(item));
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.items.where((item) => item.isAvailable).length;
    final visible = widget.items
        .where(
          (item) =>
              item.name.toLowerCase().contains(_query.toLowerCase()) &&
              (_filter == 'all' ||
                  (_filter == 'available'
                      ? item.isAvailable
                      : !item.isAvailable)),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AdminHeading(
          title: 'منيو الكافيتريا',
          subtitle: 'صور واضحة وأطباق مرتبة. تحكّم بما يستطيع الطلاب طلبه.',
          action: FilledButton.icon(
            onPressed: widget.onAdd,
            icon: const Icon(Icons.add),
            label: const LText('إضافة طبق جديد'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.darkGreen),
          ),
        ),
        LTextField(
          decoration: const InputDecoration(
            hintText: 'ابحث عن طبق',
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
            for (final entry in {
              'all': 'كل الأطباق (${widget.items.length})',
              'available': 'متوفر ($available)',
              'unavailable': 'غير متوفر (${widget.items.length - available})',
            }.entries)
              ChoiceChip(
                label: LText(entry.value),
                selected: _filter == entry.key,
                onSelected: (_) => setState(() => _filter = entry.key),
              ),
          ],
        ),
        const SizedBox(height: 22),
        if (visible.isEmpty)
          const AdminEmpty(
            'لا توجد أطباق تطابق هذا العرض',
            icon: Icons.restaurant_menu,
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1050
                  ? 4
                  : constraints.maxWidth >= 760
                  ? 3
                  : constraints.maxWidth >= 500
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 16) / columns;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final item in visible)
                    SizedBox(width: width, child: _dish(item)),
                ],
              );
            },
          ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _dish(MenuItemModel item) {
    final busy = _pending.contains(item.id);
    final photo = MenuItemImage(
      item: item,
      width: double.infinity,
      height: double.infinity,
      radius: 0,
    );
    return AdminCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  photo,
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      child: AdminBadge(
                        item.isAvailable ? 'متوفر' : 'غير متوفر',
                        color: item.isAvailable
                            ? AppColors.darkGreen
                            : Colors.grey.shade700,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: IconButton.filled(
                      tooltip: ('تغيير صورة ${item.name}').tr(context),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.darkGreen,
                      ),
                      onPressed: busy
                          ? null
                          : () => _run(item, () => widget.onImage(item)),
                      icon: const Icon(Icons.photo_camera_outlined),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LText(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkGreen,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    LText(
                      adminMoney(item.priceValue),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    LText(
                      '${item.prepMinutes} دقيقة',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(
                      child: LText(
                        'متاح للطلب',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    Switch(
                      value: item.isAvailable,
                      activeThumbColor: AppColors.darkGreen,
                      onChanged: busy
                          ? null
                          : (value) => _run(
                              item,
                              () => widget.onAvailability(item, value),
                            ),
                    ),
                  ],
                ),
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: busy ? null : () => widget.onEdit(item),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const LText('تعديل'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Tooltip(
                        message: 'حذف ${item.name}',
                        child: TextButton.icon(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const LText('حذف'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.danger,
                          ),
                          onPressed: busy ? null : () => _delete(item),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
