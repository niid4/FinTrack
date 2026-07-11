import 'package:hive/hive.dart';

part 'merchant_rule.g.dart';

@HiveType(typeId: 4)
class MerchantRule extends HiveObject {
  @HiveField(0)
  String merchantName = '';
  
  @HiveField(1)
  String category = '';
  
  @HiveField(2)
  String resolvedBy = '';
}
