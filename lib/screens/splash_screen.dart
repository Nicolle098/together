import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'dashboard_screen.dart';


class SplashScreen extends StatelessWidget {
  const SplashScreen({
    super.key,
    required this.firebaseReady,
  });

  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth < 380 ? 20.0 : 28.0;
          final logoSize = constraints.maxWidth < 380 ? 170.0 : 210.0;

          return Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  TogetherTheme.cream,
                  Color(0xFFE3EEF2),
                  TogetherTheme.mist,
                ],
              ),
            ),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: 24,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Accessible support for everyday life',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: TogetherTheme.deepOcean,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Container(
                          width: logoSize,
                          height: logoSize,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x2614345C),
                                blurRadius: 60,
                                offset: Offset(0, 16),
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/logo.png',
                            fit: BoxFit.contain,
                            color: TogetherTheme.deepOcean,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'Together',
                          textAlign: TextAlign.center,
                          style: textTheme.displaySmall?.copyWith(
                            color: TogetherTheme.deepOcean,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: const Color(0xFFBCD0D8),
                            ),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.record_voice_over_rounded,
                                color: TogetherTheme.forest,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Inclusive guidance, learning and connection for people who need it most.',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w500,
                                    color: TogetherTheme.ink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (context) => DashboardScreen(
                                  firebaseReady: firebaseReady,
                                ),
                              ),
                            );
                          },
                          child: const Text('Continue As Guest'),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton(
                          onPressed: () {
                            Navigator.of(context).pushReplacementNamed('/auth');
                          },
                          child: const Text('Skip To Sign In'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
