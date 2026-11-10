import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
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
  Future<void> _add(MenuItemModel item, {int quantity = 1, String note = ''}) async {
    if (!store.canAddFrom(widget.cafeteria)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('بدء سلة جديدة؟'),
          content: Text('سلتك تحتوي أصنافاً من "${store.cartCafeteria}". لا يمكن الطلب من كافيتريتين بنفس الطلب.\nهل تريد إفراغ السلة والبدء من جديد؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إفراغ وإضافة')),
          ],
        ),
      );
      if (ok != true) return;
      store.clearCart();
    }
    if (!mounted) return;
    showResult(context, store.addToCart(widget.cafeteria, item, quantity: quantity, note: note));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final status = info.status;
        final closed = status == CafeteriaStatus.closed;
        final menu = store.menuFor(widget.cafeteria);
        var items = (menu ?? const <MenuItemModel>[]).where((m) => m.name.contains(_query.trim())).toList();
        if (_filter == _Filter.available) items = items.where((m) => m.isAvailable).toList();
        if (_filter == _Filter.favorites) items = items.where(store.isFavorite).toList();
        // المتوفر أولاً، والمنتهي في الأسفل
        items.sort((a, b) => (b.isAvailable ? 1 : 0) - (a.isAvailable ? 1 : 0));
        final cartHere = store.cartCafeteria == widget.cafeteria && store.cartCount > 0;

        return Scaffold(
          backgroundColor: AppColors.bgCream,
          appBar: AppBar(
            backgroundColor: AppColors.darkGreen,
            foregroundColor: Colors.white,
            title: Text(widget.cafeteria, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ),
          body: Column(
            children: [
              // رأس الصفحة: الحالة + البحث + الفلاتر
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CafeteriaStatusChip(status: status),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            switch (status) {
                              CafeteriaStatus.open => 'تستقبل الطلبات الآن • ${info.hoursLabel}',
                              CafeteriaStatus.busy => 'مزدحمة الآن، قد يتأخر التجهيز قليلاً',
                              CafeteriaStatus.closed => 'مغلقة الآن • أوقات الدوام ${info.hoursLabel}',
                            },
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: 'ابحث عن صنف...',
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                        filled: true,
                        fillColor: AppColors.bgCream,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final f in _Filter.values)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 8),
                            child: ChoiceChip(
                              label: Text(switch (f) {
                                _Filter.all => 'الكل',
                                _Filter.available => 'المتوفر',
                                _Filter.favorites => 'المفضلة',
                              }),
                              selected: _filter == f,
                              selectedColor: AppColors.orange.withValues(alpha: 0.25),
                              onSelected: (_) => setState(() => _filter = f),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (closed)
                MaterialBanner(
                  backgroundColor: Colors.red.shade50,
                  leading: Icon(Icons.lock_clock, color: Colors.red.shade700),
                  content: const Text('الكافيتريا مغلقة حالياً، يمكنك تصفح القائمة لكن لا يمكن الطلب.'),
                  actions: const [SizedBox.shrink()],
                ),
              Expanded(
                child: menu == null
                    ? (_loadError == null
                        ? const Center(child: CircularProgressIndicator())
                        : EmptyState(
                            icon: Icons.wifi_off,
                            title: 'تعذّر تحميل القائمة',
                            subtitle: _loadError,
                            action: FilledButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh),
                              label: const Text('إعادة المحاولة'),
                            ),
                          ))
                    : items.isEmpty
                    ? EmptyState(
                        icon: Icons.search_off,
                        title: _filter == _Filter.favorites ? 'لا توجد أصناف مفضلة هنا' : 'لا توجد أصناف مطابقة',
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, cartHere ? 96 : 16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _MenuItemCard(
                          item: items[i],
                          canOrder: !closed,
                          inCart: store.cartCafeteria == widget.cafeteria ? store.quantityInCart(items[i]) : 0,
                          onAdd: () => _add(items[i]),
                          onDetails: () => _openDetails(items[i], closed),
                        ),
                      ),
              ),
            ],
          ),
          bottomSheet: cartHere
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: SizedBox(
                      height: 54,
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.darkGreen,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen())),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: AppColors.orange,
                              child: Text('${store.cartCount}', style: const TextStyle(color: Colors.white, fontSize: 13)),
                            ),
                            const SizedBox(width: 10),
                            const Text('عرض السلة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Text(formatPrice(store.cartTotal), style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }

  /// تفاصيل الصنف: الكمية + ملاحظة (مثلاً: بدون بصل)
  Future<void> _openDetails(MenuItemModel item, bool closed) async {
    var qty = 1;
    final note = TextEditingController();
    const quickNotes = ['بدون بصل', 'بدون طماطم', 'حار', 'صوص إضافي', 'بدون سكر'];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // زر إغلاق واضح (إضافة للسحب للأسفل أو الضغط خارج البطاقة)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: IconButton(
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ),
                Center(child: MenuItemImage(item: item, size: 120)),
                const SizedBox(height: 12),
                Text(item.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('${formatPrice(item.priceValue)} • تحضير ${item.preptime}',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
                if (item.averageRating != null) ...[
                  const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    StarRating(value: item.averageRating!),
                    Text(' (${item.ratingCount})', style: const TextStyle(fontSize: 12)),
                  ]),
                ],
                // سبب عدم إمكانية الطلب + زر رجوع
                if (!item.isAvailable || closed) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        Icon(closed ? Icons.lock_clock : Icons.block, color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            closed
                                ? 'الكافيتريا مغلقة الآن (الدوام ${info.hoursLabel})، لا يمكن الطلب حالياً.'
                                : 'هذا الصنف منتهٍ حالياً.',
                            style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('رجوع للقائمة')),
                ],
                if (item.isAvailable && !closed) ...[
                  const SizedBox(height: 16),
                  const Text('ملاحظات للمطبخ', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final q in quickNotes)
                        ActionChip(
                          label: Text(q),
                          onPressed: () => setS(() {
                            note.text = note.text.trim().isEmpty ? q : '${note.text.trim()}، $q';
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: note,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      hintText: 'مثال: بدون بصل',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.outlined(onPressed: qty > 1 ? () => setS(() => qty--) : null, icon: const Icon(Icons.remove)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text('$qty', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      ),
                      IconButton.outlined(onPressed: qty < 20 ? () => setS(() => qty++) : null, icon: const Icon(Icons.add)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.darkGreen),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _add(item, quantity: qty, note: note.text);
                      },
                      child: Text('أضف للسلة • ${formatPrice(item.priceValue * qty)}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
  final VoidCallback onDetails;

  const _MenuItemCard({
    required this.item,
    required this.canOrder,
    required this.inCart,
    required this.onAdd,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final store = StudentStore.instance;
    final available = item.isAvailable;

    return Card(
      margin: EdgeInsets.zero,
      elevation: available ? 2 : 0,
      color: available ? Colors.white : Colors.grey.shade100,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onDetails,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Stack(
                children: [
                  MenuItemImage(item: item, size: 76),
                  if (!available)
                    Positioned.fill(
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(12)),
                        child: const Text('نفد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: available ? Colors.black87 : Colors.grey,
                        decoration: available ? null : TextDecoration.lineThrough,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(formatPrice(item.priceValue),
                        style: TextStyle(
                            color: available ? AppColors.darkGreen : Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.timer_outlined, size: 14, color: Colors.grey.shade600),
                        Text(' ${item.preptime}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        if (item.averageRating != null) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.star_rounded, size: 15, color: AppColors.orange),
                          Text(item.averageRating!.toStringAsFixed(1), style: const TextStyle(fontSize: 12)),
                        ],
                      ],
                    ),
                    if (!available)
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
                        child: Text('منتهٍ حالياً', style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              ),
              Column(
                children: [
                  IconButton(
                    tooltip: 'المفضلة',
                    onPressed: () async {
                      final r = await store.toggleFavorite(item);
                      if (!r.ok && context.mounted) showResult(context, r);
                    },
                    icon: Icon(store.isFavorite(item) ? Icons.favorite : Icons.favorite_border,
                        color: store.isFavorite(item) ? Colors.red : Colors.grey),
                  ),
                  if (available && canOrder)
                    Badge(
                      isLabelVisible: inCart > 0,
                      label: Text('$inCart'),
                      backgroundColor: AppColors.orange,
                      child: IconButton.filled(
                        tooltip: 'أضف للسلة',
                        style: IconButton.styleFrom(backgroundColor: AppColors.darkGreen),
                        onPressed: onAdd,
                        icon: const Icon(Icons.add, color: Colors.white),
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
}
