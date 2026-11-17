import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_language.dart';
export 'app_language.dart';

/// A Text-compatible widget which subscribes to language changes in place.
/// Routes, controllers, cart contents and entered form values are preserved.
class LText extends Text {
  const LText(
    super.data, {
    super.key,
    super.style,
    super.strutStyle,
    super.textAlign,
    super.textDirection,
    super.locale,
    super.softWrap,
    super.overflow,
    super.textScaler,
    super.maxLines,
    super.semanticsLabel,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionColor,
  });

  @override
  Widget build(BuildContext context) {
    final language = LanguageScope.of(context);
    return Text(
      language.translate(data!),
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel == null
          ? null
          : language.translate(semanticsLabel!),
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    ).build(context);
  }
}

extension LocalizedDecoration on InputDecoration {
  InputDecoration localized(BuildContext context) {
    final language = LanguageScope.of(context);
    String? t(String? value) =>
        value == null ? null : language.translate(value);
    return copyWith(
      labelText: t(labelText),
      hintText: t(hintText),
      helperText: t(helperText),
      errorText: t(errorText),
      prefixText: t(prefixText),
      suffixText: t(suffixText),
    );
  }
}

class LTextField extends StatelessWidget {
  final TextEditingController? controller;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextDirection? textDirection;
  final int? maxLength;
  final int? maxLines;
  final bool obscureText, autofocus;
  final bool? enabled;
  final ValueChanged<String>? onChanged, onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  const LTextField({
    super.key,
    this.controller,
    this.decoration = const InputDecoration(),
    this.keyboardType,
    this.textInputAction,
    this.textDirection,
    this.maxLength,
    this.maxLines = 1,
    this.obscureText = false,
    this.autofocus = false,
    this.enabled,
    this.onChanged,
    this.onSubmitted,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    decoration: decoration?.localized(context),
    keyboardType: keyboardType,
    textInputAction: textInputAction,
    textDirection: textDirection,
    maxLength: maxLength,
    maxLines: maxLines,
    obscureText: obscureText,
    autofocus: autofocus,
    enabled: enabled,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    inputFormatters: inputFormatters,
  );
}

class LTextFormField extends StatelessWidget {
  final TextEditingController? controller;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int? maxLength;
  final int? maxLines;
  final bool obscureText;
  final bool? enabled;
  final ValueChanged<String>? onChanged, onFieldSubmitted;
  final FormFieldValidator<String>? validator;
  final List<TextInputFormatter>? inputFormatters;
  const LTextFormField({
    super.key,
    this.controller,
    this.decoration = const InputDecoration(),
    this.keyboardType,
    this.textInputAction,
    this.maxLength,
    this.maxLines = 1,
    this.obscureText = false,
    this.enabled,
    this.onChanged,
    this.onFieldSubmitted,
    this.validator,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    decoration: decoration?.localized(context),
    keyboardType: keyboardType,
    textInputAction: textInputAction,
    maxLength: maxLength,
    maxLines: maxLines,
    obscureText: obscureText,
    enabled: enabled,
    onChanged: onChanged,
    onFieldSubmitted: onFieldSubmitted,
    validator: validator,
    errorBuilder: (ctx, message) => LText(
      message,
      style: TextStyle(color: Theme.of(ctx).colorScheme.error, fontSize: 12),
    ),
    inputFormatters: inputFormatters,
  );
}
