import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/app_transaction.dart';
import '../models/merchant_rule.dart';
import '../providers/providers.dart';
import '../services/merchant_resolution_service.dart';
import '../services/transaction_capture_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/categorize_bar.dart';
import 'history_screen.dart';

// Category icon & color mapping for premium UI
const _categoryMeta = <String, _CatMeta>{
  'Food':          _CatMeta(Icons.restaurant_rounded,   Color(0xFFFF6B6B)),
  'Shopping':      _CatMeta(Icons.shopping_bag_rounded,  Color(0xFF4ECDC4)),
  'Travel':        _CatMeta(Icons.flight_takeoff_rounded, Color(0xFF45B7D1)),
  'Entertainment': _CatMeta(Icons.movie_rounded,         Color(0xFFDDA0DD)),
  'Bills':         _CatMeta(Icons.receipt_long_rounded,  Color(0xFFFFA07A)),
  'Education':     _CatMeta(Icons.school_rounded,        Color(0xFF87CEEB)),
  'Healthcare':    _CatMeta(Icons.local_hospital_rounded, Color(0xFF98FB98)),
  'Groceries':     _CatMeta(Icons.local_grocery_store_rounded, Color(0xFFFFD700)),
  'Personal':      _CatMeta(Icons.person_rounded,        Color(0xFFE6E6FA)),
  'Savings':       _CatMeta(Icons.savings_rounded,       Color(0xFF00CED1)),
  'Other':         _CatMeta(Icons.more_horiz_rounded,    Color(0xFFB0C4DE)),
  'Friend':        _CatMeta(Icons.people_rounded,        Color(0xFFFF69B4)),
  'Rent':          _CatMeta(Icons.home_rounded,          Color(0xFFDEB887)),
  'Gift':          _CatMeta(Icons.card_giftcard_rounded, Color(0xFFFF1493)),
  'Transportation':_CatMeta(Icons.directions_car_rounded, Color(0xFF87CEFA)),
};

class _CatMeta {
  final IconData icon;
  final Color color;
  const _CatMeta(this.icon, this.color);
}

