import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../constants/app_colors.dart';
import '../models/order_model.dart';
import 'analysis_screen.dart';
import 'manage_menu_screen.dart';
import '../QR/qr_scanner_screen.dart';

class DashboardScreen extends StatefulWidget {
  final String cafeteriaName;

  const DashboardScreen({super.key, required this.cafeteriaName});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _orderCheckTimer;
  int _lastOrdersCount = 0;

  @override
  void initState() {
    super.initState();
    _checkNewOrdersLoop();
  }

  void _checkNewOrdersLoop() {
    _orderCheckTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final activeOrders = SharedData.orders
          .where((o) => _isMatching(o.cafeteriaName))
          .toList();

      if (activeOrders.length > _lastOrdersCount) {
        // تشغيل صوت تنبيه عالي عند وصول طلب جديد
        _playAlertSound();
      }
      _lastOrdersCount = activeOrders.length;
      if (mounted) setState(() {});
    });
  }

  Future<void> _playAlertSound() async {
    try {
      // إصدار تنبيه صوتي افتراضي أو نغمة النظام
      await _audioPlayer.play(UrlSource('https://assets.mixkit.co/active_storage/sfx/2869/2869-preview.mp3'));
    } catch (e) {
      debugPrint("خطأ في تشغيل الصوت: $e");
    }
  }

  @override
  void dispose() {
    _orderCheckTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  bool _isMatching(String name) {
    return widget.cafeteriaName.trim().toLowerCase().contains(name.trim().toLowerCase()) ||
        name.trim().toLowerCase().contains(widget.cafeteriaName.trim().toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final activeOrders = SharedData.orders.where((o) => _isMatching(o.cafeteriaName)).toList();

    return Scaffold(
      backgroundColor: AppColors.bgCream,
      appBar: AppBar(
        title: Text('لوحة تحكم: ${widget.cafeteriaName}', style: const TextStyle(color: Colors.white, fontSize: 14)),
        backgroundColor: AppColors.darkGreen,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            tooltip: 'قراءة باركود الطالب',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const QRScannerScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.restaurant_menu_rounded),
            tooltip: 'إدارة المنيو',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ManageMenuScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.analytics_rounded),
            tooltip: 'تقارير الدخل',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => CafeteriaAnalyticsScreen(cafeteriaName: widget.cafeteriaName)),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '📦 الطلبات الواردة وقيد التجهيز (تنبيه صوتي مفعل)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.darkGreen),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.darkGreen, foregroundColor: Colors.white),
                  onPressed: () => setState(() {}),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('تحديث'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: activeOrders.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
                          SizedBox(height: 8),
                          Text('لا توجد طلبات جديدة حالياً.. بانتظار الطلبات', style: TextStyle(color: Colors.grey, fontSize: 13)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: activeOrders.length,
                      itemBuilder: (context, index) {
                        final order = activeOrders[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(14.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(order.id, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkGreen)),
                                    Text('${order.price.toStringAsFixed(0)} د.ع', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text('👤 الطالب: ${order.studentName}', style: const TextStyle(fontSize: 13, color: Colors.black87)),
                                Text('🛒 الوجبة: ${order.details}', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                                Text('⏱️ التجهيز: ${order.prepTime}', style: const TextStyle(fontSize: 12, color: Colors.orange)),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: order.status == 'ready' ? Colors.green : Colors.orange,
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size(100, 32),
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          if (order.status == 'new') {
                                            order.status = 'ready';
                                          } else {
                                            SharedData.orders.remove(order);
                                          }
                                        });
                                      },
                                      child: Text(order.status == 'new' ? 'جاهز للاستلام' : 'تم التسليم ✔️', style: const TextStyle(fontSize: 12)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}