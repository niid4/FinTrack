import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_profile.dart';
import '../providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../screens/phone_auth_screen.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref);
});

class AuthService {
  final Ref ref;
  bool _googleInitialized = false;

  AuthService(this.ref);

  /// google_sign_in 7.x API: the default `GoogleSignIn()` constructor and
  /// `signIn()` were removed (the old code didn't compile against ^7.2.0).
  /// v7 uses a singleton + initialize() + authenticate(), and the credential
  /// is built from the idToken only.
  Future<bool> loginWithGoogle() async {
    try {
      final signIn = GoogleSignIn.instance;
      if (!_googleInitialized) {
        await signIn.initialize();
        _googleInitialized = true;
      }

      final GoogleSignInAccount account = await signIn.authenticate();
      final String? idToken = account.authentication.idToken;
      if (idToken == null) return false;

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      return _completeLogin('google', userCredential.user?.uid ?? 'unknown');
    } on GoogleSignInException catch (e) {
      // Includes user-cancelled and "no OAuth client configured" errors.
      // ignore: avoid_print
      print('Google sign-in error: ${e.code} ${e.description}');
      return false;
    } catch (e) {
      // ignore: avoid_print
      print('Firebase google auth error: $e');
      return false;
    }
  }

  Future<bool> loginWithPhone(BuildContext context) async {
    bool isSuccess = false;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PhoneAuthScreen(
          onVerified: (uid) async {
            await _completeLogin('phone', uid);
            isSuccess = true;
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ),
    );
    return isSuccess;
  }

  /// Offline-first escape hatch: the app is fully functional without a cloud
  /// account (everything is stored locally in Hive; Firestore sync simply
  /// stays off). This prevents the onboarding dead-end when Google/phone
  /// auth isn't configured or has no network.
  Future<bool> continueWithoutAccount() {
    return _completeLogin('local', 'anonymous');
  }

  Future<bool> _completeLogin(String method, String uid) async {
    final hiveService = ref.read(hiveServiceProvider);
    var profile = await hiveService.getProfile();

    if (profile == null) {
      profile = UserProfile()
        ..authMethod = method
        ..mockUserId = uid
        ..hasCompletedOnboarding = false;
      await hiveService.saveProfile(profile);
    } else {
      profile.authMethod = method;
      profile.mockUserId = uid;
      await hiveService.saveProfile(profile);
    }

    ref.invalidate(userProfileProvider);
    return true;
  }
}
