import 'package:flutter/material.dart';
import '../models/order_model.dart';

class StudentOrderScreen extends StatefulWidget {
  const StudentOrderScreen({super.key});

  @override
  State<StudentOrderScreen> createState() => _StudentOrderScreenState();
}

class _StudentOrderScreenState extends State<StudentOrderScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  String? _selectedCafeteria;
  final Set<String> _selectedItems = {};

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          'وجباتي - طلب الوجبات للطالب',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green.shade900,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // بطاقة إدخال بيانات الطالب واختيار الكافيتريا
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'اسم الطالب',
                        prefixIcon: Icon(Icons.person, color: Colors.green.shade900),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'رقم الهاتف',
                        prefixIcon: Icon(Icons.phone, color: Colors.green.shade900),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedCafeteria,
                      hint: const Text('اختر الكافيتريا'),
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.storefront, color: Colors.green.shade900),
                        border: const OutlineInputBorder(),
                      ),
                      items: SharedData.cafeteriasWithCodes.keys.map((cafeteria) {
                        return DropdownMenuItem(
                          value: cafeteria,
                          child: Text(cafeteria),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedCafeteria = val;
                          _selectedItems.clear();
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // زر إرسال الطلب في منتصف الصفحة
            SizedBox(
              width: 220,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade900,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  if (_nameController.text.isEmpty || _phoneController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('الرجاء إدخال اسم الطالب ورقم الهاتف أولاً')),
                    );
                    return;
                  }
                  if (_selectedCafeteria == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('الرجاء اختيار الكافيتريا')),
                    );
                    return;
                  }
                  if (_selectedItems.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('الرجاء اختيار وجبة واحدة على الأقل')),
                    );
                    return;
                  }

                  final newOrder = OrderItem(
                    id: DateTime.now().millisecondsSinceEpoch.toString().substring(8),
                    studentName: _nameController.text,
                    details: _selectedItems.join(', '),
                    cafeteriaName: _selectedCafeteria!,
                    prepTime: 'حسب الوجبات',
                    status: 'طلب جديد',
                    time: TimeOfDay.now().format(context),
                    price: 3000,
                    date: DateTime.now(), // تمت إضافة التاريخ هنا لحل الخطأ
                  );

                  SharedData.orders.add(newOrder);

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم إرسال الطلب بنجاح إلى الكافيتريا!')),
                  );

                  setState(() {
                    _selectedItems.clear();
                    _nameController.clear();
                    _phoneController.clear();
                  });
                },
                child: const Text(
                  'إرسال الطلب',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // قائمة الوجبات
            _selectedCafeteria == null
                ? Padding(
                    padding: const EdgeInsets.only(top: 40.0),
                    child: Text(
                      'يرجى اختيار الكافيتريا لعرض القائمة المتاحة',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 15),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: SharedData.menuitems.length,
                    itemBuilder: (context, index) {
                      final item = SharedData.menuitems[index];
                      final isSelected = _selectedItems.contains(item.name);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          title: Text(
                            item.name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: item.isAvailable ? Colors.black87 : Colors.grey,
                              decoration: item.isAvailable ? null : TextDecoration.lineThrough,
                            ),
                          ),
                          subtitle: Text('السعر: ${item.price} د.ع | الوقت: ${item.preptime}'),
                          trailing: item.isAvailable
                              ? FilterChip(
                                  label: Text(isSelected ? 'تم الاختيار' : 'اختيار'),
                                  selected: isSelected,
                                  selectedColor: Colors.green.shade100,
                                  checkmarkColor: Colors.green.shade900,
                                  labelStyle: TextStyle(
                                    color: isSelected ? Colors.green.shade900 : Colors.black87,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  onSelected: (bool selected) {
                                    setState(() {
                                      if (selected) {
                                        _selectedItems.add(item.name);
                                      } else {
                                        _selectedItems.remove(item.name);
                                      }
                                    });
                                  },
                                )
                              : Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'غير متوفر',
                                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                                  ),
                                ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}