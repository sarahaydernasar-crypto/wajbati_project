import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/order_model.dart';

class ManageMenuScreen extends StatefulWidget {
  const ManageMenuScreen({super.key});

  @override
  State<ManageMenuScreen> createState() => _ManageMenuScreenState();
}

class _ManageMenuScreenState extends State<ManageMenuScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();

  void _addNewItem() {
    if (_nameController.text.isEmpty || _priceController.text.isEmpty) return;
    setState(() {
      SharedData.menuitems.add(
        MenuItemModel(
          name: _nameController.text,
          price: _priceController.text,
          preptime: _timeController.text.isEmpty ? '5 دقائق' : _timeController.text,
        ),
      );
    });
    _nameController.clear();
    _priceController.clear();
    _timeController.clear();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgCream,
      appBar: AppBar(
        title: const Text('إدارة قائمة الطعام (المنيو)', style: TextStyle(color: Colors.white, fontSize: 15)),
        backgroundColor: AppColors.darkGreen,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView.builder(
          itemCount: SharedData.menuitems.length,
          itemBuilder: (context, index) {
            final item = SharedData.menuitems[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('السعر: ${item.price} د.ع | التجهيز: ${item.preptime}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    setState(() {
                      SharedData.menuitems.removeAt(index);
                    });
                  },
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.darkGreen,
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('إضافة وجبة جديدة'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'اسم الوجبة')),
                  TextField(controller: _priceController, decoration: const InputDecoration(labelText: 'السعر (د.ع)')),
                  TextField(controller: _timeController, decoration: const InputDecoration(labelText: 'مدة التجهيز (مثال: 10 دقائق)')),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.darkGreen, foregroundColor: Colors.white),
                  onPressed: _addNewItem,
                  child: const Text('إضافة'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}