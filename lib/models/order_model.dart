class OrderItem {
  final String id;
  final String studentName;
  final String details;
  final String cafeteriaName;
  final String prepTime;
  String status;
  final String time;
  final double price;

  OrderItem({
    required this.id,
    required this.studentName,
    required this.details,
    required this.cafeteriaName,
    required this.prepTime,
    required this.status,
    required this.time,
    required this.price,
  });
}

class MenuItemModel {
  String name;
  String price;
  String preptime;

  MenuItemModel({
    required this.name,
    required this.price,
    required this.preptime,
  });
}

class SharedData {
  static final List<OrderItem> orders = [];

  static final List<MenuItemModel> menuitems = [
    MenuItemModel(name: 'صمون كباب لحم', price: '3000', preptime: '10 دقائق'),
    MenuItemModel(name: 'ببسي / عصير', price: '1000', preptime: '2 دقائق'),
    MenuItemModel(name: 'شاي مهيل', price: '500', preptime: '5 دقائق'),
  ];

  // رموز الكافيتريات المكونة من 8 خانات بالضبط لكل كافيتريا
  static final Map<String, String> cafeteriasWithCodes = {
    'كافيتريا علوم حاسوب': 'CS771SOL',
    'كافيتريا العلوم التطبيقية': 'AP882APP',
    'كافيتريا كهرومكانيك': 'EM993MEH',
    'كافيتريا طب حياتي': 'BM445BIO',
    'كافيتريا معماري': 'AR556ARC',
  };
}