_CatMeta _getCatMeta(String name) {
  return _categoryMeta[name] ?? const _CatMeta(Icons.category_rounded, Color(0xFFB0C4DE));
}

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with TickerProviderStateMixin {
  String _timeRange = 'Daily'; // Daily, Weekly, Monthly
  AppTransaction? _newlyCapturedTx;
  bool _showToast = false;
  bool _isBottomSheetOpen = false;
  StreamSubscription<int>? _openCategorizeSub;

  // Toast animation controllers
  late AnimationController _toastController;
  late Animation<Offset> _toastSlide;
  late Animation<double> _toastFade;

  @override
  void initState() {
    super.initState();
    _toastController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
      reverseDuration: const Duration(milliseconds: 400),
    );
    _toastSlide = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _toastController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    ));
    _toastFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _toastController, curve: Curves.easeOut),
    );

    // "Other" (or the body) tapped on the system categorize notification:
    // open the existing in-app categorize bottom sheet for free-text entry.
    _openCategorizeSub =
        TransactionCaptureService.openCategorizeRequests.listen((txKey) {
      if (!mounted) return;
      final tx = ref.read(hiveServiceProvider).transactionBox.get(txKey);
      if (tx == null || !tx.isUncategorized) return;
      if (_isBottomSheetOpen) return;
      _isBottomSheetOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showCategorizationBottomSheet(context, tx);
      });
    });
  }

  @override
  void dispose() {
    _toastController.dispose();
    _openCategorizeSub?.cancel();
    super.dispose();
  }

  void _showAnimatedToast(AppTransaction tx) {
    setState(() {
      _newlyCapturedTx = tx;
      _showToast = true;
    });
    _toastController.forward();
    HapticFeedback.mediumImpact();

    Future.delayed(const Duration(seconds: 12), () {
      if (mounted && _newlyCapturedTx?.key == tx.key && _showToast) {
        _dismissToast();
      }
    });
  }

  void _dismissToast() {
    _toastController.reverse().then((_) {
      if (mounted) setState(() => _showToast = false);
    });
  }

  void _simulateTransaction() async {
    final hive = ref.read(hiveServiceProvider);
    final resolutionService = MerchantResolutionService(hive);

    // Simulate a random merchant transaction
    final merchants = ['Zomato', 'Amazon', 'Uber', 'Airtel', 'Unknown Merchant'];
    final selectedMerchant = (merchants..shuffle()).first;
    final amounts = [153.00, 299.00, 450.00, 899.00, 120.00];
    final selectedAmount = (amounts..shuffle()).first;

    final tx = AppTransaction()
      ..amount = selectedAmount
      ..merchant = selectedMerchant
      ..date = DateTime.now()
      ..isUncategorized = true;

    // Use the full resolution chain: dictionary → fuzzy → keywords → cloud
    try {
      final rule = await resolutionService.resolveMerchant(selectedMerchant);
      if (rule != null) {
        tx.customCategory = rule.category;
        tx.isUncategorized = false;
      }
    } catch (_) {
      // Resolution is best-effort
    }

    await hive.saveTransaction(tx);

    // Show notification with 2.5s delay to mock the SMS flow
    await Future.delayed(const Duration(milliseconds: 2500));
    try {
      if (tx.isUncategorized) {
        // Same rich heads-up categorize notification the real capture
        // path posts — so the notification flow is testable from here.
        await TransactionCaptureService.postCategorizeNotification(
          hive,
          tx,
          sourceLabel: 'UPI',
        );
      } else {
        final platform = MethodChannel('com.example.fintrack/methods');
        await platform.invokeMethod('showNotification', {
          'title': '✅ ₹${tx.amount.toStringAsFixed(0)} → ${tx.customCategory}',
          'body':
              '₹${tx.amount.toStringAsFixed(0)} spent at ${tx.merchant} auto-categorized as ${tx.customCategory}.',
        });
      }
    } catch (_) {}
  }

  void _showCategorizationBottomSheet(BuildContext context, AppTransaction tx) {
    _isBottomSheetOpen = true;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return _CategorizationSheet(
          transaction: tx,
          ref: ref,
          onDone: () {
            Navigator.pop(context);
          },
        );
      },
    ).then((_) {
      _isBottomSheetOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);
    final txStream = ref.watch(transactionsStreamProvider);
    final categoriesAsync = ref.watch(selectedCategoriesProvider);

    // New uncategorized transactions are now handled by the system heads-up
    // notification (posted natively by TransactionCaptureService), with the
    // pending list below as the in-app fallback — so no auto-popup here.
    // Auto-categorized ones still get the in-app confirmation toast.
    ref.listen<AsyncValue<List<AppTransaction>>>(transactionsStreamProvider, (prev, next) {
      if (next.value == null) return;
      final prevList = prev?.value ?? [];
      final nextList = next.value!;
      if (prevList.isEmpty) return;

      final prevIds = prevList.map((t) => t.key).toSet();
      final newTxs = nextList.where((t) => !prevIds.contains(t.key)).toList();

      if (newTxs.isNotEmpty) {
        final latestTx = newTxs.first;
        if (!latestTx.isUncategorized) {
          _showAnimatedToast(latestTx);
        }
      }
    });

    return Scaffold(
      body: Container(
        decoration: AppTheme.backgroundGradient,
        child: SafeArea(
          child: Stack(
            children: [
              // Premium Background glow effects
              Positioned(
                top: -80,
                right: -80,
                child: Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.primaryCyan.withOpacity(0.12),
                  ),
                ),
              ),
              Positioned(
                bottom: 100,
                left: -100,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.accentPurple.withOpacity(0.08),
                  ),
                ),
              ),

              // Main scrolling screen content
              Column(
                children: [
                  // Custom styled Top Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Dashboard',
                          style: Theme.of(context).textTheme.displayLarge?.copyWith(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withOpacity(0.08)),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.history_rounded, color: AppTheme.primaryCyan),
                                tooltip: 'Transaction History',
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => const HistoryScreen()),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withOpacity(0.08)),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.add_shopping_cart, color: AppTheme.primaryCyan),
                                tooltip: 'Simulate Transaction',
                                onPressed: _simulateTransaction,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Stylish Segmented Control
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: GlassCard(
                      padding: const EdgeInsets.all(4),
                      borderRadius: 30,
                      child: Row(
                        children: ['Daily', 'Weekly', 'Monthly'].map((range) {
                          final isSelected = _timeRange == range;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _timeRange = range),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.fastOutSlowIn,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppTheme.primaryCyan.withOpacity(0.15)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(26),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppTheme.primaryCyan.withOpacity(0.25)
                                        : Colors.transparent,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    range,
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                      color: isSelected ? AppTheme.primaryCyanGlow : AppTheme.textLight,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // In-app fallback: pending uncategorized transactions the
                  // user hasn't handled from the notification (dismissed it,
                  // notifications disabled, etc.). Skipped ones stay hidden.
                  txStream.maybeWhen(
                    data: (transactions) {
                      final pending = transactions
                          .where((t) => t.isUncategorized && !t.isSkipped)
                          .take(3)
                          .toList();
                      if (pending.isEmpty) return const SizedBox.shrink();
                      return Column(
                        children: pending
                            .map((t) => CategorizeBar(
                                  key: ValueKey('categorize_${t.key}'),
                                  transaction: t,
                                  onCategorized: () {
                                    if (mounted) setState(() {});
                                  },
                                ))
                            .toList(),
                      );
                    },
                    orElse: () => const SizedBox.shrink(),
                  ),

                  Expanded(
                    child: txStream.when(
                      data: (transactions) {
                        return profileAsync.when(
                          data: (profile) {
                            if (_timeRange == 'Daily') {
                              return _buildDailyView(profile, transactions);
                            } else if (_timeRange == 'Weekly') {
                              return _buildWeeklyView(profile, transactions);
                            } else {
                              return _buildMonthlyView(profile, transactions, categoriesAsync);
                            }
                          },
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (_, __) => const SizedBox(),
                        );
                      },
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (_, __) => const SizedBox(),
                    ),
                  ),
                ],
              ),

              // ============================================================
              //  PREMIUM ANIMATED IN-APP TOAST
              // ============================================================
              if (_showToast && _newlyCapturedTx != null)
                Positioned(
                  top: 60,
                  left: 12,
                  right: 12,
                  child: SlideTransition(
                    position: _toastSlide,
                    child: FadeTransition(
                      opacity: _toastFade,
                      child: Dismissible(
                        key: Key(_newlyCapturedTx!.key.toString()),
                        direction: DismissDirection.up,
                        onDismissed: (_) {
                          setState(() => _showToast = false);
                        },
                        child: _buildPremiumToast(_newlyCapturedTx!),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  //  Premium Toast Widget
  // -------------------------------------------------------------------
  Widget _buildPremiumToast(AppTransaction tx) {
    final meta = _getCatMeta(tx.customCategory ?? 'Other');

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: meta.color.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: meta.color.withOpacity(0.15),
            blurRadius: 30,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF0F172A).withOpacity(0.92),
                  const Color(0xFF1E293B).withOpacity(0.88),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top row: icon + status + close
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            meta.color.withOpacity(0.3),
                            meta.color.withOpacity(0.1),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: meta.color.withOpacity(0.3),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Icon(meta.icon, color: meta.color, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.accentGreen.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppTheme.accentGreen.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.auto_awesome,
                                    color: AppTheme.accentGreen, size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  'Auto-Categorized',
                                  style: TextStyle(
                                    color: AppTheme.accentGreen,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tx.merchant,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _dismissToast,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, color: Colors.white54, size: 16),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Bottom row: amount + category + edit
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '₹${tx.amount.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: meta.color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: meta.color.withOpacity(0.25)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(meta.icon, color: meta.color, size: 16),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  tx.customCategory ?? 'Other',
                                  style: TextStyle(
                                    color: meta.color,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          _dismissToast();
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _showCategorizationBottomSheet(context, tx);
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.12)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit_rounded, color: Colors.white70, size: 14),
                              SizedBox(width: 4),
                              Text('Edit', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Daily View ---
  Widget _buildDailyView(dynamic profile, List<AppTransaction> transactions) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    
    // Total spent today
    final double todaySpent = transactions
        .where((tx) => !tx.date.isBefore(todayStart))
        .fold(0.0, (sum, tx) => sum + tx.amount);
    
    final double monthlyBudget = profile?.overallMonthlyBudget ?? 15000.0;
    final double dailyBudget = monthlyBudget / 30.0;

    // Category top 3
    final categoryTotals = <String, double>{};
    for (final tx in transactions) {
      if (tx.customCategory != null) {
        categoryTotals[tx.customCategory!] = (categoryTotals[tx.customCategory!] ?? 0.0) + tx.amount;
      }
    }
    final sortedCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topCategories = sortedCategories.take(3).toList();

    final circleFill = dailyBudget > 0 ? (todaySpent / dailyBudget).clamp(0.0, 1.0) : 0.0;
    final isLimitExceeded = todaySpent >= dailyBudget;

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // (Savings Goal bar removed — circle is the hero daily element)

        // 2. Daily Budget Circle (Large Progress Indicator)
        GlassCard(
          child: Column(
            children: [
              const Text(
                'Today\'s Spending Limit',
                style: TextStyle(color: AppTheme.textLight, fontSize: 15, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 24),
              Center(
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: Stack(
                    children: [
                      Center(
                        child: SizedBox(
                          width: 180,
                          height: 180,
                          child: CircularProgressIndicator(
                            value: circleFill,
                            strokeWidth: 14,
                            backgroundColor: Colors.white10,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isLimitExceeded ? Colors.redAccent : AppTheme.primaryCyan,
                            ),
                          ),
                        ),
                      ),
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('Spent', style: TextStyle(color: Colors.white54, fontSize: 13)),
                            const SizedBox(height: 4),
                            Text(
                              '₹${todaySpent.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                color: isLimitExceeded ? Colors.redAccent : Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Limit: ₹${dailyBudget.toStringAsFixed(0)}',
                              style: const TextStyle(color: AppTheme.textLight, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (isLimitExceeded)
                const Text(
                  'Warning: Daily budget limit reached!',
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14),
                )
              else
                Text(
                  'You have ₹${(dailyBudget - todaySpent).clamp(0.0, dailyBudget).toStringAsFixed(0)} left for today.',
                  style: const TextStyle(color: AppTheme.primaryCyanGlow, fontSize: 14, fontWeight: FontWeight.w500),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 3. Top Categories
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Top Categories Today',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              ),
              const SizedBox(height: 16),
              if (topCategories.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.0),
                  child: Center(
                    child: Text('No categorized spending recorded.', style: TextStyle(color: Colors.white30)),
                  ),
                )
              else
                ...topCategories.map((entry) {
                  final double limit = monthlyBudget / 3.0; // simple division
                  final double percent = limit > 0 ? (entry.value / limit).clamp(0.0, 1.0) : 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                            Text('₹${entry.value.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryCyanGlow)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(
                            value: percent,
                            backgroundColor: Colors.white10,
                            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accentPurple),
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
            ],
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  // --- Weekly View ---
  Widget _buildWeeklyView(dynamic profile, List<AppTransaction> transactions) {
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    
    // Weekly spending details
    final double weeklySpent = transactions
        .where((tx) => !tx.date.isBefore(sevenDaysAgo))
        .fold(0.0, (sum, tx) => sum + tx.amount);

    final double savingsTarget = profile?.savingsTarget ?? 50000.0;
    final double timelineMonths = (profile?.timelineMonths ?? 12).toDouble();
    final double monthlyTarget = savingsTarget / timelineMonths;
    final double weeklyTarget = monthlyTarget / 4.33;

    final double weeklyIncome = (profile?.monthlyIncome ?? 20000.0) / 4.33;
    final double weeklyBudget = weeklyIncome - weeklyTarget;
    
    final double weeklySaved = (weeklyIncome - weeklySpent).clamp(0.0, weeklyTarget);
    final double progressPercent = weeklyTarget > 0 ? (weeklySaved / weeklyTarget) : 0.0;

    // Category breakdown
    final categoryTotals = <String, double>{};
    for (final tx in transactions) {
      if (tx.date.isAfter(sevenDaysAgo) && tx.customCategory != null) {
        categoryTotals[tx.customCategory!] = (categoryTotals[tx.customCategory!] ?? 0.0) + tx.amount;
      }
    }

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // 1. Weekly Savings Progress
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Weekly Savings Progress',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                  ),
                  Text(
                    '${(progressPercent * 100).toStringAsFixed(0)}% Saved',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primaryCyanGlow),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '₹${weeklySaved.toStringAsFixed(0)} Achieved',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                  Text(
                    'Goal: ₹${weeklyTarget.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 14, color: AppTheme.textLight),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progressPercent,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryCyan),
                  minHeight: 8,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. Weekly Spending Limit
        GlassCard(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Weekly Spent (7 Days)', style: TextStyle(color: AppTheme.textLight, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('₹${weeklySpent.toStringAsFixed(0)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Weekly Budget Limit', style: TextStyle(color: AppTheme.textLight, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('₹${weeklyBudget.toStringAsFixed(0)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryCyanGlow)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 3. Weekly Category Breakdown
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Weekly Category Breakdown',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              ),
              const SizedBox(height: 16),
              if (categoryTotals.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.0),
                  child: Center(
                    child: Text('No spending this week.', style: TextStyle(color: Colors.white30)),
                  ),
                )
              else
                ...categoryTotals.entries.map((entry) {
                  final double percent = weeklyBudget > 0 ? (entry.value / weeklyBudget).clamp(0.0, 1.0) : 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                            Text('₹${entry.value.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryCyanGlow)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(
                            value: percent,
                            backgroundColor: Colors.white10,
                            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accentPurple),
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 4. Weekly AI Insight Quick View
        GlassCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryCyan.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.insights, color: AppTheme.primaryCyanGlow),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Weekly AI Insights', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                    const SizedBox(height: 6),
                    Text(
                      weeklySpent > weeklyBudget
                          ? 'You have overspent your weekly limit by ₹${(weeklySpent - weeklyBudget).toStringAsFixed(0)}. AI suggests reallocating ₹800 from Entertainment next week.'
                          : 'You are under budget this week! Saving ₹50/day will let you reach your target 2 weeks early.',
                      style: const TextStyle(color: AppTheme.textLight, fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  // --- Monthly View ---
  Widget _buildMonthlyView(dynamic profile, List<AppTransaction> transactions, AsyncValue<List<dynamic>> categoriesAsync) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    
    // Monthly spent
    final double monthlySpent = transactions
        .where((tx) => !tx.date.isBefore(monthStart))
        .fold(0.0, (sum, tx) => sum + tx.amount);

    final double savingsTarget = profile?.savingsTarget ?? 50000.0;
    final double timelineMonths = (profile?.timelineMonths ?? 12).toDouble();
    final double monthlyTarget = savingsTarget / timelineMonths;
    
    final double monthlyIncome = profile?.monthlyIncome ?? 20000.0;
    
    final double monthlySaved = (monthlyIncome - monthlySpent).clamp(0.0, monthlyTarget);
    final double progressPercent = monthlyTarget > 0 ? (monthlySaved / monthlyTarget) : 0.0;

    // Monthly category spends mapping
    final spentByCategory = <String, double>{};
    for (final tx in transactions) {
      if (tx.date.isAfter(monthStart) && tx.customCategory != null) {
        spentByCategory[tx.customCategory!] = (spentByCategory[tx.customCategory!] ?? 0.0) + tx.amount;
      }
    }

    // Chart buckets
    final buckets = _buildChartBuckets(transactions);

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // 1. Monthly Goal Progress
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Monthly Target Progress',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                  ),
                  Text(
                    '${(progressPercent * 100).toStringAsFixed(0)}% Saved',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primaryCyanGlow),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '₹${monthlySaved.toStringAsFixed(0)} Achieved',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                  Text(
                    'Goal: ₹${monthlyTarget.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 14, color: AppTheme.textLight),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progressPercent,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryCyan),
                  minHeight: 8,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. Spending Trends Chart
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Monthly Spending Trend',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 180,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: buckets.fold<double>(0.0, (max, b) => b.total > max ? b.total : max) * 1.2 + 10.0,
                    barTouchData: BarTouchData(enabled: true),
                    titlesData: FlTitlesData(
                      show: true,
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (val, meta) {
                            final i = val.toInt();
                            if (i >= 0 && i < buckets.length) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  buckets[i].label,
                                  style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
                                ),
                              );
                            }
                            return const Text('');
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(show: false),
                    barGroups: List.generate(buckets.length, (index) {
                      return BarChartGroupData(
                        x: index,
                        barRods: [
                          BarChartRodData(
                            toY: buckets[index].total,
                            gradient: const LinearGradient(
                              colors: [AppTheme.primaryCyan, AppTheme.accentPurple],
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                            ),
                            width: 16,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 3. Category Budgets & Analytics
        const Text(
          'Category Budget Performance',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
        ),
        const SizedBox(height: 12),
        categoriesAsync.when(
          data: (cats) {
            final activeCats = cats.where((c) => c.isSelected).toList();
            if (activeCats.isEmpty) {
              return const Center(child: Text('No active budgets.', style: TextStyle(color: Colors.white30)));
            }
            return Column(
              children: activeCats.map((cat) {
                final spent = spentByCategory[cat.name] ?? 0.0;
                final allocation = cat.monthlyAllocation > 0 ? cat.monthlyAllocation : 1000.0;
                final percent = (spent / allocation).clamp(0.0, 1.0);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(cat.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                            Text('₹${spent.toStringAsFixed(0)} / ₹${allocation.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryCyanGlow)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: percent,
                            backgroundColor: Colors.white10,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              percent >= 1.0 ? Colors.redAccent : AppTheme.primaryCyan,
                            ),
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const SizedBox(),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  List<_ChartBucket> _buildChartBuckets(List<AppTransaction> txs) {
    final now = DateTime.now();
    if (_timeRange == 'Daily') {
      final start = DateTime(now.year, now.month, now.day);
      final labels = ['0-4', '4-8', '8-12', '12-16', '16-20', '20-24'];
      final totals = List<double>.filled(6, 0);
      for (final tx in txs) {
        if (!tx.date.isBefore(start)) {
          final slot = (tx.date.hour ~/ 4).clamp(0, 5);
          totals[slot] += tx.amount;
        }
      }
      return List.generate(6, (i) => _ChartBucket(labels[i], totals[i]));
    }
    if (_timeRange == 'Monthly') {
      final totals = List<double>.filled(5, 0);
      for (final tx in txs) {
        if (tx.date.month == now.month && tx.date.year == now.year) {
          final week = ((tx.date.day - 1) ~/ 7).clamp(0, 4);
          totals[week] += tx.amount;
        }
      }
      return List.generate(5, (i) => _ChartBucket('W${i + 1}', totals[i]));
    }
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final totals = List<double>.filled(7, 0);
    for (final tx in txs) {
      if (!tx.date.isBefore(monday)) {
        final diff = tx.date.difference(monday).inDays;
        if (diff >= 0 && diff < 7) totals[diff] += tx.amount;
      }
    }
    return List.generate(7, (i) => _ChartBucket(days[i], totals[i]));
  }
}

class _ChartBucket {
  final String label;
  final double total;
  _ChartBucket(this.label, this.total);
}

// =======================================================================
//  PREMIUM CATEGORIZATION BOTTOM SHEET
// =======================================================================
class _CategorizationSheet extends StatefulWidget {
  final AppTransaction transaction;
  final WidgetRef ref;
  final VoidCallback onDone;

  const _CategorizationSheet({
    required this.transaction,
    required this.ref,
    required this.onDone,
  });

  @override
  State<_CategorizationSheet> createState() => _CategorizationSheetState();
}

class _CategorizationSheetState extends State<_CategorizationSheet>
    with SingleTickerProviderStateMixin {
  bool _showCustomField = false;
  bool _rememberChoice = true;
  final TextEditingController _customController = TextEditingController();
  late AnimationController _sheetAnimController;
  late Animation<double> _sheetScale;

  @override
  void initState() {
    super.initState();
    _sheetAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _sheetScale = CurvedAnimation(
      parent: _sheetAnimController,
      curve: Curves.easeOutBack,
    );
    _sheetAnimController.forward();
  }

  @override
  void dispose() {
    _sheetAnimController.dispose();
    _customController.dispose();
    super.dispose();
  }

  Future<void> _selectCategory(String catName) async {
    final tx = widget.transaction;
    tx.isUncategorized = false;
    tx.isSkipped = false;
    tx.customCategory = catName;

    final hive = widget.ref.read(hiveServiceProvider);
    await hive.saveTransaction(tx);

    // Learn: save merchant rule so next time it's auto-categorized
    if (_rememberChoice && tx.merchant.isNotEmpty && tx.merchant != 'Unknown') {
      final merchantKey = tx.merchant.toLowerCase().trim();
      final existing = hive.getMerchantRule(merchantKey);
      if (existing == null) {
        final rule = MerchantRule()
          ..merchantName = merchantKey
          ..category = catName
          ..resolvedBy = 'user';
        await hive.saveMerchantRule(rule);
      }
    }

    // Dismiss the system categorize notification if still showing
    final k = tx.key;
    if (k is int) {
      TransactionCaptureService.cancelCategorizeNotification(k);
    }

    HapticFeedback.lightImpact();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final tx = widget.transaction;
    final categoriesAsync = widget.ref.watch(allCategoriesProvider);

    return ScaleTransition(
      scale: _sheetScale,
      alignment: Alignment.bottomCenter,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(32),
            topRight: Radius.circular(32),
          ),
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(32),
            topRight: Radius.circular(32),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF1E293B).withOpacity(0.95),
                    const Color(0xFF0F172A).withOpacity(0.98),
                  ],
                ),
              ),
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom + 32,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Gradient drag handle
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.primaryCyan, AppTheme.accentPurple],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Header: Merchant + Amount
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.accentPurple.withOpacity(0.3),
                              AppTheme.primaryCyan.withOpacity(0.1),
                            ],
                          ),
                          border: Border.all(
                            color: AppTheme.accentPurple.withOpacity(0.3),
                          ),
                        ),
                        child: const Icon(
                          Icons.store_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tx.merchant,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.accentRed.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppTheme.accentRed.withOpacity(0.25),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.help_outline_rounded,
                                      color: AppTheme.accentRed, size: 12),
                                  SizedBox(width: 4),
                                  Text(
                                    'Needs categorization',
                                    style: TextStyle(
                                      color: AppTheme.accentRed,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [AppTheme.primaryCyanGlow, AppTheme.accentPurple],
                        ).createShader(bounds),
                        child: Text(
                          '₹${tx.amount.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Quick picks — same row as the system notification
                  const Text(
                    'Quick picks',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppTheme.textLight,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children:
                        TransactionCaptureService.quickPicks.map((catName) {
                      final meta = _getCatMeta(catName);
                      return GestureDetector(
                        onTap: () => _selectCategory(catName),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: meta.color.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: meta.color.withOpacity(0.2),
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(meta.icon, color: meta.color, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                catName,
                                style: TextStyle(
                                  color: meta.color,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  const Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 14),

                  // All categories
                  const Text(
                    'All categories',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppTheme.textLight,
                    ),
                  ),
                  const SizedBox(height: 10),
                  categoriesAsync.when(
                    data: (categories) {
                      final list = categories.map((c) => c.name).toSet().toList();
                      if (!list.contains('Other')) list.add('Other');

                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: list.map((catName) {
                          final meta = _getCatMeta(catName);
                          return GestureDetector(
                            onTap: () => _selectCategory(catName),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: meta.color.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: meta.color.withOpacity(0.2),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: meta.color.withOpacity(0.05),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(meta.icon, color: meta.color, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    catName,
                                    style: TextStyle(
                                      color: meta.color,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, __) => const SizedBox(),
                  ),

                  // Custom field
                  if (_showCustomField) ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _customController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Enter custom category...',
                              hintStyle: const TextStyle(color: Colors.white30),
                              isDense: true,
                              enabledBorder: OutlineInputBorder(
                                borderSide:
                                    const BorderSide(color: Colors.white24),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: const BorderSide(
                                    color: AppTheme.primaryCyan),
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryCyan,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                          ),
                          onPressed: () {
                            final label = _customController.text.trim();
                            if (label.isNotEmpty) {
                              _selectCategory(label);
                            }
                          },
                          child: const Icon(Icons.check, color: Colors.white),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Remember toggle + custom button
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(
                              () => _rememberChoice = !_rememberChoice),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: _rememberChoice
                                  ? AppTheme.accentGreen.withOpacity(0.08)
                                  : Colors.white.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _rememberChoice
                                    ? AppTheme.accentGreen.withOpacity(0.25)
                                    : Colors.white.withOpacity(0.08),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _rememberChoice
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  color: _rememberChoice
                                      ? AppTheme.accentGreen
                                      : Colors.white38,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'Remember for ${tx.merchant}',
                                    style: TextStyle(
                                      color: _rememberChoice
                                          ? AppTheme.accentGreen
                                          : Colors.white54,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _showCustomField = !_showCustomField),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.1),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _showCustomField
                                    ? Icons.close_rounded
                                    : Icons.edit_rounded,
                                color: Colors.white54,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _showCustomField ? 'Cancel' : 'Custom',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
