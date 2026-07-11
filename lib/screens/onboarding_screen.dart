import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';
import '../widgets/glass_card.dart';
import '../theme/app_theme.dart';
import '../providers/providers.dart';
import '../models/user_profile.dart';
import '../models/goal.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  final VoidCallback onComplete;
  const OnboardingScreen({Key? key, required this.onComplete}) : super(key: key);

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  // Onboarding data
  String? _userType;
  double _monthlyIncome = 0.0;
  String? _financialGoal;
  double _savingsTarget = 0.0;
  int _timelineMonths = 3;
  final List<String> _selectedCategories = [];

  // Controllers
  final TextEditingController _incomeController = TextEditingController();
  final TextEditingController _targetController = TextEditingController();
  final TextEditingController _customTimelineController = TextEditingController();

  void _nextPage() {
    if (_currentStep < 6) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() {
        _currentStep++;
      });
    }
  }

  void _prevPage() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() {
        _currentStep--;
      });
    }
  }

  Future<void> _finishSetup() async {
    final hive = ref.read(hiveServiceProvider);
    
    // Save to UserProfile
    final profile = await hive.getProfile() ?? UserProfile();
    profile.userType = _userType;
    profile.monthlyIncome = _monthlyIncome;
    profile.financialGoal = _financialGoal;
    profile.savingsTarget = _savingsTarget;
    profile.timelineMonths = _timelineMonths;
    
    // Calculate Monthly budget
    // e.g. target 50,000 over 10 months => 5,000/month target savings.
    // Monthly budget = Income - Monthly Savings Target
    final double monthlySavingsTarget = _timelineMonths > 0 ? (_savingsTarget / _timelineMonths) : 0.0;
    profile.overallMonthlyBudget = (_monthlyIncome - monthlySavingsTarget).clamp(0.0, double.infinity);
    profile.hasCompletedOnboarding = true;
    
    await hive.saveProfile(profile);

    // Save as a Main Goal
    final goal = Goal()
      ..id = 'main_savings_goal'
      ..title = _financialGoal ?? 'Savings Goal'
      ..targetAmount = _savingsTarget
      ..targetDate = DateTime.now().add(Duration(days: _timelineMonths * 30))
      ..currentProgress = 0.0
      ..status = 'active'
      ..reallocationFrequency = 'weekly';
    await hive.saveGoal(goal);

    // Initialize category selections
    final categories = await hive.getAllCategories();
    // Default allocations: divide overall monthly budget equally among selected categories.
    final double allocation = _selectedCategories.isNotEmpty 
        ? (profile.overallMonthlyBudget / _selectedCategories.length)
        : 0.0;

    for (var cat in categories) {
      if (_selectedCategories.contains(cat.name)) {
        cat.isSelected = true;
        cat.monthlyAllocation = allocation;
      } else {
        cat.isSelected = false;
        cat.monthlyAllocation = 0.0;
      }
      await hive.updateCategory(cat);
    }

    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: AppTheme.backgroundGradient,
        child: SafeArea(
          child: Column(
            children: [
              // Top Progress Indicator
              if (_currentStep > 0) _buildProgressHeader(),
              
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildLoginStep(),
                    _buildUserTypeStep(),
                    _buildIncomeStep(),
                    _buildGoalStep(),
                    _buildTargetStep(),
                    _buildTimelineStep(),
                    _buildCategoriesStep(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressHeader() {
    final double progress = _currentStep / 6.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: AppTheme.textLight, size: 20),
                onPressed: _prevPage,
              ),
              Text(
                'Step $_currentStep of 6',
                style: const TextStyle(
                  color: AppTheme.textLight,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 48), // Spacer to balance back button
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryCyan),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginStep() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'FinTrack',
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Frosted, effortless financial agent.',
            style: TextStyle(color: AppTheme.textLight, fontSize: 16),
          ),
          const SizedBox(height: 64),
          GlassCard(
            onTap: () async {
              final success = await ref.read(authServiceProvider).loginWithGoogle();
              if (success) {
                _nextPage();
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Google sign-in failed. Please try again.')),
                );
              }
            },
            height: 60,
            child: const Center(
              child: Text(
                'Continue with Google',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 16),
          GlassCard(
            onTap: () async {
              final success = await ref.read(authServiceProvider).loginWithPhone(context);
              if (success) _nextPage();
            },
            height: 60,
            child: const Center(
              child: Text(
                'Continue with Phone Number',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () async {
              await ref.read(authServiceProvider).continueWithoutAccount();
              _nextPage();
            },
            child: const Text(
              'Continue Offline First',
              style: TextStyle(color: AppTheme.primaryCyan, fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserTypeStep() {
    final options = ['Student', 'Working Professional', 'Freelancer', 'Business Owner', 'Other'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Which best describes you?',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 32),
          ...options.map((opt) => Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: GlassCard(
                  onTap: () {
                    setState(() => _userType = opt);
                    _nextPage();
                  },
                  height: 64,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Text(
                        opt,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildIncomeStep() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'What is your average monthly income or allowance?',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            child: TextField(
              controller: _incomeController,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                prefixText: '₹ ',
                prefixStyle: TextStyle(fontSize: 24, color: AppTheme.primaryCyan, fontWeight: FontWeight.bold),
                border: InputBorder.none,
                hintText: 'Enter amount',
                hintStyle: TextStyle(color: Colors.white24, fontSize: 24),
              ),
            ),
          ),
          const SizedBox(height: 48),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(_incomeController.text.replaceAll(',', '')) ?? 0.0;
              if (val > 0) {
                setState(() => _monthlyIncome = val);
                _nextPage();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid income amount')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryCyan,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Continue', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalStep() {
    final goals = ['Build Savings', 'Buy Something Specific', 'Reduce Spending', 'Create Emergency Fund', 'Other'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'What is your main financial goal right now?',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 32),
          ...goals.map((goal) => Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: GlassCard(
                  onTap: () {
                    setState(() => _financialGoal = goal);
                    _nextPage();
                  },
                  height: 64,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Text(
                        goal,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildTargetStep() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'How much money would you like to save?',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            child: TextField(
              controller: _targetController,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                prefixText: '₹ ',
                prefixStyle: TextStyle(fontSize: 24, color: AppTheme.primaryCyan, fontWeight: FontWeight.bold),
                border: InputBorder.none,
                hintText: 'Enter amount',
                hintStyle: TextStyle(color: Colors.white24, fontSize: 24),
              ),
            ),
          ),
          const SizedBox(height: 48),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(_targetController.text.replaceAll(',', '')) ?? 0.0;
              if (val > 0) {
                setState(() => _savingsTarget = val);
                _nextPage();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid savings target')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryCyan,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Continue', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineStep() {
    final presets = [3, 6, 12, 24];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'When would you like to achieve this goal?',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 32),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: presets.map((m) {
              return ChoiceChip(
                label: Text('$m Months', style: const TextStyle(color: Colors.white)),
                selected: _timelineMonths == m,
                selectedColor: AppTheme.primaryCyan,
                backgroundColor: Colors.white.withOpacity(0.08),
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _timelineMonths = m;
                      _customTimelineController.clear();
                    });
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          const Text(
            'Or specify custom months:',
            style: TextStyle(color: AppTheme.textLight, fontSize: 15),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            child: TextField(
              controller: _customTimelineController,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Enter custom months',
                hintStyle: TextStyle(color: Colors.white24),
              ),
              onChanged: (val) {
                final m = int.tryParse(val) ?? 0;
                if (m > 0) {
                  setState(() => _timelineMonths = m);
                }
              },
            ),
          ),
          const SizedBox(height: 48),
          ElevatedButton(
            onPressed: () {
              if (_timelineMonths > 0) {
                _nextPage();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please select or specify a valid timeline')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryCyan,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Continue', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesStep() {
    final categories = ['Food', 'Shopping', 'Travel', 'Entertainment', 'Education', 'Bills', 'Healthcare', 'Other'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          const Text(
            'Major Spending Categories',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 8),
          const Text(
            'Select up to 3 categories to configure your core budget.',
            style: TextStyle(color: AppTheme.textLight, fontSize: 15),
          ),
          const SizedBox(height: 32),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 2.2,
              ),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final name = categories[index];
                final isSelected = _selectedCategories.contains(name);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedCategories.remove(name);
                      } else {
                        if (_selectedCategories.length < 3) {
                          _selectedCategories.add(name);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('You can select a maximum of 3 categories')),
                          );
                        }
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primaryCyan : Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? AppTheme.primaryCyanGlow : Colors.white.withOpacity(0.15),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : AppTheme.textDark,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              if (_selectedCategories.isNotEmpty) {
                _finishSetup();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please select at least 1 category')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryCyan,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Finish Setup', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
