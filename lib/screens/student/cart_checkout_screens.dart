import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/app_colors.dart';
import '../../services/api_client.dart';
import 'student_store.dart';
import 'student_widgets.dart';

// =====================================================================
//  السلة: تعديل الكميات وإضافة ملاحظات
// =====================================================================
class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StudentStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final cart = store.cart;
        final unavailable = store.unavailableInCart;
        return Scaffold(
          backgroundColor: AppColors.bgCream,
          appBar: AppBar(
            backgroundColor: AppColors.darkGreen,
            foregroundColor: Colors.white,
            title: const Text('السلة', style: TextStyle(fontWeight: FontWeight.bold)),
            actions: [
              if (cart.isNotEmpty)
                TextButton(
                  onPressed: () => store.clearCart(),
                  child: const Text('إفراغ', style: TextStyle(color: Colors.white)),
                ),
            ],
          ),
          body: cart.isEmpty
              ? EmptyState(
                  icon: Icons.shopping_bag_outlined,
                  title: 'سلتك فارغة',
                  subtitle: 'أضف أصنافاً من قائمة إحدى الكافيتريات',
                  action: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('تصفح الكافيتريات')),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.storefront, color: AppColors.darkGreen),
                        const SizedBox(width: 6),
                        Text(store.cartCafeteria ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (unavailable.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber, color: Colors.red.shade700),
                            const SizedBox(width: 8),
                            const Expanded(child: Text('بعض الأصناف نفدت بعد إضافتها. احذفها لإكمال الطلب.')),
                          ],
                        ),
                      ),
                    for (final e in cart) _CartEntryCard(entry: e),
                    const SizedBox(height: 8),
                    _summaryRow('عدد الأصناف', '${store.cartCount}'),
                    _summaryRow('أقصى وقت تحضير', '${store.cartMaxPrepMinutes} دقيقة'),
                    const Divider(),
                    _summaryRow('المجموع', formatPrice(store.cartTotal), bold: true),
                    const SizedBox(height: 90),
                  ],
                ),
          bottomSheet: cart.isEmpty
              ? null
              : _BottomAction(
                  label: 'اختيار وقت الاستلام',
                  enabled: unavailable.isEmpty,
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PickupTimeScreen())),
                ),
        );
      },
    );
  }
}

class _CartEntryCard extends StatelessWidget {
  final CartEntry entry;
  const _CartEntryCard({required this.entry});

