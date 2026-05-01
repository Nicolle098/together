import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/app_settings_service.dart';
import '../theme/app_theme.dart';
import 'dashboard_screen.dart';
import 'verify_email_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.firebaseReady,
  });

  final bool firebaseReady;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isCreatingAccount = false;
  bool _isSubmitting = false;

  Future<void> _sendVerificationEmail(User user) async {
    await user.sendEmailVerification();
  }

  Future<bool> _trySendVerificationEmail(User user) async {
    try {
      await _sendVerificationEmail(user);
      return true;
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return false;
      }

      _showMessage(_friendlyVerificationError(error));
      return false;
    } catch (_) {
      if (!mounted) {
        return false;
      }

      _showMessage('Your account was created, but the verification email could not be sent.');
      return false;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!widget.firebaseReady) {
      _showMessage(
        'Firebase is only configured for Android right now. Add the iOS/web/desktop app in Firebase before using sign-in there.',
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

    try {
      final auth = FirebaseAuth.instance;
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      if (_isCreatingAccount) {
        final userCredential = await auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        final user = userCredential.user;
        if (user != null) {
          final sent = await _trySendVerificationEmail(user);
          if (!sent) {
            return;
          }
        }

        if (!mounted) {
          return;
        }

        _showMessage('Verification email sent. Please verify before logging in.');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const VerifyEmailScreen(),
          ),
        );
        return;
      } else {
        final userCredential = await auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );

        if (!(userCredential.user?.emailVerified ?? false)) {
          if (!mounted) {
            return;
          }

          _showMessage('Please verify your email before continuing.');
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => const VerifyEmailScreen(),
            ),
          );
          return;
        }
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => DashboardScreen(
            firebaseReady: widget.firebaseReady,
          ),
        ),
      );
    } on FirebaseAuthException catch (error) {
      _showMessage(_friendlyError(error));
    } catch (_) {
      _showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _resetPassword() async {
    if (!widget.firebaseReady) {
      _showMessage(
        'Firebase is not ready on this platform yet, so password reset is unavailable here.',
      );
      return;
    }

    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showMessage('Enter your email address first.');
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _showMessage('Password reset email sent.');
    } on FirebaseAuthException catch (error) {
      _showMessage(_friendlyError(error));
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) {
      return 'Email is required.';
    }
    if (!email.contains('@') || !email.contains('.')) {
      return 'Enter a valid email.';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final password = value?.trim() ?? '';
    if (password.isEmpty) {
      return 'Password is required.';
    }
    if (password.length < 6) {
      return 'Use at least 6 characters.';
    }
    return null;
  }

  String _friendlyError(FirebaseAuthException error) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'That email is already being used.';
      case 'invalid-email':
        return 'That email address is not valid.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password is incorrect.';
      case 'weak-password':
        return 'Choose a stronger password.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Try again in a moment.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled in Firebase yet.';
      default:
        return error.message ?? 'Authentication failed.';
    }
  }

  String _friendlyVerificationError(FirebaseAuthException error) {
    switch (error.code) {
      case 'too-many-requests':
        return 'Verification email was blocked for now because too many requests were made. Please try again shortly.';
      case 'quota-exceeded':
        return 'Firebase email quota was reached. Please try again later.';
      case 'network-request-failed':
        return 'Your account was created, but the verification email could not be sent because of a network issue.';
      case 'user-token-expired':
      case 'invalid-user-token':
        return 'Your account was created, but your session expired before the verification email could be sent. Please sign in and try again.';
      default:
        return error.message ??
            'Your account was created, but the verification email could not be sent.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppSettings.instance.lowBattery;
    final titleColor =
        isDark ? TogetherTheme.amoledTextPrimary : TogetherTheme.deepOcean;
    final textTheme = Theme.of(context).textTheme;

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
                  child: Form(
                    key: _formKey,
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
                          _isCreatingAccount
                              ? 'Create Your Account'
                              : 'Welcome Back',
                          style: textTheme.headlineMedium?.copyWith(
                            color: titleColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.firebaseReady
                              ? 'Use Firebase email authentication to sign in or create an account.'
                              : 'Auth is currently enabled for Android. Other platforms still need Firebase app configuration.',
                          style: textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 32),
                        const Text(
                          'Email Address',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          validator: _validateEmail,
                          decoration: const InputDecoration(
                            hintText: 'Enter your email',
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Password',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          validator: _validatePassword,
                          decoration: const InputDecoration(
                            hintText: 'Enter your password',
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _submit,
                            child: Text(
                              _isSubmitting
                                  ? 'Please wait...'
                                  : _isCreatingAccount
                                      ? 'Create Account'
                                      : 'Login',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _isSubmitting
                                ? null
                                : () {
                                    setState(() {
                                      _isCreatingAccount = !_isCreatingAccount;
                                    });
                                  },
                            child: Text(
                              _isCreatingAccount
                                  ? 'Already Have An Account?'
                                  : 'Create Account',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: TextButton(
                            onPressed: _isSubmitting ? null : _resetPassword,
                            child: const Text('Forgot Password?'),
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
      ),
    );
  }
}
