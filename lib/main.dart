import 'package:flutter/material.dart';

import 'constants/app_colors.dart';
import 'screens/student/student_auth_screens.dart'; // واجهة الطالب: تسجيل الدخول / إنشاء حساب
import 'screens/student/student_store.dart';
import 'screens/student_order_screen.dart';
import 'services/api_client.dart';
import 'services/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // عنوان السيرفر والجلسة المحفوظة
  await ApiClient.instance.init();
  await PushService.instance.init();
  await StudentStore.instance.init();
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.darkGreen,
          primary: AppColors.darkGreen,
        ),
        useMaterial3: true,
      ),
      // التطبيق عربي: اتجاه من اليمين لليسار لكل الشاشات
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      // إذا كان الطالب مسجّل دخول مسبقاً يفتح التطبيق مباشرة على الشاشة الرئيسية
      home: StudentStore.instance.isLoggedIn
          ? const StudentOrderScreen()
          : const StudentLoginScreen(),
    );
  }
}
