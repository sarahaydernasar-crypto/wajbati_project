import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/order_model.dart';
import 'dashboard_screen.dart';

class CafeteriaLoginScreen extends StatefulWidget {
  const CafeteriaLoginScreen({super.key});

  @override
  State<CafeteriaLoginScreen> createState() => _CafeteriaLoginScreenState();
}

class _CafeteriaLoginScreenState extends State<CafeteriaLoginScreen> {
  final Map<String, TextEditingController> _codeControllers = {
    'كافيتريا علوم حاسوب': TextEditingController(),
    'كافيتريا العلوم التطبيقية': TextEditingController(),
    'كافيتريا كهرومكانيك': TextEditingController(),
    'كافيتريا طب حياتي': TextEditingController(),
    'كافيتريا معماري': TextEditingController(),
  };

  @override
  void dispose() {
    for (var controller in _codeControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgCream,
      appBar: AppBar(
        title: const Text('تسجيل دخول مشرف الكافيتريا (الرمز السري)', style: TextStyle(color: Colors.white, fontSize: 14)),
        backgroundColor: AppColors.darkGreen,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'الرجاء إدخال الرمز التعريفي (8 خانات) الخاص بكافيتريتك للدخول:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.darkGreen),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: SharedData.cafeteriasWithCodes.keys.map((cafeteriaName) {
                  final correctCode = SharedData.cafeteriasWithCodes[cafeteriaName];
                  final controller = _codeControllers[cafeteriaName]!;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.store_rounded, color: AppColors.darkGreen, size: 24),
                              const SizedBox(width: 8),
                              Text(cafeteriaName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.darkGreen)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: controller,
                            maxLength: 8,
                            decoration: InputDecoration(
                              labelText: 'أدخل الرمز السري (8 خانات)',
                              hintText: 'مثال: $correctCode',
                              counterText: '',
                              filled: true,
                              fillColor: Colors.grey[100],
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.darkGreen,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(120, 36),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () {
                                String enteredCode = controller.text.trim();
                                if (enteredCode == correctCode) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => DashboardScreen(cafeteriaName: cafeteriaName),
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('الرمز السري غير صحيح! يجيب أن يكون 8 خانات مطابقة.'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              },
                              child: const Text('دخول لوحة التحكم', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}