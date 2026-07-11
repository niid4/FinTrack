import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../providers/providers.dart';
import '../services/transaction_capture_service.dart';

/// Real permission step (the old version only showed a SnackBar and was
/// never even reachable in the navigation flow).
///
/// 1. SMS  — standard runtime permission via permission_handler.
/// 2. Notification access — a special access, NOT a runtime permission:
///    it can only be granted on the system settings page, which we open
///    through a native MethodChannel and then re-check on resume.
class PermissionsScreen extends ConsumerStatefulWidget {
  final VoidCallback onComplete;

  const PermissionsScreen({Key? key, required this.onComplete})
      : super(key: key);

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen>
    with WidgetsBindingObserver {
  bool _smsGranted = false;
  bool _notifGranted = false;
  bool _pushNotifGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check when the user comes back from the settings page.
    if (state == AppLifecycleState.resumed) _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final sms = await Permission.sms.status;
    final notif = await TransactionCaptureService.isNotificationAccessGranted();
    final push = await Permission.notification.status;
    if (!mounted) return;
    setState(() {
      _smsGranted = sms.isGranted;
      _notifGranted = notif;
      _pushNotifGranted = push.isGranted;
    });
  }

  Future<void> _requestSms() async {
    final status = await Permission.sms.request();
    if (!mounted) return;
    setState(() => _smsGranted = status.isGranted);
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
  }

  Future<void> _requestPushNotif() async {
    final status = await Permission.notification.request();
    if (!mounted) return;
    setState(() => _pushNotifGranted = status.isGranted);
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
  }

  Future<void> _openNotificationSettings() async {
    await TransactionCaptureService.openNotificationAccessSettings();
  }

  Future<void> _finish() async {
    final hive = ref.read(hiveServiceProvider);
    final profile = await hive.getProfile();
    if (profile != null) {
      profile.permissionsRequested = true;
      await hive.saveProfile(profile);
    }
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: AppTheme.backgroundGradient,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: GlassCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.security,
                        size: 56, color: AppTheme.primaryCyan),
                    const SizedBox(height: 16),
                    const Text(
                      'Automatic capture',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'FinTrack reads your bank SMS and payment-app notifications on-device to log transactions automatically. Nothing is captured without these permissions, and only messages that look like transactions are processed.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textLight),
                    ),
                    const SizedBox(height: 24),
                    _PermissionTile(
                      title: 'SMS access',
                      subtitle: 'Bank debit alerts sent by SMS',
                      granted: _smsGranted,
                      buttonLabel: 'Allow',
                      onPressed: _requestSms,
                    ),
                    const SizedBox(height: 12),
                    _PermissionTile(
                      title: 'Notification access',
                      subtitle:
                          'GPay / PhonePe / bank app alerts — enable "FinTrack Notification Listener" on the settings page that opens',
                      granted: _notifGranted,
                      buttonLabel: 'Open settings',
                      onPressed: _openNotificationSettings,
                    ),
                    const SizedBox(height: 12),
                    _PermissionTile(
                      title: 'Push notifications',
                      subtitle: 'Pops up transaction alerts at the top of the screen',
                      granted: _pushNotifGranted,
                      buttonLabel: 'Allow',
                      onPressed: _requestPushNotif,
                    ),
                    const SizedBox(height: 28),
                    ElevatedButton(
                      onPressed: _finish,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryCyan,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(
                        (_smsGranted && _notifGranted && _pushNotifGranted)
                            ? 'Continue'
                            : 'Continue anyway',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'You can grant these later — until then, transactions can be added manually.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 12, color: AppTheme.textLight),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool granted;
  final String buttonLabel;
  final VoidCallback onPressed;

  const _PermissionTile({
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.buttonLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            granted ? Icons.check_circle : Icons.radio_button_unchecked,
            color: granted ? Colors.green : AppTheme.textLight,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textLight)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!granted)
            TextButton(
              onPressed: onPressed,
              child: Text(buttonLabel,
                  style: const TextStyle(color: AppTheme.primaryCyan)),
            ),
        ],
      ),
    );
  }
}
