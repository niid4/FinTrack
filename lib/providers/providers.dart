import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/hive_service.dart';
import '../models/user_profile.dart';
import '../models/app_category.dart';
import '../models/app_transaction.dart';

final hiveServiceProvider = Provider<HiveService>((ref) {
  throw UnimplementedError();
});

final userProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final hive = ref.watch(hiveServiceProvider);
  return hive.getProfile();
});

final allCategoriesProvider = FutureProvider<List<AppCategory>>((ref) async {
  final hive = ref.watch(hiveServiceProvider);
  await hive.initDefaultCategories();
  return hive.getAllCategories();
});

final selectedCategoriesProvider = FutureProvider<List<AppCategory>>((ref) async {
  final hive = ref.watch(hiveServiceProvider);
  return hive.getSelectedCategories();
});

final transactionsStreamProvider = StreamProvider<List<AppTransaction>>((ref) {
  final hive = ref.watch(hiveServiceProvider);
  return hive.listenToTransactions();
});

class BudgetTotalNotifier extends StateNotifier<double> {
  BudgetTotalNotifier() : super(0.0);
  
  void updateCap(double cap) {
    state = cap;
  }
}
final budgetCapProvider = StateNotifierProvider<BudgetTotalNotifier, double>((ref) => BudgetTotalNotifier());
