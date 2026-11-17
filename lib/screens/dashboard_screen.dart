import '../localization/localized_widgets.dart';
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/order_model.dart';
import '../constants/app_colors.dart';
import '../widgets/app_feedback.dart';
import 'admin/orders_panel.dart';
import 'admin/menu_panel.dart';
import 'admin/reports_panel.dart';
import '../services/cafeteria_admin_store.dart';
import '../services/password_dialog.dart';
import '../services/api_client.dart';
import 'menu_item_editor_dialog.dart';
import 'student/student_store.dart' show ActionResult, CafeteriaStatus;

class DashboardScreen extends StatefulWidget {
  final String cafeteriaName;

  const DashboardScreen({super.key, required this.cafeteriaName});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _section = 0;
  final _store = CafeteriaAdminStore.instance;

  // لمنع تكرار قراءة نفس الرمز عشرات المرات بالثانية
  String? _lastScanned;
  DateTime _lastScanTime = DateTime(2000);

  // صوت تنبيه الطلبات الجديدة
  AudioPlayer? _player;
  StreamSubscription<List<OrderItem>>? _newOrdersSub;

  @override
  void initState() {
    super.initState();
    _newOrdersSub = _store.onNewOrders.listen(_onNewOrders);
  }

  @override
  void dispose() {
    _newOrdersSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _onNewOrders(List<OrderItem> fresh) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.red.shade700,
        content: LText(
          fresh.length == 1
              ? '🔔 طلب جديد #${fresh.first.id} من ${fresh.first.studentName}'
              : '🔔 ${fresh.length} طلبات جديدة',
        ),
      ),
    );
    if (!_store.soundEnabled) return;
    try {
      _player ??= AudioPlayer();
      await _player!.stop();
      await _player!.play(AssetSource('sounds/new_order.wav'));
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
              title: LText(
                'صورة "${item.name}"',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: LText(hasImage ? 'تغيير الصورة' : 'رفع صورة'),
              subtitle: const LText('JPG أو PNG، حتى 2 ميغابايت'),
              onTap: () => Navigator.pop(ctx, 'upload'),
            ),
            if (hasImage)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const LText('حذف الصورة'),
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
          content: LText(r.message),
          backgroundColor: r.ok ? Colors.green : Colors.red,
        ),
      );
  }

  Future<void> _reject(OrderItem order) async {
    final reason = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: LText('رفض الطلب #${order.id}'),
        content: LTextField(
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
            child: const LText('رجوع'),
          ),
          FilledButton(
            onPressed: () {
              if (reason.text.trim().length >= 3) {
                Navigator.pop(ctx, reason.text.trim());
              }
            },
            child: const LText('رفض وإبلاغ الطالب'),
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

  static const _labels = ['الطلبات', 'المنيو', 'ماسح QR', 'التقارير'];
  static const _icons = [
    Icons.receipt_long_outlined,
    Icons.restaurant_menu,
    Icons.qr_code_scanner,
    Icons.bar_chart_outlined,
  ];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _store,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;
        final panels = IndexedStack(
          index: _section,
          children: [
            OrdersPanel(
              orders: _store.orders,
              now: _store.cafeteria?.serverTime,
              onAdvance: (order, status) async =>
                  _show(await _store.setOrderStatus(order, status)),
              onReject: _reject,
            ),
            MenuPanel(
              items: _store.menu,
              onAdd: () => _showAddMealDialog(context),
              onEdit: (item) => _showAddMealDialog(context, item: item),
              onImage: _editImage,
              onDelete: (item) async =>
                  _show(await _store.deleteMenuItem(item)),
              onAvailability: (item, available) async =>
                  _show(await _store.setAvailable(item, available)),
            ),
            _section == 2 ? _buildQRScanner() : const SizedBox.shrink(),
            ReportsPanel(
              data: _store.report,
              period: _store.reportPeriod,
              loading: _store.reportLoading,
              error: _store.reportError,
              onSelect: _store.selectReport,
              onRetry: () => _store.loadReport(showLoading: true),
            ),
          ],
        );
        final content = Column(
          children: [
            if (_store.connectionError != null)
              MaterialBanner(
                backgroundColor: Colors.red.shade50,
                leading: const Icon(Icons.wifi_off),
                content: LText(_store.connectionError!),
                actions: [
                  TextButton(
                    onPressed: _store.refresh,
                    child: const LText('إعادة المحاولة'),
                  ),
                ],
              ),
            Expanded(
              child: !_store.loaded
                  ? const LoadingCards(label: 'جارٍ تجهيز لوحة الكافيتريا...')
                  : Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1360),
                        child: panels,
                      ),
                    ),
            ),
          ],
        );
        return Scaffold(
          backgroundColor: AppColors.bgCream,
          appBar: AppBar(
            backgroundColor: AppColors.darkGreen,
            foregroundColor: Colors.white,
            title: LText(
              widget.cafeteriaName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            actions: [
              const LanguageButton(),
              _buildCafeteriaStatusMenu(),
              PopupMenuButton<String>(
                tooltip: ('إعدادات الكافيتريا').tr(context),
                onSelected: (value) {
                  if (value == 'sound') _store.toggleSound();
                  if (value == 'password') {
                    showPasswordDialog(context, role: ApiRole.cafeteria);
                  }
                  if (value == 'logout') _logout();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'sound',
                    child: LText(
                      _store.soundEnabled
                          ? 'كتم صوت الطلبات'
                          : 'تشغيل صوت الطلبات',
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'password',
                    child: LText('تغيير الرمز السري'),
                  ),
                  const PopupMenuItem(
                    value: 'logout',
                    child: LText('تسجيل الخروج'),
                  ),
                ],
              ),
            ],
          ),
          body: wide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _section,
                      extended: constraints.maxWidth >= 1280,
                      backgroundColor: Colors.white,
                      indicatorColor: AppColors.lightGreen.withValues(
                        alpha: 0.12,
                      ),
                      onDestinationSelected: (index) =>
                          setState(() => _section = index),
                      destinations: [
                        for (var i = 0; i < _labels.length; i++)
                          NavigationRailDestination(
                            icon: Icon(_icons[i]),
                            label: LText(_labels[i]),
                          ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: content),
                  ],
                )
              : content,
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _section,
                  indicatorColor: AppColors.lightGreen.withValues(alpha: 0.12),
                  onDestinationSelected: (index) =>
                      setState(() => _section = index),
                  destinations: [
                    for (var i = 0; i < _labels.length; i++)
                      NavigationDestination(
                        icon: Icon(_icons[i]),
                        label: _labels[i].tr(context),
                      ),
                  ],
                ),
        );
      },
    ),
  );

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
      tooltip: ('حالة الكافيتريا للطلاب').tr(context),
      icon: const Icon(Icons.storefront, color: Colors.white),
      onSelected: (s) async => _show(await _store.setCafeteriaStatus(s)),
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: LText(
            'الحالة الحالية: ${labels[info.status]}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(
          value: null,
          checked: info.manualStatus == null,
          child: const LText('تلقائي (حسب الدوام)'),
        ),
        for (final s in CafeteriaStatus.values)
          CheckedPopupMenuItem(
            value: s,
            checked: info.manualStatus == s,
            child: LText(labels[s]!),
          ),
      ],
    );
  }

  Future<void> _showAddMealDialog(
    BuildContext context, {
    MenuItemModel? item,
  }) async {
    final result = await showDialog<ActionResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MenuItemEditorDialog(item: item),
    );
    if (result != null) _show(result);
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
}
