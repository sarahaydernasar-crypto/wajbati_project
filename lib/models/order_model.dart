class OrderItem {
  final String id;
  final String studentName;
  final String details;
  final String cafeteriaName;
  final String prepTime;
  String status; // received / preparing / ready / delivered (انظر OrderStatus)
  final String time;
  final double price;
  final DateTime date;

  // ===== حقول واجهة الطالب =====
  final String? studentId; // الرقم الجامعي
  final int? cafeteriaId;
  final List<OrderLine> lines; // الأصناف بالتفصيل (للسجل و"أعد الطلب")
  final DateTime? pickupTime; // وقت الاستلام المختار
  final String paymentMethod;
  bool studentArrived; // ضغط الطالب زر "وصلت"
  int? rating; // تقييم الطالب للطلب (1-5)
  String? ratingComment;
  final String? closureReason;

  OrderItem({
    required this.id,
    required this.studentName,
    required this.details,
    required this.cafeteriaName,
    required this.prepTime,
    this.status = 'received',
    required this.time,
    required this.price,
    required this.date,
    this.studentId,
    this.cafeteriaId,
    this.lines = const [],
    this.pickupTime,
    this.paymentMethod = 'نقداً عند الاستلام',
    this.studentArrived = false,
    this.rating,
    this.ratingComment,
    this.closureReason,
  });

  /// من استجابة السيرفر
  factory OrderItem.fromApi(Map<String, dynamic> j) {
    final lines = ((j['lines'] as List?) ?? [])
        .map((e) => OrderLine.fromApi(Map<String, dynamic>.from(e as Map)))
        .toList();
    final created = DateTime.parse(j['created_at'] as String);
    return OrderItem(
      id: j['id'] as String,
      studentName: j['student_name'] as String,
      details: lines
          .map(
            (l) =>
                '${l.itemName} ×${l.quantity}${l.note.isEmpty ? '' : ' (${l.note})'}',
          )
          .join('، '),
      cafeteriaName: j['cafeteria_name'] as String,
      cafeteriaId: j['cafeteria_id'] as int?,
      prepTime: '${j['prep_minutes']} دقائق',
      status: j['status'] as String,
      time:
          '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}',
      price: (j['total'] as num).toDouble(),
      date: created,
      studentId: j['student_university_id'] as String?,
      lines: lines,
      pickupTime: j['pickup_time'] == null
          ? null
          : DateTime.parse(j['pickup_time'] as String),
      paymentMethod: (j['payment_method'] as String?) ?? 'نقداً عند الاستلام',
      studentArrived: (j['arrived'] as bool?) ?? false,
      rating: j['rating'] as int?,
      ratingComment: j['rating_comment'] as String?,
      closureReason: j['closure_reason'] as String?,
    );
  }
}

/// سطر واحد داخل الطلب: الصنف + الكمية + الملاحظة
class OrderLine {
  final int? menuItemId;
  final String itemName;
  final int quantity;
  final double unitPrice;
  final String note;

  const OrderLine({
    this.menuItemId,
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
    this.note = '',
  });

  double get total => unitPrice * quantity;

  factory OrderLine.fromApi(Map<String, dynamic> j) => OrderLine(
    menuItemId: j['menu_item_id'] as int?,
    itemName: j['item_name'] as String,
    quantity: j['quantity'] as int,
    unitPrice: (j['unit_price'] as num).toDouble(),
    note: (j['note'] as String?) ?? '',
  );
}

class MenuItemModel {
  int? id;
  int? cafeteriaId;
  String? cafeteriaName;
  String name;
  String price;
  String preptime;
  bool isAvailable;
  String? imageUrl; // صورة الصنف (اختيارية)
  String emoji; // أيقونة بديلة تظهر عند عدم وجود صورة أو ضعف النت
  double? ratingAvg; // متوسط تقييم الطلاب (من السيرفر)
  int ratingCount;

  MenuItemModel({
    this.id,
    this.cafeteriaId,
    this.cafeteriaName,
    required this.name,
    required this.price,
    required this.preptime,
    this.isAvailable = true,
    this.imageUrl,
    this.emoji = '🍽️',
    this.ratingAvg,
    this.ratingCount = 0,
  });

  factory MenuItemModel.fromApi(Map<String, dynamic> j) => MenuItemModel(
    id: j['id'] as int,
    cafeteriaId: j['cafeteria_id'] as int?,
    cafeteriaName: j['cafeteria_name'] as String?,
    name: j['name'] as String,
    price: '${j['price']}',
    preptime: '${j['prep_minutes']} دقائق',
    isAvailable: (j['available'] as bool?) ?? true,
    imageUrl: j['image_url'] as String?,
    emoji: (j['emoji'] as String?) ?? '🍽️',
    ratingAvg: (j['rating_avg'] as num?)?.toDouble(),
    ratingCount: (j['rating_count'] as int?) ?? 0,
  );

  double get priceValue => double.tryParse(price.trim()) ?? 0;

  /// وقت التحضير بالدقائق (يُستخرج من نص مثل "10 دقائق")
  int get prepMinutes {
    final m = RegExp(r'\d+').firstMatch(preptime);
    return m == null ? 5 : int.parse(m.group(0)!);
  }

  double? get averageRating => ratingAvg;
}
