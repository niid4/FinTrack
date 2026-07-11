import 'package:hive/hive.dart';

part 'user_profile.g.dart';

@HiveType(typeId: 0)
class UserProfile extends HiveObject {
  @HiveField(0)
  bool hasCompletedOnboarding = false;
  
  @HiveField(1)
  String? authMethod; 
  
  @HiveField(2)
  String? mockUserId;
  
  @HiveField(3)
  String? userType; 
  
  @HiveField(4)
  String? spendRange; 
  
  @HiveField(5)
  double overallMonthlyBudget = 0.0;

  @HiveField(6)
  bool permissionsRequested = false;

  @HiveField(7)
  double monthlyIncome = 0.0;

  @HiveField(8)
  String? financialGoal;

  @HiveField(9)
  double savingsTarget = 0.0;

  @HiveField(10)
  int timelineMonths = 0;
}
