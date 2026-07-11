import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

class BudgetSetupScreen extends ConsumerStatefulWidget {
  const BudgetSetupScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<BudgetSetupScreen> createState() => _BudgetSetupScreenState();
}

class _BudgetSetupScreenState extends ConsumerState<BudgetSetupScreen> {
  int _selectedIndex = 0;
  final TextEditingController _capController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Load the saved cap from the profile instead of hardcoding 30000
    // (the old value was never persisted, so the dashboard always showed
    // Budget = 0 and the cap reset on every restart).
    Future.microtask(() async {
      final hive = ref.read(hiveServiceProvider);
      final profile = await hive.getProfile();
      final cap = (profile?.overallMonthlyBudget ?? 0) > 0
          ? profile!.overallMonthlyBudget
          : 30000.0;
      if (!mounted) return;
      _capController.text = cap.toStringAsFixed(0);
      ref.read(budgetCapProvider.notifier).updateCap(cap);
    });
  }

  Future<void> _persistCap(double cap) async {
    ref.read(budgetCapProvider.notifier).updateCap(cap);
    final hive = ref.read(hiveServiceProvider);
    final profile = await hive.getProfile();
    if (profile != null) {
      profile.overallMonthlyBudget = cap;
      await hive.saveProfile(profile);
      ref.invalidate(userProfileProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(selectedCategoriesProvider);
    final overallCap = ref.watch(budgetCapProvider);

    return Scaffold(
      body: Container(
        decoration: AppTheme.backgroundGradient,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Budget Setup', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 28)),
                  ],
                ),
              ),

              // Monthly Cap Input
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Text('Monthly Cap: ₹', style: TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(
                        child: TextField(
                          controller: _capController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(border: InputBorder.none),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                          onChanged: (val) {
                            final cap = double.tryParse(val) ?? 0.0;
                            _persistCap(cap);
                          },
                        ),
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              categoriesAsync.when(
                data: (cats) {
                  if (cats.isEmpty) {
                    return const Expanded(child: Center(child: Text('No categories selected.')));
                  }
                  
                  final selectedCat = cats[_selectedIndex];
                  double totalAllocated = cats.fold(0.0, (sum, cat) => sum + cat.monthlyAllocation);

                  return Expanded(
                    child: Column(
                      children: [
                        // Scrollable Tabs
                        SizedBox(
                          height: 80,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: cats.length,
                            itemBuilder: (context, index) {
                              final cat = cats[index];
                              final isSelected = index == _selectedIndex;
                              return GestureDetector(
                                onTap: () => setState(() => _selectedIndex = index),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin: const EdgeInsets.only(right: 12),
                                  width: 70,
                                  decoration: BoxDecoration(
                                    color: isSelected ? AppTheme.primaryCyan : Colors.white.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isSelected ? AppTheme.primaryCyan : Colors.white.withValues(alpha: 0.5),
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.category, color: isSelected ? Colors.white : AppTheme.textDark),
                                      const SizedBox(height: 4),
                                      Text(
                                        cat.name,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: isSelected ? Colors.white : AppTheme.textDark,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        
                        const SizedBox(height: 32),
                        
                        // Focused Input for selected category
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(selectedCat.name, style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32)),
                                const SizedBox(height: 16),
                                Text('₹${selectedCat.monthlyAllocation.toStringAsFixed(0)}', 
                                  style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: AppTheme.primaryCyan)),
                                const SizedBox(height: 16),
                                Slider(
                                  value: selectedCat.monthlyAllocation,
                                  max: overallCap > 0 ? overallCap : 50000,
                                  divisions: 100,
                                  activeColor: AppTheme.primaryCyan,
                                  onChanged: (val) async {
                                    setState(() {
                                      selectedCat.monthlyAllocation = val;
                                    });
                                  },
                                  onChangeEnd: (val) async {
                                    final hive = ref.read(hiveServiceProvider);
                                    await hive.updateCategory(selectedCat);
                                    // ignore: unused_result
                                    ref.refresh(selectedCategoriesProvider);
                                  },
                                ),
                                const SizedBox(height: 24),
                                GlassCard(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                                    children: [
                                      _buildSplitStat('Weekly', selectedCat.monthlyAllocation / 4),
                                      _buildSplitStat('Daily', selectedCat.monthlyAllocation / 30),
                                    ],
                                  ),
                                )
                              ],
                            ),
                          ),
                        ),
                        
                        // Summary Strip
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.8),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))
                            ]
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Total Allocated', style: TextStyle(color: AppTheme.textLight)),
                                  Text('₹${totalAllocated.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text('Monthly Cap', style: TextStyle(color: AppTheme.textLight)),
                                  Text('₹${overallCap.toStringAsFixed(0)}', style: TextStyle(
                                    fontWeight: FontWeight.bold, 
                                    fontSize: 20,
                                    color: totalAllocated > overallCap ? Colors.red : AppTheme.textDark,
                                  )),
                                ],
                              )
                            ],
                          ),
                        )
                      ],
                    ),
                  );
                },
                loading: () => const Expanded(child: Center(child: CircularProgressIndicator())),
                error: (e, _) => Expanded(child: Center(child: Text('Error: $e'))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSplitStat(String label, double amount) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textLight)),
        const SizedBox(height: 4),
        Text('₹${amount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ],
    );
  }
}
