import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/app_settings_service.dart';
import '../theme/app_theme.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  static const int _resendCooldownSeconds = 30;

  Timer? _pollTimer;
  Timer? _cooldownTimer;
  int _cooldownRemaining = 0;
  bool _isRefreshing = false;
  bool _isResending = false;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _sendVerificationEmail(User user) async {
    await user.sendEmailVerification();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _refreshUser(autoTriggered: true);
    });
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() {
      _cooldownRemaining = _resendCooldownSeconds;
    });

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_cooldownRemaining <= 1) {
        timer.cancel();
        setState(() {
          _cooldownRemaining = 0;
        });
        return;
      }

      setState(() {
        _cooldownRemaining -= 1;
      });
    });
  }

  Future<void> _signOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _refreshUser({bool autoTriggered = false}) async {
    if (_isRefreshing) {
      return;
    }

    setState(() {
      _isRefreshing = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      await user?.reload();

      if (!mounted) {
        return;
      }

      final refreshedUser = FirebaseAuth.instance.currentUser;
      if (refreshedUser?.emailVerified ?? false) {
        _pollTimer?.cancel();
        _cooldownTimer?.cancel();
        Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
        return;
      }

      if (!autoTriggered) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email is not verified yet.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _resendEmail(BuildContext context) async {
    if (_cooldownRemaining > 0 || _isResending) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in again before resending the verification email.'),
        ),
      );
      return;
    }

    setState(() {
      _isResending = true;
    });

    try {
      await _sendVerificationEmail(user);
      _startCooldown();

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification email sent again.')),
      );
    } on FirebaseAuthException catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Could not resend verification email.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppSettings.instance.lowBattery;
    final titleColor =
        isDark ? TogetherTheme.amoledTextPrimary : TogetherTheme.deepOcean;
    final textTheme = Theme.of(context).textTheme;
    final resendLabel = _cooldownRemaining > 0
        ? 'Resend Email ($_cooldownRemaining)'
        : 'Resend Email';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 8,
                shadowColor: Colors.black12,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(36),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Image.asset(
                          'assets/logo.png',
                          scale: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Verify Your Email',
                        style: textTheme.headlineMedium?.copyWith(
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'We sent a verification email to your inbox. Open it, verify your account, then return here. This screen checks automatically every few seconds.',
                        style: textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isRefreshing
                              ? null
                              : () => _refreshUser(autoTriggered: false),
                          child: Text(
                            _isRefreshing
                                ? 'Checking...'
                                : 'I Verified My Email',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: (_cooldownRemaining > 0 || _isResending)
                              ? null
                              : () => _resendEmail(context),
                          child: Text(
                            _isResending ? 'Sending...' : resendLabel,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          onPressed: () => _signOut(context),
                          child: const Text('Back To Login'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
