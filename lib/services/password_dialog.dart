import 'package:flutter/material.dart';

import 'api_client.dart';

Future<void> showPasswordDialog(
  BuildContext context, {
  required ApiRole role,
}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _PasswordDialog(role: role),
  );
}

class _PasswordDialog extends StatefulWidget {
  final ApiRole role;
  const _PasswordDialog({required this.role});

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final current = TextEditingController();
  final next = TextEditingController();
  final confirmation = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    current.dispose();
    next.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final admin = widget.role == ApiRole.cafeteria;
    if (next.text.length < (admin ? 12 : 8) ||
        next.text != confirmation.text ||
        current.text.isEmpty) {
      setState(
        () => error =
            'أدخل القيمة الحالية وكلمة جديدة من ${admin ? 12 : 8} أحرف على الأقل، وطابق التأكيد.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await ApiClient.instance.post(
        admin ? '/admin/password' : '/auth/password',
        auth: widget.role,
        body: admin
            ? {'current_code': current.text, 'new_code': next.text}
            : {'current_password': current.text, 'new_password': next.text},
      );
      await ApiClient.instance.setToken(
        widget.role,
        (result as Map)['token'] as String,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ApiException
              ? e.message
              : 'تعذّر حفظ كلمة المرور. حاول مجدداً.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(
        widget.role == ApiRole.cafeteria
            ? 'تغيير رمز الكافيتريا'
            : 'تغيير كلمة المرور',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: current,
              obscureText: true,
              enabled: !busy,
              decoration: const InputDecoration(labelText: 'القيمة الحالية'),
            ),
            TextField(
              controller: next,
              obscureText: true,
              enabled: !busy,
              decoration: const InputDecoration(labelText: 'القيمة الجديدة'),
            ),
            TextField(
              controller: confirmation,
              obscureText: true,
              enabled: !busy,
              decoration: const InputDecoration(
                labelText: 'تأكيد القيمة الجديدة',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'سيتم إنهاء الجلسات القديمة بعد التغيير.',
              style: TextStyle(fontSize: 12),
            ),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(busy ? 'جارٍ الحفظ...' : 'حفظ'),
        ),
      ],
    ),
  );
}
