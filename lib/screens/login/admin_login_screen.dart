import '../../localization/localized_widgets.dart';
import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';

import '../../services/cafeteria_admin_store.dart';
import '../../services/server_settings_dialog.dart';
import '../student/student_store.dart' show CafeteriaInfo;
import '../dashboard_screen.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _store = CafeteriaAdminStore.instance;
  final TextEditingController _codeController = TextEditingController();
  List<CafeteriaInfo>? _cafeterias;
  String? _loadError;
  int? _selectedCafeteria;
  bool _loading = false;
  bool _obscureCode = true;

  @override
  void initState() {
    super.initState();
    _loadCafeterias();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadCafeterias() async {
    setState(() => _loadError = null);
    try {
      final list = await _store.fetchCafeterias();
      if (mounted) setState(() => _cafeterias = list);
    } catch (e) {
      if (mounted) setState(() => _loadError = e.toString());
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: LText(msg), backgroundColor: Colors.red));
  }

  Future<void> _loginAdmin() async {
    if (_selectedCafeteria == null) {
      _showError('الرجاء اختيار الكافيتريا أولاً');
      return;
    }
    setState(() => _loading = true);
    final r = await _store.login(_selectedCafeteria!, _codeController.text);
    if (!mounted) return;
    setState(() => _loading = false);
    if (!r.ok) {
      _showError(r.message);
      return;
    }
    _codeController.clear();
    setState(() => _obscureCode = true);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            DashboardScreen(cafeteriaName: _store.cafeteria!.name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const LText(
          'تسجيل دخول مسؤول الكافيتريا',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.darkGreen,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
        actions: const [LanguageButton()],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (_loadError != null) ...[
              LText(
                _loadError!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              TextButton.icon(
                onPressed: _loadCafeterias,
                icon: const Icon(Icons.refresh),
                label: const LText('إعادة المحاولة'),
              ),
              const SizedBox(height: 12),
            ] else if (_cafeterias == null) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<int>(
              initialValue: _selectedCafeteria,
              hint: const LText('اختر الكافيتريا الخاصة بك'),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.storefront),
              ).localized(context),
              items: (_cafeterias ?? const <CafeteriaInfo>[])
                  .map(
                    (c) => DropdownMenuItem(value: c.id, child: LText(c.name)),
                  )
                  .toList(),
              onChanged: (val) => setState(() => _selectedCafeteria = val),
            ),
            const SizedBox(height: 16),
            LTextField(
              controller: _codeController,
              obscureText: _obscureCode,
              onSubmitted: (_) => _loginAdmin(),
              decoration: InputDecoration(
                labelText: 'الرمز السري للكافيتريا',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  tooltip: (_obscureCode ? 'إظهار الرمز' : 'إخفاء الرمز').tr(
                    context,
                  ),
                  icon: Icon(
                    _obscureCode
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscureCode = !_obscureCode),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.darkGreen,
                  foregroundColor: Colors.white,
                ),
                onPressed: _loading ? null : _loginAdmin,
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const LText(
                        'دخول لوحة التحكم',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            const ServerSettingsButton(),
          ],
        ),
      ),
    );
  }
}
