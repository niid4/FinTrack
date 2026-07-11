import 'package:hive_flutter/hive_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_profile.dart';
import '../models/app_category.dart';
import '../models/app_transaction.dart';
import '../models/goal.dart';
import '../models/merchant_rule.dart';
import 'dart:async';

class HiveService {
  late Box<UserProfile> profileBox;
  late Box<AppCategory> categoryBox;
  late Box<AppTransaction> transactionBox;
  late Box<Goal> goalBox;
  late Box<MerchantRule> merchantRuleBox;
  
  final _transactionsStreamController = StreamController<List<AppTransaction>>.broadcast();

  HiveService();

  Future<void> init() async {
    await Hive.initFlutter();
    
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(UserProfileAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(AppCategoryAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(AppTransactionAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(GoalAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(MerchantRuleAdapter());

    try {
      profileBox = await Hive.openBox<UserProfile>('user_profile');
      categoryBox = await Hive.openBox<AppCategory>('categories');
      transactionBox = await Hive.openBox<AppTransaction>('transactions');
      goalBox = await Hive.openBox<Goal>('goals');
      merchantRuleBox = await Hive.openBox<MerchantRule>('merchant_rules');
    } catch (e) {
      // ignore: avoid_print
      print("Hive initialization failed, deleting boxes and retrying: $e");
      try {
        await Hive.deleteBoxFromDisk('user_profile');
        await Hive.deleteBoxFromDisk('categories');
        await Hive.deleteBoxFromDisk('transactions');
        await Hive.deleteBoxFromDisk('goals');
        await Hive.deleteBoxFromDisk('merchant_rules');
      } catch (_) {}
      
      profileBox = await Hive.openBox<UserProfile>('user_profile');
      categoryBox = await Hive.openBox<AppCategory>('categories');
      transactionBox = await Hive.openBox<AppTransaction>('transactions');
      goalBox = await Hive.openBox<Goal>('goals');
      merchantRuleBox = await Hive.openBox<MerchantRule>('merchant_rules');
    }
  }

  void _syncToFirestore(String collection, String docId, Map<String, dynamic> data) {
    try {
      final String uid = profileBox.isNotEmpty ? (profileBox.getAt(0)?.mockUserId ?? 'anonymous') : 'anonymous';
      if (uid == 'anonymous') return;
      
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection(collection)
          .doc(docId)
          .set(data, SetOptions(merge: true))
          .catchError((e) => print('Firestore sync error: $e'));
    } catch (e) {
      print('Firestore sync error: $e');
    }
  }

  // --- Profile ---
  Future<UserProfile?> getProfile() async {
    if (profileBox.isEmpty) return null;
    return profileBox.getAt(0);
  }

  Future<void> saveProfile(UserProfile profile) async {
    if (profileBox.isEmpty) {
      await profileBox.add(profile);
    } else {
      await profileBox.putAt(0, profile);
    }
    // Sync profile
    _syncToFirestore('profile', 'main', {
      'hasCompletedOnboarding': profile.hasCompletedOnboarding,
      'authMethod': profile.authMethod,
      'userType': profile.userType,
      'spendRange': profile.spendRange,
      'overallMonthlyBudget': profile.overallMonthlyBudget,
      'monthlyIncome': profile.monthlyIncome,
      'financialGoal': profile.financialGoal,
      'savingsTarget': profile.savingsTarget,
      'timelineMonths': profile.timelineMonths,
    });
  }

  // --- Categories ---
  Future<void> initDefaultCategories() async {
    if (categoryBox.isEmpty) {
      final defaultCats = [
        AppCategory()..name = 'Food'..isSystem = true,
        AppCategory()..name = 'Shopping'..isSystem = true,
        AppCategory()..name = 'Travel'..isSystem = true,
        AppCategory()..name = 'Entertainment'..isSystem = true,
        AppCategory()..name = 'Bills'..isSystem = true,
        AppCategory()..name = 'Education'..isSystem = true,
        AppCategory()..name = 'Healthcare'..isSystem = true,
        AppCategory()..name = 'Groceries'..isSystem = true,
        AppCategory()..name = 'Personal'..isSystem = true,
        AppCategory()..name = 'Savings'..isSystem = true,
        AppCategory()..name = 'Other'..isSystem = true,
      ];
      await categoryBox.addAll(defaultCats);
    }
  }

  Future<List<AppCategory>> getAllCategories() async {
    return categoryBox.values.toList();
  }
  
  Future<List<AppCategory>> getSelectedCategories() async {
    return categoryBox.values.where((c) => c.isSelected).toList();
  }

  Future<void> updateCategory(AppCategory category) async {
    await category.save();
    _syncToFirestore('categories', category.name, {
      'name': category.name,
      'isSelected': category.isSelected,
      'isSystem': category.isSystem,
      'monthlyAllocation': category.monthlyAllocation,
    });
  }

  // --- Transactions ---
  Future<void> saveTransaction(AppTransaction tx) async {
    // add() throws if the object is already in a box (e.g. when the
    // categorize bar updates an existing transaction) — use save() then.
    if (tx.isInBox) {
      await tx.save();
    } else {
      await transactionBox.add(tx);
    }
    _transactionsStreamController.add(getTransactionsSync());
    
    _syncToFirestore('transactions', tx.key.toString(), {
      'amount': tx.amount,
      'merchant': tx.merchant,
      'date': tx.date.toIso8601String(),
      'customCategory': tx.customCategory,
      'isUncategorized': tx.isUncategorized,
    });
  }

  Future<List<AppTransaction>> getTransactions() async {
    return getTransactionsSync();
  }
  
  List<AppTransaction> getTransactionsSync() {
    final list = transactionBox.values.toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }
  
  Stream<List<AppTransaction>> listenToTransactions() async* {
    yield getTransactionsSync();
    yield* _transactionsStreamController.stream;
  }
  
  // --- Goals ---
  Future<List<Goal>> getGoals() async {
    return goalBox.values.toList();
  }
  
  Future<void> saveGoal(Goal goal) async {
    if (goal.id.isEmpty) {
      goal.id = DateTime.now().millisecondsSinceEpoch.toString();
    }
    
    if (goal.isInBox) {
      await goal.save();
    } else {
      await goalBox.put(goal.id, goal);
    }
    
    _syncToFirestore('goals', goal.id, {
      'id': goal.id,
      'title': goal.title,
      'targetAmount': goal.targetAmount,
      'targetDate': goal.targetDate.toIso8601String(),
      'currentProgress': goal.currentProgress,
      'status': goal.status,
      'reallocationFrequency': goal.reallocationFrequency,
    });
  }
  
  // --- Merchant Dictionary ---
  MerchantRule? getMerchantRule(String name) {
    try {
      return merchantRuleBox.values.firstWhere((rule) => rule.merchantName == name);
    } catch (e) {
      return null;
    }
  }
  
  Future<void> saveMerchantRule(MerchantRule rule) async {
    await merchantRuleBox.add(rule);
    _syncToFirestore('merchant_dictionary', rule.merchantName, {
      'merchantName': rule.merchantName,
      'category': rule.category,
      'resolvedBy': rule.resolvedBy,
    });
  }
}
