import '../../localization/localized_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../constants/app_colors.dart';
import '../../services/server_settings_dialog.dart';
import '../login/admin_login_screen.dart';
import '../student_order_screen.dart';
import '../platform_screen.dart';
import 'student_store.dart';
import 'student_widgets.dart';

// =================== تسجيل الدخول ===================
class StudentLoginScreen extends StatefulWidget {
  const StudentLoginScreen({super.key});

  @override
  State<StudentLoginScreen> createState() => _StudentLoginScreenState();
}

class _StudentLoginScreenState extends State<StudentLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final r = await StudentStore.instance.login(_phone.text, _password.text);
      if (!mounted) return;
      if (r.ok) {
        ScaffoldMessenger.of(context).clearSnackBars();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const StudentOrderScreen()),
        );
      } else {
        showResult(context, r);
      }
    } catch (_) {
      if (mounted) {
        showStudentMessage(
          context,
          'تعذّر الاتصال، تحقق من الإنترنت وحاول مجدداً.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'أهلاً بك في وجباتي',
      subtitle: 'اطلب وجبتك من كافيتريا كليتك واستلمها بدون انتظار',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LTextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: _input('رقم الهاتف', Icons.phone_iphone),
              validator: _validatePhone,
            ),
            const SizedBox(height: 14),
            LTextFormField(
              controller: _password,
              obscureText: _obscure,
              onFieldSubmitted: (_) => _submit(),
              decoration: _input('كلمة المرور', Icons.lock_outline).copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'أدخل كلمة المرور' : null,
            ),
            const SizedBox(height: 22),
            _PrimaryButton(
              label: 'تسجيل الدخول',
              loading: _loading,
              onPressed: _submit,
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const LText('ليس لديك حساب؟'),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const StudentRegisterScreen(),
                    ),
                  ),
                  child: const LText(
                    'أنشئ حساباً',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (!kReleaseMode)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const LText(
                  'حساب تجريبي: 07700000000 / 123456',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12),
                ),
              ),
            const Divider(height: 32),
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
              ),
              icon: const Icon(Icons.storefront, size: 18),
              label: const LText('دخول مسؤول الكافيتريا'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade700,
              ),
            ),
            const ServerSettingsButton(),
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlatformScreen()),
              ),
              icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
              label: const LText('إدارة المنصة'),
            ),
          ],
        ),
      ),
    );
  }
}

// =================== إنشاء حساب ===================
class StudentRegisterScreen extends StatefulWidget {
  const StudentRegisterScreen({super.key});

  @override
  State<StudentRegisterScreen> createState() => _StudentRegisterScreenState();
}

class _StudentRegisterScreenState extends State<StudentRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final r = await StudentStore.instance.register(
        name: _name.text,
        phone: _phone.text,
        password: _password.text,
      );
      if (!mounted) return;
      if (r.ok) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const StudentOrderScreen()),
          (_) => false,
        );
      }
      showResult(context, r);
    } catch (_) {
      if (mounted) {
        showStudentMessage(
          context,
          'تعذّر إنشاء الحساب، تحقق من الإنترنت وحاول مجدداً.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'إنشاء حساب طالب',
      subtitle: 'سجّل مرة واحدة واطلب من أي كافيتريا في الجامعة',
      showBack: true,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LTextFormField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: _input('الاسم الكامل', Icons.person_outline),
              validator: (v) => (v == null || v.trim().length < 3)
                  ? 'أدخل اسمك الكامل'
                  : null,
            ),
            const SizedBox(height: 14),
            LTextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: _input('رقم الهاتف', Icons.phone_iphone),
              validator: _validatePhone,
            ),
            const SizedBox(height: 14),
            LTextFormField(
              controller: _password,
              obscureText: true,
              textInputAction: TextInputAction.next,
              decoration: _input('كلمة المرور', Icons.lock_outline),
              validator: (v) => (v == null || v.length < 6)
                  ? 'كلمة المرور 6 أحرف على الأقل'
                  : null,
            ),
            const SizedBox(height: 14),
            LTextFormField(
              controller: _confirm,
              obscureText: true,
              onFieldSubmitted: (_) => _submit(),
              decoration: _input('تأكيد كلمة المرور', Icons.lock_reset),
              validator: (v) =>
                  v != _password.text ? 'كلمتا المرور غير متطابقتين' : null,
            ),
            const SizedBox(height: 22),
            _PrimaryButton(
              label: 'إنشاء الحساب',
              loading: _loading,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

// =================== عناصر مشتركة ===================
String? _validatePhone(String? v) {
  final p = StudentStore.normalizePhone(v ?? '');
  if (!RegExp(r'^07\d{9}$').hasMatch(p)) {
    return 'رقم هاتف غير صالح (مثال: 07701234567)';
  }
  return null;
}

InputDecoration _input(String label, IconData icon) => InputDecoration(
  labelText: label,
  prefixIcon: Icon(icon, color: AppColors.darkGreen),
  filled: true,
  fillColor: Colors.white,
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
);

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onPressed;

  const _PrimaryButton({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.darkGreen,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : LText(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}

class _AuthScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final bool showBack;

  const _AuthScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
    this.showBack = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgCream,
      appBar: AppBar(
        automaticallyImplyLeading: showBack,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.darkGreen,
        actions: const [LanguageButton(color: AppColors.darkGreen)],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.darkGreen,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.restaurant,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 16),
                  LText(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGreen,
                    ),
                  ),
                  const SizedBox(height: 6),
                  LText(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 28),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
