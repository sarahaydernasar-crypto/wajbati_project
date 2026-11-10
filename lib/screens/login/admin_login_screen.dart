import 'package:flutter/material.dart';

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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
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
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => DashboardScreen(cafeteriaName: _store.cafeteria!.name)),
    );
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
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (_loadError != null) ...[
              Text(_loadError!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              TextButton.icon(onPressed: _loadCafeterias, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
              const SizedBox(height: 12),
            ] else if (_cafeterias == null) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<int>(
              initialValue: _selectedCafeteria,
              hint: const Text('اختر الكافيتريا الخاصة بك'),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.storefront),
              ),
              items: (_cafeterias ?? const <CafeteriaInfo>[])
                  .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                  .toList(),
              onChanged: (val) => setState(() => _selectedCafeteria = val),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _codeController,
              obscureText: true,
              onSubmitted: (_) => _loginAdmin(),
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
                onPressed: _loading ? null : _loginAdmin,
                child: _loading
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Text('دخول لوحة التحكم', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
