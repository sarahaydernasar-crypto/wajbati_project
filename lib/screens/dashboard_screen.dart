import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/order_model.dart';

class DashboardScreen extends StatefulWidget {
  final String cafeteriaName;

  const DashboardScreen({super.key, required this.cafeteriaName});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'إدارة: ${widget.cafeteriaName}',
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green.shade900,
        centerTitle: true,
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
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOrdersAndMenuManagement(), // 1. المنيو والطلبات (مع زر الحذف والإضافة)
          _buildQRScanner(),               // 2. ماسح الـ QR الحقيقي
          _buildRevenueDashboard(),        // 3. الدخل الأسبوعي
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
    );
  }

  // نافذة إضافة وجبة جديدة
  void _showAddMealDialog(BuildContext context) {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController priceController = TextEditingController();
    final TextEditingController timeController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('إضافة وجبة جديدة للمنيو'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'اسم الوجبة')),
              TextField(controller: priceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر (د.ع)')),
              TextField(controller: timeController, decoration: const InputDecoration(labelText: 'وقت التحضير (مثال: 5 دقائق)')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade900, foregroundColor: Colors.white),
              onPressed: () {
                if (nameController.text.isNotEmpty && priceController.text.isNotEmpty) {
                  setState(() {
                    SharedData.addMenuItem(nameController.text, priceController.text, timeController.text.isEmpty ? '5 دقائق' : timeController.text);
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text('إضافة'),
            ),
          ],
        );
      },
    );
  }

  // 1. إدارة الطلبات والمنيو (مع خيار الحذف والتحكم)
  Widget _buildOrdersAndMenuManagement() {
    final cafeteriaOrders = SharedData.orders.where((o) => o.cafeteriaName == widget.cafeteriaName).toList();

    final newOrders = cafeteriaOrders.where((o) => o.status == 'طلب جديد').toList();
    final preparingOrders = cafeteriaOrders.where((o) => o.status == 'جاري التجهيز').toList();
    final completedOrders = cafeteriaOrders.where((o) => o.status == 'تم الاستلام').toList();

    return Column(
      children: [
        Container(
          height: 220,
          color: Colors.green.shade50,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text('حالة الطلبات الحية:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              Expanded(
                child: ListView(
                  children: [
                    if (newOrders.isNotEmpty) ...[
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('🔴 طلب جديد:', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                      ...newOrders.map((order) => _buildOrderCard(order, 'نقل إلى جاري التجهيز', 'جاري التجهيز', Colors.orange)),
                    ],
                    if (preparingOrders.isNotEmpty) ...[
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('🟠 جاري التجهيز:', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
                      ...preparingOrders.map((order) => _buildOrderCard(order, 'تم الاستلام', 'تم الاستلام', Colors.green)),
                    ],
                    if (completedOrders.isNotEmpty) ...[
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('🟢 تم الاستلام:', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
                      ...completedOrders.map((order) => Card(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        child: ListTile(
                          title: Text('${order.studentName} - ${order.details}'),
                          subtitle: Text('تم التسليم | السعر: ${order.price} د.ع'),
                          trailing: const Icon(Icons.check_circle, color: Colors.green),
                        ),
                      )),
                    ],
                    if (cafeteriaOrders.isEmpty)
                      const Center(child: Padding(padding: EdgeInsets.all(20.0), child: Text('لا توجد طلبات مسجلة حالياً'))),
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
            itemCount: SharedData.menuitems.length,
            itemBuilder: (context, index) {
              final item = SharedData.menuitems[index];
              return Card(
                child: ListTile(
                  title: Text(item.name, style: TextStyle(fontWeight: FontWeight.bold, color: item.isAvailable ? Colors.black87 : Colors.grey)),
                  subtitle: Text('السعر: ${item.price} د.ع | الوقت: ${item.preptime}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: item.isAvailable,
                        activeColor: Colors.green.shade900,
                        onChanged: (val) {
                          setState(() {
                            item.isAvailable = val;
                          });
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          setState(() {
                            SharedData.menuitems.removeAt(index);
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('تم حذف الوجبة من المنيو بنجاح!')),
                          );
                        },
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

  Widget _buildOrderCard(OrderItem order, String buttonText, String nextStatus, Color buttonColor) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: ListTile(
        title: Text('${order.studentName} (${order.details})'),
        subtitle: Text('الوقت: ${order.time} | السعر: ${order.price} د.ع'),
        trailing: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: buttonColor, foregroundColor: Colors.white),
          onPressed: () {
            setState(() {
              order.status = nextStatus;
            });
          },
          child: Text(buttonText),
        ),
      ),
    );
  }

  // 2. ماسح الـ QR الحقيقي
  Widget _buildQRScanner() {
    return MobileScanner(
      onDetect: (capture) {
        final List<Barcode> barcodes = capture.barcodes;
        for (final barcode in barcodes) {
          final String? orderId = barcode.rawValue;
          if (orderId != null) {
            final orderIndex = SharedData.orders.indexWhere((o) => o.id == orderId);
            if (orderIndex != -1) {
              setState(() {
                SharedData.orders[orderIndex].status = 'تم الاستلام';
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('تم تأكيد استلام الطلب رقم ($orderId) بنجاح!'),
                  backgroundColor: Colors.green,
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('الرمز ($orderId) غير مسجل أو غير صالح!'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        }
      },
    );
  }

  // 3. واجهة الدخل الأسبوعي
  Widget _buildRevenueDashboard() {
    final double weeklyTotal = SharedData.getWeeklyRevenue(widget.cafeteriaName);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Card(
            color: Colors.green.shade900,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('إجمالي الدخل المالي الأسبوعي:', style: TextStyle(color: Colors.white, fontSize: 16)),
                  Text('$weeklyTotal د.ع', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}