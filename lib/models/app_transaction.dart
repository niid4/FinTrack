import 'package:hive/hive.dart';

part 'app_transaction.g.dart';

@HiveType(typeId: 2)
class AppTransaction extends HiveObject {
  @HiveField(0)
  double amount = 0.0;
  
  @HiveField(1)
  String merchant = '';
  
  @HiveField(2)
  late DateTime date;

  @HiveField(3)
  int? categoryId;
  
  @HiveField(4)
  String? customCategory;
  
  @HiveField(5)
  bool isUncategorized = true;

  /// Set when the user taps "Skip" on the categorize notification — the
  /// transaction stays in history but is no longer surfaced for
  /// categorization (notification or in-app fallback bar).
  @HiveField(6)
  bool isSkipped = false;
}
