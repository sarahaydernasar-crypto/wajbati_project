import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/order_model.dart';
import 'login_screen.dart';

class StudentOrderScreen extends StatefulWidget {
  const StudentOrderScreen({super.key});

  @override
  State<StudentOrderScreen> createState() => _StudentOrderScreenState();
}

class _StudentOrderScreenState extends State<StudentOrderScreen> {
  final TextEditingController _nameController = TextEditingController();
  String? selectedCafeteria;
  String? selectedMeal;
  double mealPrice = 3000.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgCream,
      appBar: AppBar(
        title: const Text('واجهة طلب الطالب - وجباتي', style: TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: AppColors.darkGreen,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white),
            tooltip: 'دخول مشرف الكافيتريا',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CafeteriaLoginScreen()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('اسم الطالب الثلاثي:', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkGreen)),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: 'أدخل اسمك الكريم هنا',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 20),
            const Text('اختر الكافيتريا:', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkGreen)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: selectedCafeteria,
              hint: const Text('اختر الكافيتريا المستهدفة'),
              items: SharedData.cafeteriasWithCodes.keys.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (val) => setState(() => selectedCafeteria = val),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 20),
            const Text('اختر الوجبة من المنيو:', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkGreen)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: selectedMeal,
              hint: const Text('اختر وجبتك المفضلة'),
              items: SharedData.menuitems.map((m) => DropdownMenuItem(value: m.name, child: Text('${m.name} (${m.price} د.ع)'))).toList(),
              onChanged: (val) {
                setState(() {
                  selectedMeal = val;
                  final matching = SharedData.menuitems.firstWhere((m) => m.name == val);
                  mealPrice = double.tryParse(matching.price) ?? 3000.0;
                });
              },
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
            const Spacer(),
            Center(
              child: SizedBox(
                width: 260,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () {
                    if (_nameController.text.trim().isEmpty || selectedCafeteria == null || selectedMeal == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('الرجاء إدخال الاسم، اختيار الكافيتريا والوجبة أولاً!')),
                      );
                      return;
                    }

                    final newOrder = OrderItem(
                      id: 'ORD-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
                      studentName: _nameController.text.trim(),
                      details: selectedMeal!,
                      cafeteriaName: selectedCafeteria!,
                      prepTime: '10 دقائق',
                      status: 'new',
                      time: TimeOfDay.now().format(context),
                      price: mealPrice,
                    );

                    SharedData.orders.add(newOrder);

                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('تم بنجاح 🎉', style: TextStyle(color: AppColors.darkGreen, fontWeight: FontWeight.bold)),
                        content: Text('تم إرسال طلبك إلى (${selectedCafeteria}) بنجاح وتم تفعيل التنبيه الصوتي لدى الكافيتريا!'),
                        actions: [
                          TextButton(
                            onPressed: () {
                              _nameController.clear();
                              setState(() {
                                selectedCafeteria = null;
                                selectedMeal = null;
                              });
                              Navigator.pop(context);
                            },
                            child: const Text('حسناً'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('إرسال الطلب 🚀', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}