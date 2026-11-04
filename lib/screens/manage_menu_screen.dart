import 'package:flutter/material.dart';
import '../models/order_model.dart';

class ManageMenuScreen extends StatefulWidget {
  const ManageMenuScreen({super.key});

  @override
  State<ManageMenuScreen> createState() => _ManageMenuScreenState();
}

class _ManageMenuScreenState extends State<ManageMenuScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'إدارة قائمة الطعام - الوجبات',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green.shade900,
        centerTitle: true,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: SharedData.menuitems.length,
        itemBuilder: (context, index) {
          final item = SharedData.menuitems[index];
          return Card(
            elevation: 3,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              title: Text(
                item.name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  // إذا كانت الوجبة منتهية، يتغير لون النص إلى الرمادي الباهت
                  color: item.isAvailable ? Colors.black87 : Colors.grey,
                ),
              ),
              subtitle: Text('السعر: ${item.price} د.ع | الوقت: ${item.preptime}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // نص يوضح الحالة الحالية
                  Text(
                    item.isAvailable ? 'متوفر' : 'منتهي',
                    style: TextStyle(
                      color: item.isAvailable ? Colors.green.shade900 : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // مفتاح تبديل لتغيير حالة التوفر مباشرة
                  Switch(
                    value: item.isAvailable, 
                    activeColor: Colors.green.shade900,
                    onChanged: (bool value) {
                      setState(() {
                        item.isAvailable = value;
                      });
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}