import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/app_settings_service.dart';
import 'dashboard_screen.dart';
import 'sign_up.dart';
import 'verify_email_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.firebaseReady});
  final bool firebaseReady;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  // Tracks which uid has already been synced this session so the Firestore
  // read fires exactly once per login, not on every stream event.
  String? _syncedUid;

  @override
  Widget build(BuildContext context) {
    if (!widget.firebaseReady) {
      return LoginScreen(firebaseReady: widget.firebaseReady);
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          _syncedUid = null; // resetăm la delogare
          return LoginScreen(firebaseReady: widget.firebaseReady);
        }

        if (!user.emailVerified) {
          return const VerifyEmailScreen();
        }

        // Sync display name from Firestore once per session.
        if (user.uid != _syncedUid) {
          _syncedUid = user.uid;
          AppSettings.instance.syncFromFirestore(user.uid);
        }

        return DashboardScreen(firebaseReady: widget.firebaseReady);
      },
    );
  }
}
