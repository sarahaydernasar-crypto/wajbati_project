import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/order_model.dart';

class CafeteriaAnalyticsScreen extends StatelessWidget {
  final String cafeteriaName;

  const CafeteriaAnalyticsScreen({super.key, required this.cafeteriaName});

  bool _isMatching(String name) {
    return cafeteriaName.trim().toLowerCase().contains(name.trim().toLowerCase()) ||
        name.trim().toLowerCase().contains(cafeteriaName.trim().toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final cafeteriaOrders = SharedData.orders.where((o) => _isMatching(o.cafeteriaName)).toList();

    double totalRevenue = 0;
    for (var order in cafeteriaOrders) {
      totalRevenue += order.price;
    }

    return Scaffold(
      backgroundColor: AppColors.bgCream,
      appBar: AppBar(
        title: Text('تقارير الدخل والأرباح: $cafeteriaName', style: const TextStyle(color: Colors.white, fontSize: 15)),
        backgroundColor: AppColors.darkGreen,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF2E7D32).withOpacity(0.3), width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.payments_rounded, color: Color(0xFF2E7D32), size: 28),
                        const SizedBox(height: 10),
                        const Text('إجمالي الدخل المالي', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('${totalRevenue.toStringAsFixed(0)} د.ع', style: const TextStyle(color: Color(0xFF2E7D32), fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF388E3C).withOpacity(0.3), width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.assessment_rounded, color: Color(0xFF388E3C), size: 28),
                        const SizedBox(height: 10),
                        const Text('الطلبات المسجلة', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('${cafeteriaOrders.length} طلب', style: const TextStyle(color: Color(0xFF388E3C), fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              '📊 تفاصيل حركة المبيعات المسجلة',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.darkGreen),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: cafeteriaOrders.isEmpty
                  ? Center(
                      child: Text(
                        'لا توجد مبيعات مسجلة لـ ($cafeteriaName) حتى الآن.',
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      itemCount: cafeteriaOrders.length,
                      itemBuilder: (context, index) {
                        final order = cafeteriaOrders[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.darkGreen.withOpacity(0.2)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(order.id, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkGreen, fontSize: 13)),
                                  const SizedBox(height: 2),
                                  Text('👤 ${order.studentName}', style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
                                ],
                              ),
                              Text(order.details, style: const TextStyle(fontSize: 12, color: Color(0xFF444444))),
                              Text('${order.price.toStringAsFixed(0)} د.ع', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkGreen, fontSize: 12)),
                            ],
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