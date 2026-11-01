import 'package:flutter/material.dart';
import 'constants/app_colors.dart';
import 'screens/student_order_screen.dart';

void main() {
  runApp(const WajbatiApp());
}

class WajbatiApp extends StatelessWidget {
  const WajbatiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'وجباتي - نظام الكافيتريا الجامعي',
      theme: ThemeData(
        primaryColor: AppColors.darkGreen,
        scaffoldBackgroundColor: AppColors.bgCream,
        fontFamily: 'Segoe UI',
      ),
      home: const StudentOrderScreen(),
    );
  }
}