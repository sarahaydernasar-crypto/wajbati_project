import 'package:flutter/material.dart';
import '../../models/order_model.dart';
import '../dashboard_screen.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  String? _selectedCafeteria;
  final TextEditingController _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _loginAdmin() {
    if (_selectedCafeteria == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرجاء اختيار الكافيتريا أولاً'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final enteredCode = _codeController.text.trim();
    final correctCode = SharedData.cafeteriasWithCodes[_selectedCafeteria];

    if (enteredCode == correctCode) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DashboardScreen(cafeteriaName: _selectedCafeteria!),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرمز السري غير صحيح! يجب أن يكون 8 خانات مطابقة'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'تسجيل دخول مسؤول الكافيتريا',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green.shade900,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: _selectedCafeteria,
              hint: const Text('اختر الكافيتريا الخاصة بك'),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.storefront),
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
                });
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _codeController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'الرمز السري للكافيتريا (8 خانات)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade900,
                  foregroundColor: Colors.white,
                ),
                onPressed: _loginAdmin,
                child: const Text('دخول لوحة التحكم', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}