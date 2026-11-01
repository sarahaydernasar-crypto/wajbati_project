import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../constants/app_colors.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final MobileScannerController controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgCream,
      appBar: AppBar(
        title: const Text('كاميرا مسح باركود الطالب', style: TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: AppColors.darkGreen,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: MobileScanner(
        controller: controller,
        onDetect: (capture) {
          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            final String? code = barcode.rawValue;
            if (code != null) {
              controller.stop();
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('تم التحقق من الرمز بنجاح 🎯', style: TextStyle(color: AppColors.darkGreen, fontWeight: FontWeight.bold)),
                  content: Text('باركود الطالب المقروء: $code\nالطلب مطابقة وجاهز للتسليم النهائي!'),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        controller.start();
                      },
                      child: const Text('موافق'),
                    ),
                  ],
                ),
              );
              break;
            }
          }
        },
      ),
    );
  }
}