import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

class AiDashboardScreen extends ConsumerStatefulWidget {
  const AiDashboardScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<AiDashboardScreen> createState() => _AiDashboardScreenState();
}

class _AiDashboardScreenState extends ConsumerState<AiDashboardScreen> {
  bool _isLoading = false;
  bool _emulatorConfigured = false;
  Map<String, dynamic>? _insightsData;

  Future<void> _fetchAiInsights() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final profile = await ref.read(hiveServiceProvider).getProfile();
      final String userId = profile?.mockUserId ?? 'anonymous';

      final functionsInstance = FirebaseFunctions.instance;
      if (kDebugMode && !_emulatorConfigured) {
        // Point to the local machine running the emulator.
        functionsInstance.useFunctionsEmulator('10.9.0.140', 5001);
        _emulatorConfigured = true;
      }

      final HttpsCallable callable = functionsInstance.httpsCallable('getAiInsights');
      final result = await callable.call({
        'userId': userId,
      });

      if (result.data != null) {
        setState(() {
          _insightsData = Map<String, dynamic>.from(result.data);
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error fetching AI insights: $e");
      }
      // Set default fallback mock data if firebase/ollama is offline
      setState(() {
        _insightsData = {
          "suggestedBudgets": [
            {"category": "Food", "amount": 4000},
            {"category": "Travel", "amount": 2000},
            {"category": "Entertainment", "amount": 1500},
            {"category": "Shopping", "amount": 2500},
            {"category": "Emergency Savings", "amount": 5000}
          ],
          "spendingInsights": [
            "Food spending is your biggest expense category.",
            "Based on your current trend, you will reach your goal in 8.3 months.",
            "Skipping two food delivery orders per week saves approximately ₹1,200/month."
          ],
          "savingsProjection": "Based on your income, you are projected to save ₹56,000 this year and reach your goal on time.",
          "reallocationAdvice": "Food was overspent by ₹500. Entertainment was underspent by ₹800. Shifting available budget intelligently to keep your savings on track."
        };
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: AppTheme.backgroundGradient,
        child: SafeArea(
          child: Stack(
            children: [
              // Premium Background glow effects
              Positioned(
                top: -50,
                left: -50,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.accentPurple.withOpacity(0.1),
                  ),
                ),
              ),
              Positioned(
                bottom: 80,
                right: -80,
                child: Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.primaryCyan.withOpacity(0.1),
                  ),
                ),
              ),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Bar
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'AI Planner',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        if (_insightsData != null && !_isLoading)
                          IconButton(
                            icon: const Icon(Icons.refresh, color: AppTheme.primaryCyan),
                            onPressed: _fetchAiInsights,
                          ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: _isLoading
                        ? _buildLoadingState()
                        : (_insightsData == null ? _buildInitialState() : _buildInsightsDashboard()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInitialState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.primaryCyan.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.primaryCyan.withOpacity(0.2), width: 2),
              ),
              child: const Icon(Icons.psychology_outlined, size: 64, color: AppTheme.primaryCyanGlow),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Meet your Financial Planning Agent',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 12),
          const Text(
            'FinTrack AI will analyze your income, goals, timeline, and actual transactions using Ollama to generate an optimized monthly budget plan and actionable spending insights.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textLight, fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: 48),
          ElevatedButton(
            onPressed: _fetchAiInsights,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryCyan,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              shadowColor: AppTheme.primaryCyanGlow.withOpacity(0.4),
              elevation: 8,
            ),
            child: const Text(
              'Generate AI Budget Plan & Insights',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(
              strokeWidth: 6,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryCyan),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Analyzing profile & transactions...',
            style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Ollama AI Agent is computing custom advice',
            style: TextStyle(color: AppTheme.textLight, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightsDashboard() {
    final suggestedBudgets = _insightsData!['suggestedBudgets'] as List<dynamic>? ?? [];
    final spendingInsights = _insightsData!['spendingInsights'] as List<dynamic>? ?? [];
    final savingsProjection = _insightsData!['savingsProjection']?.toString() ?? '';
    final reallocationAdvice = _insightsData!['reallocationAdvice']?.toString() ?? '';

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // 1. Savings Forecast Card
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.timeline_rounded, color: AppTheme.primaryCyanGlow),
                  const SizedBox(width: 12),
                  const Text(
                    'Savings Goal Forecast',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                savingsProjection,
                style: const TextStyle(color: AppTheme.textLight, fontSize: 14, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. Suggested Category Budgets
        if (suggestedBudgets.isNotEmpty) ...[
          const Text(
            'AI Recommended Allocations',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
          ),
          const SizedBox(height: 12),
          Column(
            children: suggestedBudgets.map((b) {
              final cat = b['category']?.toString() ?? 'Other';
              final amt = double.tryParse(b['amount']?.toString() ?? '0') ?? 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: GlassCard(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        cat,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                      ),
                      Text(
                        '₹${amt.toStringAsFixed(0)}/mo',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primaryCyanGlow),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],

        // 3. Reallocation Advice
        if (reallocationAdvice.isNotEmpty) ...[
          const Text(
            'Dynamic Reallocations',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
          ),
          const SizedBox(height: 12),
          GlassCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accentPurple.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.swap_horiz, color: AppTheme.accentPurple),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Weekly Shift Suggestion',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        reallocationAdvice,
                        style: const TextStyle(color: AppTheme.textLight, fontSize: 13, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // 4. Actionable Insights
        if (spendingInsights.isNotEmpty) ...[
          const Text(
            'Spending Insights',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
          ),
          const SizedBox(height: 12),
          Column(
            children: spendingInsights.map((insight) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: GlassCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lightbulb_outline, color: AppTheme.primaryCyanGlow, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          insight.toString(),
                          style: const TextStyle(color: AppTheme.textLight, fontSize: 13, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 80),
      ],
    );
  }
}
