import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'translations.dart';

class AppLanguage extends ChangeNotifier {
  AppLanguage._();
  static final instance = AppLanguage._();
  static const preferenceKey = 'wajbati.language';
  String _code = 'ar';
  String get code => _code;
  bool get isEnglish => _code == 'en';
  Locale get locale => Locale(_code);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(preferenceKey);
    if (saved == 'ar' || saved == 'en') {
      _code = saved!;
      notifyListeners();
    }
  }

  Future<void> setLanguage(String code) async {
    if (code != 'ar' && code != 'en') return;
    _code = code;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(
      preferenceKey,
      code,
    );
  }

  String translate(String value) {
    if (!isEnglish || value.isEmpty) return value;
    final exact = englishTranslations[value];
    if (exact != null) return exact;
    for (final entry in _patterns.entries) {
      final match = entry.value.firstMatch(value);
      if (match == null) continue;
      final translation = englishTemplates[entry.key]!;
      return translation.replaceAllMapped(
        RegExp(r'\{(\d+)\}'),
        (part) => translate(match.group(int.parse(part[1]!) + 1) ?? ''),
      );
    }
    if (value.contains('\n')) {
      return value.split('\n').map(translate).join('\n');
    }
    if (value.contains('، ')) {
      return value.split('، ').map(translate).join(', ');
    }
    return value
        .replaceAll('د.ع', 'IQD')
        .replaceAll(RegExp(r'دقائق|دقيقة'), 'min')
        .replaceAll(RegExp(r'(?<=\d) ص(?=\s|$)'), ' AM')
        .replaceAll(RegExp(r'(?<=\d) م(?=\s|$)'), ' PM');
  }

  static final Map<String, RegExp> _patterns = {
    for (final key in englishTemplates.keys)
      key: RegExp(
        '^${key.split(RegExp(r'\{\d+\}')).map(RegExp.escape).join('(.*?)')}'
        r'$',
        dotAll: true,
      ),
  };
}

class LanguageScope extends InheritedNotifier<AppLanguage> {
  const LanguageScope({
    super.key,
    required AppLanguage language,
    required super.child,
  }) : super(notifier: language);

  static AppLanguage of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LanguageScope>()?.notifier ??
      AppLanguage.instance;
}

extension LocalizedString on String {
  String tr(BuildContext context) => LanguageScope.of(context).translate(this);
}

class LanguageButton extends StatelessWidget {
  final Color? color;
  const LanguageButton({super.key, this.color});
  @override
  Widget build(BuildContext context) {
    final language = LanguageScope.of(context);
    return TextButton.icon(
      onPressed: () => language.setLanguage(language.isEnglish ? 'ar' : 'en'),
      icon: const Icon(Icons.language, size: 20),
      label: Text(language.isEnglish ? 'العربية' : 'English'),
      style: TextButton.styleFrom(
        foregroundColor: color ?? Theme.of(context).appBarTheme.foregroundColor,
      ),
    );
  }
}
