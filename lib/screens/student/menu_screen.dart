import '../../localization/localized_widgets.dart';
import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_theme.dart';
import '../../widgets/app_feedback.dart';
import '../../widgets/cart_dock.dart';
import '../../widgets/quantity_stepper.dart';
import '../../models/order_model.dart';
import 'cart_checkout_screens.dart';
import 'student_store.dart';
import 'student_widgets.dart';

/// صفحة قائمة الكافيتريا: الأصناف، الصور، الأسعار، والأصناف المنتهية بشكل واضح
class MenuScreen extends StatefulWidget {
  final String cafeteria;
  const MenuScreen({super.key, required this.cafeteria});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

enum _Filter { all, available, favorites }

class _MenuScreenState extends State<MenuScreen> {
  final store = StudentStore.instance;
  String _query = '';
  _Filter _filter = _Filter.all;
  String? _loadError;

  CafeteriaInfo get info => store.cafeterias[widget.cafeteria]!;

  @override
  void initState() {
    super.initState();
    store.watchMenu(widget.cafeteria); // تحديث دوري لتوفر الأصناف
    _load();
  }

  @override
  void dispose() {
    store.unwatchMenu(widget.cafeteria);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    final r = await store.loadMenu(widget.cafeteria);
    if (mounted && !r.ok) setState(() => _loadError = r.message);
  }

  /// إضافة مع التعامل مع سلة من كافيتريا أخرى
  Future<void> _add(
    MenuItemModel item, {
    int quantity = 1,
    String note = '',
    bool quiet = false,
  }) async {
    if (!store.canAddFrom(widget.cafeteria)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const LText('بدء سلة جديدة؟'),
          content: LText(
            'سلتك تحتوي أصنافاً من "${store.cartCafeteria}". لا يمكن الطلب من كافيتريتين بنفس الطلب.\nهل تريد إفراغ السلة والبدء من جديد؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const LText('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const LText('إفراغ وإضافة'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      store.clearCart();
    }
    if (!mounted) return;
    final result = store.addToCart(
      widget.cafeteria,
      item,
      quantity: quantity,
      note: note,
    );
    if (!quiet || !result.ok) showResult(context, result);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final closed = info.status == CafeteriaStatus.closed;
      final menu = store.menuFor(widget.cafeteria);
      var items = (menu ?? const <MenuItemModel>[])
          .where(
            (item) =>
                item.name.toLowerCase().contains(_query.trim().toLowerCase()),
          )
          .toList();
      if (_filter == _Filter.available) {
        items = items.where((item) => item.isAvailable).toList();
      }
      if (_filter == _Filter.favorites) {
        items = items.where(store.isFavorite).toList();
      }
      items.sort((a, b) => (b.isAvailable ? 1 : 0) - (a.isAvailable ? 1 : 0));
      final error = _loadError ?? store.connectionError;
      return Scaffold(
        appBar: AppBar(
          title: LText(widget.cafeteria, overflow: TextOverflow.ellipsis),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final columns = ((constraints.maxWidth - 32) / 280).floor().clamp(
              1,
              4,
            );
            final cardWidth =
                (constraints.maxWidth - 32 - (columns - 1) * 16) / columns;
            final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
            return RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                cacheExtent: 450,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              CafeteriaStatusChip(status: info.status),
                              LText(
                                info.hoursLabel,
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          LTextField(
                            onChanged: (value) =>
                                setState(() => _query = value),
                            decoration: const InputDecoration(
                              hintText: 'ابحث عن صنف...',
                              prefixIcon: Icon(Icons.search),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final filter in _Filter.values)
                                ChoiceChip(
                                  label: LText(switch (filter) {
                                    _Filter.all => 'الكل',
                                    _Filter.available => 'المتوفر',
                                    _Filter.favorites => 'المفضلة',
                                  }),
                                  selected: _filter == filter,
                                  onSelected: (_) =>
                                      setState(() => _filter = filter),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (closed)
                    const SliverToBoxAdapter(
                      child: AppNotice(
                        message:
                            'الكافيتريا مغلقة حاليًا. يمكنك تصفح الأطباق والطلب عند فتحها.',
                      ),
                    ),
                  if (error != null && menu != null)
                    SliverToBoxAdapter(
                      child: AppNotice(
                        message: '$error\nقد تكون القائمة المعروضة غير محدّثة.',
                        error: true,
                        onRetry: _load,
                      ),
                    ),
                  if (menu == null)
                    SliverFillRemaining(
                      child: error == null
                          ? const LoadingCards(
                              label: 'جارٍ تجهيز قائمة الأطباق...',
                            )
                          : EmptyState(
                              icon: Icons.wifi_off,
                              title: 'تعذّر تحميل القائمة',
                              subtitle: error,
                              action: FilledButton.icon(
                                onPressed: _load,
                                icon: const Icon(Icons.refresh),
                                label: const LText('إعادة المحاولة'),
                              ),
                            ),
                    )
                  else if (items.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                        icon: Icons.search_off,
                        title: _filter == _Filter.favorites
                            ? 'لا توجد أصناف مفضلة هنا'
                            : 'لا توجد أصناف مطابقة',
                        subtitle: 'جرّب تغيير البحث أو الفلتر.',
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          mainAxisExtent:
                              cardWidth * .625 +
                              235 +
                              (scale > 1 ? (scale - 1) * 160 : 0),
                        ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final item = items[index];
                          final quantity =
                              store.cartCafeteria == widget.cafeteria
                              ? store.quantityInCart(item)
                              : 0;
                          return _MenuItemCard(
                            key: ValueKey(item.id),
                            item: item,
                            canOrder: !closed,
                            inCart: quantity,
                            onAdd: () => _add(item, quiet: quantity > 0),
                            onRemove: () => store.decreaseItem(item),
                            onDetails: () => _openDetails(item, closed),
                          );
                        }, childCount: items.length),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                ],
              ),
            );
          },
        ),
        bottomNavigationBar: QuietSize(
          alignment: Alignment.bottomCenter,
          child: store.cartCount > 0
              ? CartDock(
                  total: store.cartTotal,
                  count: store.cartCount,
                  message: store.cartCafeteria != widget.cafeteria
                      ? 'السلة من ${store.cartCafeteria}'
                      : null,
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CartScreen()),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      );
    },
  );