  Future<void> _editNote(BuildContext context) async {
    final ctrl = TextEditingController(text: entry.note);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('ملاحظة على "${entry.item.name}"'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(hintText: 'مثال: بدون بصل', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('حفظ')),
        ],
      ),
    );
    if (result != null) StudentStore.instance.updateNote(entry, result);
  }

  @override
  Widget build(BuildContext context) {
    final store = StudentStore.instance;
    final available = entry.item.isAvailable;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: available ? BorderSide.none : BorderSide(color: Colors.red.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MenuItemImage(item: entry.item, size: 60),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (!available)
                    Text('نفد - احذفه من السلة', style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
                  Text(formatPrice(entry.total), style: const TextStyle(color: AppColors.darkGreen, fontWeight: FontWeight.bold)),
                  InkWell(
                    onTap: () => _editNote(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(Icons.edit_note, size: 18, color: Colors.grey.shade700),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              entry.note.isEmpty ? 'أضف ملاحظة (مثلاً بدون بصل)' : entry.note,
                              style: TextStyle(
                                fontSize: 12,
                                color: entry.note.isEmpty ? Colors.grey.shade600 : AppColors.orange,
                                fontWeight: entry.note.isEmpty ? null : FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                IconButton(
                  tooltip: 'حذف',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => store.removeFromCart(entry),
                  icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
                ),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _stepBtn(Icons.remove, () => store.changeQuantity(entry, -1)),
                      Text('${entry.quantity}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      _stepBtn(Icons.add, available && entry.quantity < 20 ? () => store.changeQuantity(entry, 1) : null),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap) => IconButton(
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        onPressed: onTap,
        icon: Icon(icon),
      );
}

// =====================================================================
//  اختيار وقت الاستلام (من الأوقات المتاحة فقط)
// =====================================================================
class PickupTimeScreen extends StatefulWidget {
  const PickupTimeScreen({super.key});

  @override
  State<PickupTimeScreen> createState() => _PickupTimeScreenState();
}

class _PickupTimeScreenState extends State<PickupTimeScreen> {
  final store = StudentStore.instance;
  DateTime? _selected;
  Map<DateTime, int>? _slots;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// جلب الأوقات المتاحة من السيرفر
  Future<void> _load() async {
    final cafeteria = store.cartCafeteria;
    if (cafeteria == null) return;
    setState(() => _error = null);
    try {
      final slots = await store.fetchSlots(cafeteria);
      if (!mounted) return;
      setState(() {
        _slots = slots;
        // إذا امتلأ الوقت المختار في هذه الأثناء
        if (_selected != null && !store.isSlotAvailable(slots[_selected] ?? StudentStore.slotCapacity)) {
          _selected = null;
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _continue() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentScreen(pickupTime: _selected!)));
    // عند الرجوع (مثلاً امتلأ الوقت) نحدّث الأوقات
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final cafeteria = store.cartCafeteria;
        final slots = _slots ?? const <DateTime, int>{};
        final anyAvailable = slots.values.any(store.isSlotAvailable);

        return Scaffold(
          backgroundColor: AppColors.bgCream,
          appBar: AppBar(
            backgroundColor: AppColors.darkGreen,
            foregroundColor: Colors.white,
            title: const Text('وقت الاستلام', style: TextStyle(fontWeight: FontWeight.bold)),
            actions: [IconButton(tooltip: 'تحديث', onPressed: _load, icon: const Icon(Icons.refresh))],
          ),
          body: _error != null
              ? EmptyState(
                  icon: Icons.wifi_off,
                  title: 'تعذّر تحميل أوقات الاستلام',
                  subtitle: _error,
                  action: FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                )
              : _slots == null
              ? const Center(child: CircularProgressIndicator())
              : !anyAvailable
              ? const EmptyState(
                  icon: Icons.event_busy,
                  title: 'لا توجد أوقات استلام متاحة اليوم',
                  subtitle: 'الكافيتريا مغلقة أو قاربت على الإغلاق، أو كل الأوقات محجوزة. جرّب كافيتريا أخرى.',
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('متى تريد استلام طلبك من $cafeteria؟',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text('أقرب وقت محسوب حسب وقت تحضير طلبك (${store.cartMaxPrepMinutes} دقيقة). الأوقات الممتلئة غير قابلة للاختيار.',
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in slots.entries)
                          _SlotChip(
                            time: entry.key,
                            booked: entry.value,
                            selected: _selected == entry.key,
                            onTap: store.isSlotAvailable(entry.value) ? () => setState(() => _selected = entry.key) : null,
                          ),
                      ],
                    ),
                    const SizedBox(height: 100),
                  ],
                ),
          bottomSheet: _BottomAction(
            label: _selected == null ? 'اختر وقتاً للمتابعة' : 'المتابعة للدفع • ${formatTime(_selected!)}',
            enabled: _selected != null && cafeteria != null,
            onPressed: _continue,
          ),
        );
      },
    );
  }
}

class _SlotChip extends StatelessWidget {
  final DateTime time;
  final int booked;
  final bool selected;
  final VoidCallback? onTap;

  const _SlotChip({required this.time, required this.booked, required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) {
    final full = onTap == null;
    final left = StudentStore.slotCapacity - booked;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.darkGreen : (full ? Colors.grey.shade200 : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.darkGreen : Colors.grey.shade300),
        ),
        child: Column(
          children: [
            Text(formatTime(time),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: selected ? Colors.white : (full ? Colors.grey : Colors.black87),
                  decoration: full ? TextDecoration.lineThrough : null,
                )),
            Text(
              full ? 'ممتلئ' : (left <= 1 ? 'آخر مكان' : 'متاح'),
              style: TextStyle(
                fontSize: 11,
                color: selected ? Colors.white70 : (full ? Colors.red.shade400 : (left <= 1 ? AppColors.orange : AppColors.lightGreen)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
//  شاشة الدفع
// =====================================================================
class PaymentScreen extends StatefulWidget {
  final DateTime pickupTime;
  const PaymentScreen({super.key, required this.pickupTime});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  static const _methods = [
    ('cash', 'نقداً عند الاستلام', Icons.payments_outlined),
    ('card', 'بطاقة مصرفية', Icons.credit_card),
    ('wallet', 'محفظة إلكترونية', Icons.account_balance_wallet_outlined),
  ];

  final store = StudentStore.instance;
  final _formKey = GlobalKey<FormState>();
  final _cardNumber = TextEditingController();
  final _expiry = TextEditingController();
  final _cvv = TextEditingController();
  final _walletPhone = TextEditingController();
  String _method = 'cash';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _walletPhone.text = store.currentStudent?.phone ?? '';
  }

  @override
  void dispose() {
    for (final c in [_cardNumber, _expiry, _cvv, _walletPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pay() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    setState(() => _loading = true);
    try {
      final label = _methods.firstWhere((m) => m.$1 == _method).$2;
      final r = await store.placeOrder(pickupTime: widget.pickupTime, paymentMethod: label);
      if (!mounted) return;
      if (r.ok) {
        // الرجوع للشاشة الرئيسية وفتح "طلباتي" حيث يُتابَع الطلب
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).popUntil((route) => route.isFirst);
        store.openTab(StudentStore.ordersTab);
        messenger.showSnackBar(SnackBar(
          content: Text('تم إرسال طلبك #${r.message} بنجاح! تابع حالته من هنا'),
          backgroundColor: AppColors.darkGreen,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ));
      } else {
        await _showError(r.message);
      }
    } catch (_) {
      if (mounted) await _showError('انقطع الاتصال أثناء إرسال الطلب. تحقق من الإنترنت وحاول مرة أخرى، لن يتم خصم أي مبلغ.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showError(String message) => showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.error_outline, color: Colors.red.shade700, size: 40),
          title: const Text('تعذّر إتمام الطلب'),
          content: Text(message, textAlign: TextAlign.center),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgCream,
      appBar: AppBar(
        backgroundColor: AppColors.darkGreen,
        foregroundColor: Colors.white,
        title: const Text('الدفع وتأكيد الطلب', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ملخص الطلب
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ملخص الطلب', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    for (final e in store.cart)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${e.quantity}× ', style: const TextStyle(fontWeight: FontWeight.bold)),
                            Expanded(
                              child: Text(e.note.isEmpty ? e.item.name : '${e.item.name}\n(${e.note})'),
                            ),
                            Text(formatPrice(e.total)),
                          ],
                        ),
                      ),
                    const Divider(),
                    _summaryRow('الكافيتريا', store.cartCafeteria ?? ''),
                    _summaryRow('وقت الاستلام', formatTime(widget.pickupTime)),
                    _summaryRow('المجموع', formatPrice(store.cartTotal), bold: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('طريقة الدفع', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            for (final m in _methods)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: _method == m.$1 ? AppColors.darkGreen : Colors.transparent, width: 1.5),
                ),
                child: ListTile(
                  onTap: () => setState(() => _method = m.$1),
                  leading: Icon(m.$3, color: AppColors.darkGreen),
                  title: Text(m.$2),
                  trailing: Icon(
                    _method == m.$1 ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: _method == m.$1 ? AppColors.darkGreen : Colors.grey,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            if (_method == 'card') ...[
              TextFormField(
                controller: _cardNumber,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(16)],
                decoration: _field('رقم البطاقة (16 رقم)', Icons.credit_card),
                validator: (v) => (v ?? '').length != 16 ? 'رقم البطاقة يجب أن يكون 16 رقماً' : null,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _expiry,
                      keyboardType: TextInputType.datetime,
                      decoration: _field('MM/YY', Icons.date_range),
                      validator: (v) => RegExp(r'^(0[1-9]|1[0-2])/\d{2}$').hasMatch(v ?? '') ? null : 'صيغة غير صحيحة',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _cvv,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                      decoration: _field('CVV', Icons.lock_outline),
                      validator: (v) => (v ?? '').length != 3 ? '3 أرقام' : null,
                    ),
                  ),
                ],
              ),
            ],
            if (_method == 'wallet')
              TextFormField(
                controller: _walletPhone,
                keyboardType: TextInputType.phone,
                decoration: _field('رقم المحفظة', Icons.phone_iphone),
                validator: (v) => RegExp(r'^07\d{9}$').hasMatch(StudentStore.normalizePhone(v ?? '')) ? null : 'رقم غير صالح',
              ),
            if (_method != 'cash')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('⚠️ الدفع الإلكتروني تجريبي حالياً ولن يتم خصم أي مبلغ.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              ),
            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomSheet: _BottomAction(
        label: _method == 'cash' ? 'تأكيد الطلب' : 'ادفع ${formatPrice(store.cartTotal)}',
        enabled: !_loading && store.cart.isNotEmpty,
        loading: _loading,
        onPressed: _pay,
      ),
    );
  }

  InputDecoration _field(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );
}

// =================== عناصر مشتركة ===================
Widget _summaryRow(String label, String value, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: bold ? Colors.black87 : Colors.grey.shade700, fontWeight: bold ? FontWeight.bold : null)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                fontSize: bold ? 17 : 14,
                color: bold ? AppColors.darkGreen : null,
              )),
        ],
      ),
    );

class _BottomAction extends StatelessWidget {
  final String label;
  final bool enabled;
  final bool loading;
  final VoidCallback onPressed;

  const _BottomAction({required this.label, required this.enabled, required this.onPressed, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        color: AppColors.bgCream,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          height: 54,
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.darkGreen,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: enabled ? onPressed : null,
            child: loading
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }
}
