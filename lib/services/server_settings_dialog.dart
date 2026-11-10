import 'package:flutter/material.dart';

import 'api_client.dart';

/// زر صغير يعرض عنوان السيرفر الحالي ويفتح نافذة تعديله
class ServerSettingsButton extends StatefulWidget {
  const ServerSettingsButton({super.key});

  @override
  State<ServerSettingsButton> createState() => _ServerSettingsButtonState();
}

class _ServerSettingsButtonState extends State<ServerSettingsButton> {
  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () async {
        await showServerSettings(context);
        if (mounted) setState(() {});
      },
      icon: const Icon(Icons.dns_outlined, size: 18),
      label: Text('السيرفر: ${ApiClient.instance.baseUrl}', style: const TextStyle(fontSize: 12)),
      style: TextButton.styleFrom(foregroundColor: Colors.grey.shade600),
    );
  }
}

/// تغيير عنوان السيرفر (مثلاً عند التشغيل على هاتف حقيقي: http://192.168.1.10:8000)
Future<void> showServerSettings(BuildContext context) async {
  final api = ApiClient.instance;
  final ctrl = TextEditingController(text: api.baseUrl);
  String? result;
  var testing = false;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: const Text('عنوان السيرفر'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'http://192.168.1.10:8000',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '• على نفس الكمبيوتر: http://localhost:8000\n'
              '• محاكي أندرويد: http://10.0.2.2:8000\n'
              '• هاتف حقيقي: عنوان IP للكمبيوتر على نفس شبكة الواي فاي',
              style: TextStyle(fontSize: 12),
            ),
            if (result != null) ...[
              const SizedBox(height: 8),
              Text(result!,
                  style: TextStyle(
                      color: result!.startsWith('✅') ? Colors.green.shade700 : Colors.red.shade700,
                      fontWeight: FontWeight.bold)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: testing
                ? null
                : () async {
                    setD(() => testing = true);
                    var url = ctrl.text.trim();
                    if (!url.startsWith('http')) url = 'http://$url';
                    final ok = await api.ping(url);
                    setD(() {
                      testing = false;
                      result = ok ? '✅ الاتصال ناجح' : '❌ تعذّر الوصول للسيرفر على هذا العنوان';
                    });
                  },
            child: Text(testing ? 'جارٍ الفحص...' : 'فحص الاتصال'),
          ),
          FilledButton(
            onPressed: () async {
              await api.setBaseUrl(ctrl.text);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    ),
  );
}
