import 'package:hive/hive.dart';

part 'app_category.g.dart';

@HiveType(typeId: 1)
class AppCategory extends HiveObject {
  @HiveField(0)
  String name = '';
  
  @HiveField(1)
  String? iconName;
  
  @HiveField(2)
  bool isSystem = false;
  
  @HiveField(3)
  bool isSelected = false; 

  @HiveField(4)
  double monthlyAllocation = 0.0; 
}
