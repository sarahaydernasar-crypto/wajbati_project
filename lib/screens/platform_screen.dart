import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../localization/localized_widgets.dart';
import '../services/api_client.dart';
import '../widgets/app_feedback.dart';

class PlatformScreen extends StatefulWidget {
  const PlatformScreen({super.key});
  @override
  State<PlatformScreen> createState() => _PlatformScreenState();
}

class _PlatformScreenState extends State<PlatformScreen> {
  final _api = ApiClient.instance;
  final _username = TextEditingController(text: 'admin');
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _authorized = false, _busy = false, _obscure = true;
  String? _error;
  List<Map<String, dynamic>> _cafeterias = [];

  @override
  void initState() {
    super.initState();
    if (_api.platformToken != null) _refresh();
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.get('/platform/me', auth: ApiRole.platform);
      final data =
          await _api.get('/platform/cafeterias', auth: ApiRole.platform)
              as List;
      if (mounted) {
        setState(() {
          _authorized = true;
          _cafeterias = data
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      }
    } catch (e) {
      if (e is ApiException && e.isUnauthorized) {
        await _api.setToken(ApiRole.platform, null);
        if (mounted) setState(() => _authorized = false);
      }
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _login() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data =
          await _api.post(
                '/platform/login',
                body: {
                  'username': _username.text.trim(),
                  'password': _password.text,
                },
              )
              as Map;
      await _api.setToken(ApiRole.platform, data['token'] as String);
      _password.clear();
      if (mounted) await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CafeteriaDialog(),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LText('تمت إضافة الكافيتريا بنجاح')),
      );
      await _refresh();
    }
  }

  Future<void> _changePassword() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _PlatformPasswordDialog(),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: LText(_authorized ? 'إدارة الكافيتريات' : 'مسؤول المنصة'),
      actions: [
        const LanguageButton(),
        if (_authorized)
          PopupMenuButton<String>(
            tooltip: 'إدارة المنصة'.tr(context),
            onSelected: (value) async {
              if (value == 'password') await _changePassword();
              if (value == 'logout') {
                await _api.setToken(ApiRole.platform, null);
                if (mounted) {
                  setState(() {
                    _authorized = false;
                    _cafeterias = [];
                    _error = null;
                  });
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'password',
                child: LText('تغيير كلمة المرور'),
              ),
              PopupMenuItem(value: 'logout', child: LText('تسجيل الخروج')),
            ],
          ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: !_authorized
            ? SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(
                            Icons.admin_panel_settings_outlined,
                            size: 64,
                            color: AppColors.darkGreen,
                          ),
                          const SizedBox(height: 24),
                          LTextFormField(
                            controller: _username,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'اسم المستخدم',
                            ),
                            validator: (v) => (v ?? '').trim().isEmpty
                                ? 'أدخل اسم المستخدم'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          LTextFormField(
                            controller: _password,
                            obscureText: _obscure,
                            decoration: InputDecoration(
                              labelText: 'كلمة المرور',
                              suffixIcon: IconButton(
                                tooltip:
                                    (_obscure ? 'إظهار الرمز' : 'إخفاء الرمز')
                                        .tr(context),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            onFieldSubmitted: (_) => _login(),
                            validator: (v) =>
                                (v ?? '').isEmpty ? 'أدخل كلمة المرور' : null,
                          ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: AppNotice(message: _error!, error: true),
                            ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _busy ? null : _login,
                            child: LText(
                              _busy ? 'جارٍ التحديث...' : 'تسجيل الدخول',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: LText(
                            'الكافيتريات',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _busy ? null : _add,
                          icon: const Icon(Icons.add),
                          label: const LText('إضافة كافيتريا'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const LText(
                      'سلّم الرمز لصاحب الكافيتريا ليضيف الأطباق ويدير الطلبات.',
                    ),
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: LinearProgressIndicator(),
                      ),
                    if (_error != null)
                      AppNotice(
                        message: _error!,
                        error: true,
                        onRetry: _refresh,
                      ),
                    const SizedBox(height: 16),
                    for (final cafe in _cafeterias)
                      Card(
                        child: ListTile(
                          leading: const Icon(
                            Icons.storefront,
                            color: AppColors.darkGreen,
                          ),
                          title: LText(cafe['name'] as String),
                          subtitle: LText(
                            '${cafe['location']}\n${cafe['open_hour']}:00 - ${cafe['close_hour']}:00',
                          ),
                          isThreeLine: true,
                        ),
                      ),
                  ],
                ),
              ),
      ),
    ),
  );
}

class _CafeteriaDialog extends StatefulWidget {
  const _CafeteriaDialog();
  @override
  State<_CafeteriaDialog> createState() => _CafeteriaDialogState();
}

class _CafeteriaDialogState extends State<_CafeteriaDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _location = TextEditingController(),
      _open = TextEditingController(text: '8'),
      _close = TextEditingController(text: '16'),
      _code = TextEditingController();
  bool _busy = false, _obscure = true;
  String? _error;
  @override
  void dispose() {
    for (final c in [_name, _location, _open, _close, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.instance.post(
        '/platform/cafeterias',
        auth: ApiRole.platform,
        body: {
          'name': _name.text.trim(),
          'location': _location.text.trim(),
          'open_hour': int.parse(_open.text),
          'close_hour': int.parse(_close.text),
          'code': _code.text,
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const LText('أضف كافيتريا جديدة'),
    scrollable: true,
    content: SizedBox(
      width: 460,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LTextFormField(
              controller: _name,
              enabled: !_busy,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'اسم الكافيتريا'),
              validator: (v) => (v ?? '').trim().length < 3
                  ? 'الاسم والموقع ثلاثة أحرف على الأقل'
                  : null,
            ),
            const SizedBox(height: 12),
            LTextFormField(
              controller: _location,
              enabled: !_busy,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'الموقع'),
              validator: (v) => (v ?? '').trim().length < 3
                  ? 'الاسم والموقع ثلاثة أحرف على الأقل'
                  : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: LTextFormField(
                    controller: _open,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'ساعة الفتح'),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return n == null || n < 0 || n > 23
                          ? 'ساعة من 0 إلى 23'
                          : null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LTextFormField(
                    controller: _close,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'ساعة الإغلاق',
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n < 1 || n > 24) {
                        return 'ساعة من 1 إلى 24';
                      }
                      return n <= (int.tryParse(_open.text) ?? 0)
                          ? 'وقت الإغلاق يجب أن يكون بعد وقت الفتح'
                          : null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            LTextFormField(
              controller: _code,
              enabled: !_busy,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'رمز الدخول لصاحب الكافيتريا',
                helperMaxLines: 3,
                helperText:
                    'رمز من 12 حرفاً إنجليزياً أو رقماً على الأقل، دون مسافات',
                suffixIcon: IconButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _obscure = !_obscure),
                  tooltip: (_obscure ? 'إظهار الرمز' : 'إخفاء الرمز').tr(
                    context,
                  ),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (v) =>
                  !RegExp(r'^[\x21-\x7e]{12,72}$').hasMatch(v ?? '')
                  ? 'رمز من 12 حرفاً إنجليزياً أو رقماً على الأقل، دون مسافات'
                  : null,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: AppNotice(message: _error!, error: true),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const LText('إلغاء'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: LText(_busy ? 'جارٍ الحفظ...' : 'إضافة كافيتريا'),
      ),
    ],
  );
}

class _PlatformPasswordDialog extends StatefulWidget {
  const _PlatformPasswordDialog();
  @override
  State<_PlatformPasswordDialog> createState() =>
      _PlatformPasswordDialogState();
}

class _PlatformPasswordDialogState extends State<_PlatformPasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController(),
      _next = TextEditingController(),
      _confirm = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data =
          await ApiClient.instance.post(
                '/platform/password',
                auth: ApiRole.platform,
                body: {
                  'current_password': _current.text,
                  'new_password': _next.text,
                },
              )
              as Map;
      await ApiClient.instance.setToken(
        ApiRole.platform,
        data['token'] as String,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: LText('تم تغيير كلمة المرور')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const LText('تغيير كلمة المرور'),
    scrollable: true,
    content: SizedBox(
      width: 420,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LTextFormField(
              controller: _current,
              obscureText: true,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'كلمة المرور الحالية',
              ),
              validator: (v) => (v ?? '').isEmpty ? 'أدخل كلمة المرور' : null,
            ),
            const SizedBox(height: 16),
            LTextFormField(
              controller: _next,
              obscureText: true,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'كلمة المرور الجديدة',
              ),
              validator: (v) => (v ?? '').length < 12
                  ? 'كلمة المرور 12 حرفاً على الأقل'
                  : null,
            ),
            const SizedBox(height: 16),
            LTextFormField(
              controller: _confirm,
              obscureText: true,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور'),
              validator: (v) =>
                  v != _next.text ? 'كلمتا المرور غير متطابقتين' : null,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: AppNotice(message: _error!, error: true),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const LText('إلغاء'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: LText(_busy ? 'جارٍ الحفظ...' : 'حفظ'),
      ),
    ],
  );
}
