import '../localization/localized_widgets.dart';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/app_colors.dart';
import '../models/order_model.dart';
import '../services/cafeteria_admin_store.dart';

class MenuItemEditorDialog extends StatefulWidget {
  final MenuItemModel? item;
  final Future<XFile?> Function()? pickImage;

  const MenuItemEditorDialog({super.key, this.item, this.pickImage});

  @override
  State<MenuItemEditorDialog> createState() => _MenuItemEditorDialogState();
}

class _MenuItemEditorDialogState extends State<MenuItemEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _prep;
  late final TextEditingController _ingredients;
  late final Set<String> _removable;
  List<String> get _ingredientNames => _ingredients.text
      .split(RegExp(r'[,،\n]'))
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .toSet()
      .toList();
  Uint8List? _image;
  String? _filename;
  String? _error;
  bool _saving = false;
  bool _picking = false;
  bool get _busy => _saving || _picking;
  bool get _isNew => widget.item == null;
  static const _maxImageBytes = 2 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.item?.name);
    _price = TextEditingController(text: widget.item?.price);
    _prep = TextEditingController(text: '${widget.item?.prepMinutes ?? 5}');
    _ingredients = TextEditingController(
      text: widget.item?.ingredients.join('، ') ?? '',
    );
    _removable = {...?widget.item?.removableIngredients};
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _prep.dispose();
    _ingredients.dispose();
    super.dispose();
  }

  Future<void> _chooseImage() async {
    if (_busy) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final file =
          await (widget.pickImage?.call() ??
              ImagePicker().pickImage(
                source: ImageSource.gallery,
                maxWidth: 800,
                maxHeight: 800,
                imageQuality: 80,
              ));
      if (file == null || !mounted) return;
      if (await file.length() > _maxImageBytes) {
        if (mounted) {
          setState(
            () => _error = 'حجم الصورة أكبر من 2 ميغابايت. اختر صورة أصغر.',
          );
        }
        return;
      }
      final bytes = await file.readAsBytes();
      // Decode before previewing, so unreadable images can be replaced before saving.
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 400);
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
      if (mounted) {
        setState(() {
          _image = bytes;
          _filename = file.name.isEmpty ? 'meal.jpg' : file.name;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'تعذّر قراءة الصورة. اختر صورة JPG أو PNG أو WEBP أو GIF صالحة.',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final store = CafeteriaAdminStore.instance;
      final price = int.parse(_price.text.trim());
      final prep = int.parse(_prep.text.trim());
      final result = _isNew
          ? await store.addMenuItem(
              _name.text.trim(),
              price,
              prep,
              imageBytes: _image,
              imageFilename: _filename,
              ingredients: _ingredientNames,
              removableIngredients: _ingredientNames
                  .where(_removable.contains)
                  .toList(),
            )
          : await store.editMenuItem(
              widget.item!,
              _name.text.trim(),
              price,
              prep,
              ingredients: _ingredientNames,
              removableIngredients: _ingredientNames
                  .where(_removable.contains)
                  .toList(),
            );
      if (!mounted) return;
      if (result.ok) {
        Navigator.pop(context, result);
      } else {
        setState(() => _error = result.message);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'تعذّر حفظ الوجبة. تحقق من الاتصال وحاول مجدداً.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _number(String? value, int maximum, String label) {
    final number = int.tryParse(value?.trim() ?? '');
    return number == null || number < 0 || number > maximum
        ? 'أدخل $label من 0 إلى $maximum'
        : null;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          const Icon(Icons.restaurant_menu, color: AppColors.darkGreen),
          const SizedBox(width: 10),
          Expanded(child: LText(_isNew ? 'إضافة طبق جديد' : 'تعديل الطبق')),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isNew) ...[
                  const LText(
                    'صورة الطبق',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _imagePicker(),
                  const SizedBox(height: 6),
                  LText(
                    'اختيارية • JPG، PNG، WEBP أو GIF • حتى 2 ميغابايت',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 20),
                ],
                LTextFormField(
                  controller: _name,
                  enabled: !_busy,
                  maxLength: 100,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'اسم الطبق',
                    hintText: 'مثال: صمون كباب لحم',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.restaurant),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'أدخل اسم الطبق'
                      : null,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: LTextFormField(
                        controller: _price,
                        enabled: !_busy,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'السعر',
                          helperText: 'دينار عراقي',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => _number(value, 1000000, 'سعراً'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: LTextFormField(
                        controller: _prep,
                        enabled: !_busy,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'وقت التحضير',
                          helperText: 'دقيقة',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => _number(value, 120, 'وقتاً'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                LTextFormField(
                  controller: _ingredients,
                  enabled: !_busy,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'مكونات الطبق',
                    hintText: 'مثال: شاي، ماء، سكر',
                    helperText: 'افصل بين المكونات بفاصلة. حتى 20 مكوناً.',
                  ),
                  onChanged: (_) =>
                      setState(() => _removable.retainAll(_ingredientNames)),
                  validator: (_) =>
                      _ingredientNames.length > 20 ||
                          _ingredientNames.any((v) => v.length > 40)
                      ? 'حتى 20 مكوناً، و40 حرفاً لكل مكون'
                      : null,
                ),
                if (_ingredientNames.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const LText(
                    'المكونات التي يمكن للطالب إزالتها',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const LText(
                    'اختر المكونات الاختيارية فقط؛ للشاي اختر السكر.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final ingredient in _ingredientNames)
                        FilterChip(
                          label: LText(ingredient),
                          selected: _removable.contains(ingredient),
                          onSelected: _busy
                              ? null
                              : (selected) => setState(() {
                                  if (selected) {
                                    _removable.add(ingredient);
                                  } else {
                                    _removable.remove(ingredient);
                                  }
                                }),
                        ),
                    ],
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: LText(
                      _error!,
                      style: TextStyle(color: Colors.red.shade800),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const LText('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: AppColors.darkGreen),
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check),
          label: LText(
            _saving
                ? 'جارٍ الحفظ...'
                : _isNew
                ? 'إضافة إلى المنيو'
                : 'حفظ التعديلات',
          ),
        ),
      ],
    ),
  );

  Widget _imagePicker() => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: Material(
      color: AppColors.darkGreen.withValues(alpha: 0.05),
      child: InkWell(
        onTap: _busy ? null : _chooseImage,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: _image == null
              ? Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.green.shade200),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_picking)
                        const CircularProgressIndicator()
                      else
                        const Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 40,
                          color: AppColors.darkGreen,
                        ),
                      const SizedBox(height: 8),
                      LText(
                        _picking ? 'جارٍ تجهيز الصورة...' : 'اختر صورة للطبق',
                        style: const TextStyle(
                          color: AppColors.darkGreen,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(
                      _image!,
                      fit: BoxFit.cover,
                      semanticLabel: 'معاينة صورة الطبق',
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: IconButton.filled(
                        tooltip: ('إزالة الصورة').tr(context),
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _image = null;
                                _filename = null;
                              }),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: FilledButton.tonalIcon(
                        onPressed: _busy ? null : _chooseImage,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const LText('تغيير الصورة'),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    ),
  );
}
