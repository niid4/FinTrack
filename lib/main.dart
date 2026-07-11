import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/app_theme.dart';
import 'screens/onboarding_screen.dart';
import 'screens/permissions_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/budget_setup_screen.dart';
import 'screens/ai_dashboard_screen.dart';
import 'providers/providers.dart';
import 'services/hive_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/merchant_resolution_service.dart';
import 'services/transaction_capture_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Try initializing Firebase, but catch errors in case google-services.json is missing
  try {
    await Firebase.initializeApp();
  } catch (e) {
    print("Firebase init failed (likely missing google-services.json): $e");
  }

  final hiveService = HiveService();
  await hiveService.init();

  final resolutionService = MerchantResolutionService(hiveService);
  await resolutionService.init();

  final captureService =
      TransactionCaptureService(hiveService, resolutionService);
  // Drains transactions captured while the app was closed, then listens live.
  // We launch this asynchronously to prevent MethodChannel/EventChannel initialization issues from blocking launch.
  captureService.start().catchError((e) {
    // ignore: avoid_print
    print('Capture service failed to start: $e');
  });

  runApp(
    ProviderScope(
      overrides: [
        hiveServiceProvider.overrideWithValue(hiveService),
      ],
      child: const FinTrackApp(),
    ),
  );
}

class FinTrackApp extends ConsumerWidget {
  const FinTrackApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'FinTrack',
      theme: AppTheme.theme,
      home: const InitialRouter(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class InitialRouter extends ConsumerWidget {
  const InitialRouter({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);

    return profileAsync.when(
      data: (profile) {
        if (profile == null || !profile.hasCompletedOnboarding) {
          return OnboardingScreen(
            onComplete: () {
              ref.invalidate(userProfileProvider);
            },
          );
        }
        // Permission step comes right after onboarding: SMS runtime
        // permission + Notification Listener access (system settings page).
        if (!profile.permissionsRequested) {
          return PermissionsScreen(
            onComplete: () {
              ref.invalidate(userProfileProvider);
            },
          );
        }
        return const MainScreen();
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const DashboardScreen(),
    const AiDashboardScreen(),
    const BudgetSetupScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      extendBody: true,
      bottomNavigationBar: Container(
        margin: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              )
            ]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            backgroundColor: Colors.transparent,
            elevation: 0,
            selectedItemColor: AppTheme.primaryCyan,
            unselectedItemColor: AppTheme.textLight,
            showSelectedLabels: false,
            showUnselectedLabels: false,
            items: const [
              BottomNavigationBarItem(
                  icon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.psychology_rounded), label: 'AI Planner'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.pie_chart_rounded), label: 'Budget'),
            ],
          ),
        ),
      ),
    );
  }
}
