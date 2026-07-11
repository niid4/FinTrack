import 'package:hive/hive.dart';

part 'goal.g.dart';

@HiveType(typeId: 3)
class Goal extends HiveObject {
  @HiveField(0)
  String id = '';

  @HiveField(1)
  String title = '';
  
  @HiveField(2)
  double targetAmount = 0.0;
  
  @HiveField(3)
  late DateTime targetDate;
  
  @HiveField(4)
  double currentProgress = 0.0;
  
  @HiveField(5)
  String status = 'active';
  
  @HiveField(6)
  String reallocationFrequency = 'weekly';
}