  /// تفاصيل الصنف: الكمية + ملاحظة (مثلاً: بدون بصل)
  Future<void> _openDetails(MenuItemModel item, bool closed) async {
    var qty = 1;
    final note = TextEditingController();
    final removable = item.removableIngredients
        .where(item.ingredients.contains)
        .toSet();
    final removed = <String>{};
    String orderNote() => [
      ...removed.map((ingredient) => 'بدون $ingredient'),
      if (note.text.trim().isNotEmpty) note.text.trim(),
    ].join('، ');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // زر إغلاق واضح (إضافة للسحب للأسفل أو الضغط خارج البطاقة)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: IconButton(
                    tooltip: ('إغلاق').tr(context),
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ),
                Center(child: MenuItemImage(item: item, size: 120)),
                const SizedBox(height: 12),
                LText(
                  item.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                LText(
                  '${formatPrice(item.priceValue)} • تحضير ${item.preptime}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                if (item.averageRating != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      StarRating(value: item.averageRating!),
                      LText(
                        ' (${item.ratingCount})',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ],
                if (item.ingredients.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const LText(
                    'المكونات',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  LText(item.ingredients.join('، ')),
                ],
                // سبب عدم إمكانية الطلب + زر رجوع
                if (!item.isAvailable || closed) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          closed ? Icons.lock_clock : Icons.block,
                          color: Colors.red.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: LText(
                            closed
                                ? 'الكافيتريا مغلقة الآن (الدوام ${info.hoursLabel})، لا يمكن الطلب حالياً.'
                                : 'هذا الصنف منتهٍ حالياً.',
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const LText('رجوع للقائمة'),
                  ),
                ],
                if (item.isAvailable && !closed) ...[
                  const SizedBox(height: 16),
                  const LText(
                    'ملاحظات للمطبخ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (removable.isNotEmpty) ...[
                    const LText('إزالة مكونات (اختياري)'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final ingredient in removable)
                          FilterChip(
                            label: LText('بدون $ingredient'),
                            selected: removed.contains(ingredient),
                            onSelected: (selected) => setS(() {
                              if (selected) {
                                removed.add(ingredient);
                              } else {
                                removed.remove(ingredient);
                              }
                            }),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  LTextField(
                    controller: note,
                    maxLength: 80,
                    onChanged: (_) => setS(() {}),
                    decoration: const InputDecoration(
                      hintText: 'ملاحظة إضافية للمطبخ (اختياري)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  if (orderNote().length > 80)
                    const LText(
                      'اختصر الملاحظة أو قلّل المكونات المختارة؛ الحد 80 حرفاً.',
                      style: TextStyle(color: AppColors.danger),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.outlined(
                        onPressed: qty > 1 ? () => setS(() => qty--) : null,
                        icon: const Icon(Icons.remove),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: LText(
                          '$qty',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton.outlined(
                        onPressed: qty < 20 ? () => setS(() => qty++) : null,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.darkGreen,
                      ),
                      onPressed: orderNote().length > 80
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              _add(item, quantity: qty, note: orderNote());
                            },
                      child: LText(
                        'أضف للسلة • ${formatPrice(item.priceValue * qty)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuItemCard extends StatelessWidget {
  final MenuItemModel item;
  final bool canOrder;
  final int inCart;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onDetails;
  const _MenuItemCard({
    super.key,
    required this.item,
    required this.canOrder,
    required this.inCart,
    required this.onAdd,
    required this.onRemove,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final store = StudentStore.instance;
    final available = item.isAvailable;
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return SoftEntrance(
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onDetails,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MenuItemImage(
                      item: item,
                      width: double.infinity,
                      height: double.infinity,
                      radius: 0,
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: IconButton.filled(
                        tooltip: ('المفضلة').tr(context),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.darkGreen,
                        ),
                        onPressed: () async {
                          final result = await store.toggleFavorite(item);
                          if (!result.ok && context.mounted) {
                            showResult(context, result);
                          }
                        },
                        icon: Icon(
                          store.isFavorite(item)
                              ? Icons.favorite
                              : Icons.favorite_border,
                        ),
                      ),
                    ),
                    if (!available)
                      const Positioned(
                        bottom: 12,
                        right: 12,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.all(Radius.circular(30)),
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: LText(
                              'نفد',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 44 * scale,
                      child: LText(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                          color: available ? AppColors.ink : AppColors.muted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        LText(
                          formatPrice(item.priceValue),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.darkGreen,
                          ),
                        ),
                        if (item.averageRating != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                size: 16,
                                color: AppColors.orange,
                              ),
                              LText(
                                item.averageRating!.toStringAsFixed(1),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.timer_outlined,
                          size: 14,
                          color: AppColors.muted,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: LText(
                            item.preptime,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    AnimatedSwitcher(
                      duration: AppDesign.motion(context),
                      child: !available || !canOrder
                          ? SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: null,
                                child: LText(
                                  !available
                                      ? 'غير متوفر حاليًا'
                                      : 'الكافيتريا مغلقة',
                                ),
                              ),
                            )
                          : inCart == 0
                          ? Tooltip(
                              message: 'أضف للسلة',
                              child: SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: onAdd,
                                  icon: const Icon(Icons.add, size: 20),
                                  label: const LText('إضافة'),
                                ),
                              ),
                            )
                          : Center(
                              child: QuantityStepper(
                                key: const ValueKey('quantity'),
                                value: inCart,
                                itemName: item.name,
                                onDecrease: onRemove,
                                onIncrease: inCart < 20 ? onAdd : null,
                              ),
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
}
