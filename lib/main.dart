import 'package:flutter/material.dart';
import 'screens/student_order_screen.dart'; // استيراد واجهة الطالب الرئيسية

void main() {
  runApp(const WajbatiApp());
}

class WajbatiApp extends StatelessWidget {
  const WajbatiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'وجباتي - Wajbati',
      theme: ThemeData(
        primarySwatch: Colors.green,
        useMaterial3: true,
      ),
      // تعيين واجهة الطالب لتكون هي الشاشة الافتتاحية عند فتح التطبيق
      home: const StudentOrderScreen(),
    );
  }
}