import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/order_model.dart';
import '../services/cafeteria_admin_store.dart';
import '../services/password_dialog.dart';
import '../services/api_client.dart';
import 'student/student_store.dart'
    show ActionResult, CafeteriaStatus, OrderStatus, formatTime;
import 'student/student_widgets.dart' show MenuItemImage;

class DashboardScreen extends StatefulWidget {
  final String cafeteriaName;

  const DashboardScreen({super.key, required this.cafeteriaName});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _store = CafeteriaAdminStore.instance;

  // لمنع تكرار قراءة نفس الرمز عشرات المرات بالثانية
  String? _lastScanned;
  DateTime _lastScanTime = DateTime(2000);

  // صوت تنبيه الطلبات الجديدة
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<List<OrderItem>>? _newOrdersSub;
  String _query = '';
  String _statusFilter = 'all';
  bool _arrivedFirst = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _newOrdersSub = _store.onNewOrders.listen(_onNewOrders);
  }

  @override
  void dispose() {
    _newOrdersSub?.cancel();
    _player.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _onNewOrders(List<OrderItem> fresh) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.red.shade700,
        content: Text(
          fresh.length == 1
              ? '🔔 طلب جديد #${fresh.first.id} من ${fresh.first.studentName}'
              : '🔔 ${fresh.length} طلبات جديدة',
        ),
      ),
    );
    if (!_store.soundEnabled) return;
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/new_order.wav'));
    } catch (_) {
      // بعض المتصفحات تمنع الصوت قبل أول تفاعل من المستخدم؛ الرسالة تكفي حينها
    }
  }

  /// رفع/حذف صورة الصنف
  Future<void> _editImage(MenuItemModel item) async {
    final hasImage = item.imageUrl != null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                'صورة "${item.name}"',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(hasImage ? 'تغيير الصورة' : 'رفع صورة'),
              subtitle: const Text('JPG أو PNG، حتى 2 ميغابايت'),
              onTap: () => Navigator.pop(ctx, 'upload'),
            ),
            if (hasImage)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('حذف الصورة'),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (choice == 'delete') {
      _show(await _store.deleteImage(item));
    } else if (choice == 'upload') {
      final XFile? file;
      try {
        // تصغير الصورة قبل الرفع لتوفير البيانات وتسريع تحميل القائمة عند الطلاب
        file = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 800,
          imageQuality: 80,
        );
      } catch (_) {
        _show(const ActionResult.failure('تعذّر فتح معرض الصور.'));
        return;
      }
      if (file == null) return;
      final bytes = await file.readAsBytes();
      _show(await _store.uploadImage(item, bytes, file.name));
    }
  }

  void _show(ActionResult r) {
    if (r.message.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(r.message),
          backgroundColor: r.ok ? Colors.green : Colors.red,
        ),
      );
  }

  Future<void> _reject(OrderItem order) async {
    final reason = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('رفض الطلب #${order.id}'),
        content: TextField(
          controller: reason,
          maxLength: 300,
          decoration: const InputDecoration(
            labelText: 'سبب الرفض',
            hintText: 'مثال: نفدت الوجبة',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () {
              if (reason.text.trim().length >= 3) {
                Navigator.pop(ctx, reason.text.trim());
              }
            },
            child: const Text('رفض وإبلاغ الطالب'),
          ),
        ],
      ),
    );
    // Dispose after the dialog's closing animation stops reading its controller.
    if (value != null) _show(await _store.rejectOrder(order, value));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    reason.dispose();
  }

  void _logout() {
    _store.logout();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    // تحديث تلقائي كل بضع ثوانٍ من السيرفر (طلبات جديدة، "وصلت"...)
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(
            'إدارة: ${widget.cafeteriaName}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.green.shade900,
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              tooltip: _store.soundEnabled
                  ? 'كتم صوت الطلبات الجديدة'
                  : 'تشغيل صوت الطلبات الجديدة',
              onPressed: _store.toggleSound,
              icon: Icon(
                _store.soundEnabled ? Icons.volume_up : Icons.volume_off,
              ),
            ),
            _buildCafeteriaStatusMenu(),
            IconButton(
              tooltip: 'تغيير الرمز السري',
              icon: const Icon(Icons.key),
              onPressed: () =>
                  showPasswordDialog(context, role: ApiRole.cafeteria),
            ),
            IconButton(
              tooltip: 'تسجيل الخروج',
              onPressed: _logout,
              icon: const Icon(Icons.logout),
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.green.shade200,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            tabs: const [
              Tab(icon: Icon(Icons.restaurant_menu), text: 'المنيو والطلبات'),
              Tab(icon: Icon(Icons.qr_code_scanner), text: 'ماسح الـ QR'),
              Tab(icon: Icon(Icons.attach_money), text: 'الدخل الأسبوعي'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (_store.connectionError != null)
              MaterialBanner(
                backgroundColor: Colors.red.shade50,
                leading: Icon(Icons.wifi_off, color: Colors.red.shade700),
                content: Text(_store.connectionError!),
                actions: [
                  TextButton(
                    onPressed: _store.refresh,
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            Expanded(
              child: !_store.loaded
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildOrdersAndMenuManagement(), // 1. المنيو والطلبات
                        _buildQRScanner(), // 2. ماسح الـ QR
                        _buildRevenueDashboard(), // 3. الدخل الأسبوعي
                      ],
                    ),
            ),
          ],
        ),
        floatingActionButton: AnimatedBuilder(
          animation: _tabController,
          builder: (context, child) {
            return _tabController.index == 0
                ? FloatingActionButton(
                    backgroundColor: Colors.green.shade900,
                    child: const Icon(Icons.add, color: Colors.white),
                    onPressed: () => _showAddMealDialog(context),
                  )
                : const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  // حالة الكافيتريا كما تظهر للطلاب (تلقائي / مفتوحة / مزدحمة / مغلقة)
  Widget _buildCafeteriaStatusMenu() {
    final info = _store.cafeteria;
    if (info == null) return const SizedBox.shrink();
    const labels = {
      CafeteriaStatus.open: 'مفتوحة',
      CafeteriaStatus.busy: 'مزدحمة',
      CafeteriaStatus.closed: 'مغلقة',
    };
    return PopupMenuButton<CafeteriaStatus?>(
      tooltip: 'حالة الكافيتريا للطلاب',
      icon: const Icon(Icons.storefront, color: Colors.white),
      onSelected: (s) async => _show(await _store.setCafeteriaStatus(s)),
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Text(
            'الحالة الحالية: ${labels[info.status]}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(
          value: null,
          checked: info.manualStatus == null,
          child: const Text('تلقائي (حسب الدوام)'),
        ),
        for (final s in CafeteriaStatus.values)
          CheckedPopupMenuItem(
            value: s,
            checked: info.manualStatus == s,
            child: Text(labels[s]!),
          ),
      ],
    );
  }

  // نافذة إضافة وجبة جديدة
  void _showAddMealDialog(BuildContext context, {MenuItemModel? item}) {
    final TextEditingController nameController = TextEditingController(
      text: item?.name,
    );
    final TextEditingController priceController = TextEditingController(
      text: item?.price,
    );
    final TextEditingController timeController = TextEditingController(
      text: '${item?.prepMinutes ?? 5}',
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            item == null ? 'إضافة وجبة جديدة للمنيو' : 'تعديل الوجبة',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'اسم الوجبة'),
              ),
              TextField(
                controller: priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'السعر (د.ع)'),
              ),
              TextField(
                controller: timeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'وقت التحضير بالدقائق (مثال: 5)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade900,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final price = int.tryParse(priceController.text.trim());
                final prep = int.tryParse(timeController.text.trim());
                if (nameController.text.trim().isEmpty ||
                    price == null ||
                    price < 0 ||
                    price > 1000000 ||
                    prep == null ||
                    prep < 0 ||
                    prep > 120) {
                  _show(
                    const ActionResult.failure(
                      'أدخل اسم الوجبة وسعراً صحيحاً ووقت تحضير من 0 إلى 120 دقيقة',
                    ),
                  );
                  return;
                }
                Navigator.pop(context);
                _show(
                  await (item == null
                      ? _store.addMenuItem(nameController.text, price, prep)
                      : _store.editMenuItem(
                          item,
                          nameController.text,
                          price,
                          prep,
                        )),
                );
              },
              child: Text(item == null ? 'إضافة' : 'حفظ'),
            ),
          ],
        );
      },
    );
  }

  // 1. إدارة الطلبات والمنيو
  Widget _buildOrdersAndMenuManagement() {
    final cafeteriaOrders = _store.orders
        .where(
          (o) =>
              (_statusFilter == 'all' || o.status == _statusFilter) &&
              '${o.id} ${o.studentName} ${o.details}'.toLowerCase().contains(
                _query.toLowerCase(),
              ),
        )
        .toList();

    // ترتيب حسب وقت الاستلام، والطالب الذي وصل يظهر أولاً
    int byPickup(OrderItem a, OrderItem b) {
      if (_arrivedFirst && a.studentArrived != b.studentArrived) {
        return a.studentArrived ? -1 : 1;
      }
      return (a.pickupTime ?? a.date).compareTo(b.pickupTime ?? b.date);
    }

    final newOrders =
        cafeteriaOrders.where((o) => o.status == OrderStatus.received).toList()
          ..sort(byPickup);
    final preparingOrders =
        cafeteriaOrders.where((o) => o.status == OrderStatus.preparing).toList()
          ..sort(byPickup);
    final readyOrders =
        cafeteriaOrders.where((o) => o.status == OrderStatus.ready).toList()
          ..sort(byPickup);
    final completedOrders = cafeteriaOrders
        .where((o) => o.status == OrderStatus.delivered)
        .toList();
    final closedOrders = cafeteriaOrders
        .where(
          (o) =>
              o.status == OrderStatus.cancelled ||
              o.status == OrderStatus.rejected,
        )
        .toList();

    return Column(
      children: [
        Container(
          height: 380,
          color: Colors.green.shade50,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'ابحث برقم الطلب أو اسم الطالب أو الوجبة',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => _query = value.trim()),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _statusFilter,
                        items: [
                          const DropdownMenuItem(
                            value: 'all',
                            child: Text('كل الحالات'),
                          ),
                          for (final entry in OrderStatus.studentLabels.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _statusFilter = value ?? 'all'),
                      ),
                    ),
                    IconButton(
                      tooltip: _arrivedFirst
                          ? 'الترتيب بوقت الاستلام'
                          : 'إظهار الطلاب الواصلين أولًا',
                      icon: Icon(
                        _arrivedFirst ? Icons.directions_walk : Icons.schedule,
                      ),
                      onPressed: () =>
                          setState(() => _arrivedFirst = !_arrivedFirst),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(
                  'حالة الطلبات الحية:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    if (newOrders.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '🔴 طلب جديد:',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      ...newOrders.map(
                        (order) => _buildOrderCard(
                          order,
                          'بدء التجهيز',
                          OrderStatus.preparing,
                          Colors.orange,
                        ),
                      ),
                    ],
                    if (preparingOrders.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '🟠 جاري التجهيز:',
                          style: TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      ...preparingOrders.map(
                        (order) => _buildOrderCard(
                          order,
                          'جاهز للاستلام',
                          OrderStatus.ready,
                          Colors.blue,
                        ),
                      ),
                    ],
                    if (readyOrders.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '🔵 جاهز للاستلام (امسح QR الطالب أو سلّم يدوياً):',
                          style: TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      ...readyOrders.map(
                        (order) => _buildOrderCard(
                          order,
                          'تم التسليم',
                          OrderStatus.delivered,
                          Colors.green,
                        ),
                      ),
                    ],
                    if (completedOrders.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '🟢 تم الاستلام (آخر 24 ساعة):',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      ...completedOrders.map(
                        (order) => Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          child: ListTile(
                            title: Text('#${order.id} - ${order.studentName}'),
                            subtitle: Text(
                              '${order.details}\nتم التسليم | ${order.price.toStringAsFixed(0)} د.ع',
                            ),
                            trailing: const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                            ),
                          ),
                        ),
                      ),
                    ],
                    for (final order in closedOrders)
                      Card(
                        child: ListTile(
                          title: Text(
                            '#${order.id} - ${OrderStatus.studentLabels[order.status]}',
                          ),
                          subtitle: Text(order.closureReason ?? ''),
                          trailing: const Icon(Icons.cancel_outlined),
                        ),
                      ),
                    if (cafeteriaOrders.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20.0),
                          child: Text('لا توجد طلبات مسجلة حالياً'),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 2),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _store.menu.length,
            itemBuilder: (context, index) {
              final item = _store.menu[index];
              return Card(
                child: ListTile(
                  leading: Tooltip(
                    message: 'رفع / تغيير الصورة',
                    child: InkWell(
                      onTap: () => _editImage(item),
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        children: [
                          MenuItemImage(item: item, size: 48),
                          const Positioned(
                            bottom: 0,
                            left: 0,
                            child: CircleAvatar(
                              radius: 9,
                              backgroundColor: Colors.white,
                              child: Icon(
                                Icons.camera_alt,
                                size: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  title: Text(
                    item.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: item.isAvailable ? Colors.black87 : Colors.grey,
                    ),
                  ),
                  subtitle: Text(
                    'السعر: ${item.price} د.ع | الوقت: ${item.preptime}'
                    '${item.averageRating == null ? '' : ' | ⭐ ${item.averageRating!.toStringAsFixed(1)}'}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: item.isAvailable,
                        activeThumbColor: Colors.green.shade900,
                        onChanged: (val) async =>
                            _show(await _store.setAvailable(item, val)),
                      ),
                      IconButton(
                        tooltip: 'تعديل الوجبة',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () =>
                            _showAddMealDialog(context, item: item),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async =>
                            _show(await _store.deleteMenuItem(item)),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildOrderCard(
    OrderItem order,
    String buttonText,
    String nextStatus,
    Color buttonColor,
  ) {
    final overdue =
        order.pickupTime != null &&
        DateTime.now().isAfter(order.pickupTime!) &&
        OrderStatus.isActive(order.status);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      color: order.studentArrived ? Colors.amber.shade50 : null,
      child: ListTile(
        title: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (overdue)
              const Chip(
                label: Text('متأخر عن الاستلام'),
                avatar: Icon(Icons.schedule, size: 16, color: Colors.red),
              ),
            Text(
              '#${order.id} - ${order.studentName}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (order.studentArrived)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.shade700,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '🚶 الطالب وصل',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          '${order.details}\n'
          'وقت الطلب: ${order.time}'
          '${order.pickupTime == null ? '' : ' | الاستلام: ${formatTime(order.pickupTime!)}'}'
          ' | ${order.price.toStringAsFixed(0)} د.ع | ${order.paymentMethod}',
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: buttonColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () async =>
                  _show(await _store.setOrderStatus(order, nextStatus)),
              child: Text(buttonText),
            ),
            if (order.status == OrderStatus.received)
              PopupMenuButton<String>(
                tooltip: 'إجراءات الطلب',
                onSelected: (_) => _reject(order),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'reject',
                    child: Text('رفض الطلب'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // 2. ماسح الـ QR (محتوى الرمز = رقم الطلب)
  Widget _buildQRScanner() {
    return MobileScanner(
      onDetect: (capture) async {
        for (final barcode in capture.barcodes) {
          final String? code = barcode.rawValue?.trim();
          if (code == null || code.isEmpty) continue;

          // تجاهل نفس الرمز إذا قُرئ مرة أخرى خلال 3 ثوانٍ
          final now = DateTime.now();
          if (code == _lastScanned &&
              now.difference(_lastScanTime).inSeconds < 3) {
            return;
          }
          _lastScanned = code;
          _lastScanTime = now;

          _show(await _store.scan(code));
          return;
        }
      },
    );
  }

  // 3. واجهة الدخل الأسبوعي
  Widget _buildRevenueDashboard() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          Card(
            color: Colors.green.shade900,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  const Text(
                    'إجمالي الدخل المالي الأسبوعي:',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  Text(
                    '${_store.weeklyRevenue} د.ع',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('عدد الطلبات المسلّمة هذا الأسبوع: ${_store.weeklyOrders}'),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ملخص اليوم',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  Text(
                    'الطلبات: ${_store.dailySummary['orders'] ?? 0} • المسلّمة: ${_store.dailySummary['delivered_orders'] ?? 0}',
                  ),
                  Text(
                    'مبيعات الطلبات المسلّمة: ${_store.dailySummary['sales'] ?? 0} د.ع',
                  ),
                  Text(
                    'الملغاة والمرفوضة: ${_store.dailySummary['closed_orders'] ?? 0}',
                  ),
                  const Divider(),
                  const Text('الأصناف الأكثر طلبًا اليوم'),
                  for (final item
                      in (_store.dailySummary['top_items'] as List? ?? []))
                    Text('${item['name']} ×${item['quantity']}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
