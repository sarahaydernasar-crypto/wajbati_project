class OrderItem {
  final String id;
  final String studentName;
  final String details;
  final String cafeteriaName;
  final String prepTime;
  String status; // الحالات: 'طلب جديد', 'جاري التجهيز', 'تم الاستلام'
  final String time;
  final double price;
  final DateTime date;

  OrderItem({
    required this.id,
    required this.studentName,
    required this.details,
    required this.cafeteriaName,
    required this.prepTime,
    this.status = 'طلب جديد',
    required this.time,
    required this.price,
    required this.date,
  });
}

class MenuItemModel {
  String name;
  String price;
  String preptime;
  bool isAvailable;

  MenuItemModel({
    required this.name,
    required this.price,
    required this.preptime,
    this.isAvailable = true,
  });
}

class SharedData {
  static final List<OrderItem> orders = [];

  static final List<MenuItemModel> menuitems = [
    MenuItemModel(name: 'صمون كباب لحم', price: '3000', preptime: '10 دقائق'),
    MenuItemModel(name: 'ببسي / عصير', price: '1000', preptime: '2 دقائق'),
    MenuItemModel(name: 'شاي مهيل', price: '500', preptime: '5 دقائق'),
  ];

  static void addMenuItem(String name, String price, String preptime) {
    menuitems.add(MenuItemModel(
      name: name,
      price: price,
      preptime: preptime,
      isAvailable: true,
    ));
  }

  static double getWeeklyRevenue(String cafeteriaName) {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    
    double total = 0;
    for (var order in orders) {
      if (order.cafeteriaName == cafeteriaName && 
          order.status == 'تم الاستلام' && 
          order.date.isAfter(weekAgo)) {
        total += order.price;
      }
    }
    return total;
  }

  static final Map<String, String> cafeteriasWithCodes = {
    'كافيتريا علوم حاسوب': 'CS771SOL',
    'كافيتريا العلوم التطبيقية': 'AP882APP',
    'كافيتريا كهرومكانيك': 'EM993MEH',
    'كافيتريا طب حياتي': 'BM445BIO',
    'كافيتريا معماري': 'AR556ARC',
  };
}