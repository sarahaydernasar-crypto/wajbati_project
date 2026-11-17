import 'localization/localized_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'constants/app_theme.dart';
import 'screens/student/student_auth_screens.dart'; // واجهة الطالب: تسجيل الدخول / إنشاء حساب
import 'screens/student/student_store.dart';
import 'screens/student_order_screen.dart';
import 'services/api_client.dart';
import 'services/push_service.dart';
import 'widgets/app_feedback.dart';
import 'screens/student/student_widgets.dart' show EmptyState;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Tajawal',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  runApp(const WajbatiBootstrap());
}

class WajbatiBootstrap extends StatefulWidget {
  final Future<void> Function()? initialize;
  const WajbatiBootstrap({super.key, this.initialize});
  @override
  State<WajbatiBootstrap> createState() => _WajbatiBootstrapState();
}

class _WajbatiBootstrapState extends State<WajbatiBootstrap> {
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      if (widget.initialize != null) {
        await widget.initialize!();
      } else {
        await AppLanguage.instance.init();
        await ApiClient.instance.init();
        await PushService.instance.init();
        await StudentStore.instance.init();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'تعذّر تجهيز التطبيق. أعد المحاولة.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => WajbatiApp(
    initializing: _loading,
    startupError: _error,
    onRetry: _initialize,
  );
}

class WajbatiApp extends StatelessWidget {
  final bool initializing;
  final String? startupError;
  final VoidCallback? onRetry;
  const WajbatiApp({
    super.key,
    this.initializing = false,
    this.startupError,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLanguage.instance,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: AppLanguage.instance.isEnglish ? 'Wajbati' : 'وجباتي - Wajbati',
        theme: buildAppTheme(),
        locale: AppLanguage.instance.locale,
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        // التطبيق عربي: اتجاه من اليمين لليسار لكل الشاشات
        builder: (context, child) => LanguageScope(
          language: AppLanguage.instance,
          child: Directionality(
            textDirection: AppLanguage.instance.isEnglish
                ? TextDirection.ltr
                : TextDirection.rtl,
            child: child!,
          ),
        ),
        // إذا كان الطالب مسجّل دخول مسبقاً يفتح التطبيق مباشرة على الشاشة الرئيسية
        home: initializing
            ? const Scaffold(
                body: SafeArea(
                  child: LoadingCards(label: 'نجهّز لك وجباتي...'),
                ),
              )
            : startupError != null
            ? Scaffold(
                body: EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: startupError!,
                  subtitle:
                      'تحقق من الاتصال ثم أعد المحاولة، أو أعد فتح التطبيق.',
                  action: FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const LText('إعادة المحاولة'),
                  ),
                ),
              )
            : StudentStore.instance.isLoggedIn
            ? const StudentOrderScreen()
            : const StudentLoginScreen(),
      ),
    );
  }
}
