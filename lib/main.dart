import 'package:flutter/foundation.dart'; 
import 'package:flutter/material.dart'; 
import 'data/community_seeder.dart'; 
import 'screens/auth_gate.dart'; 
import 'screens/splash_screen.dart'; 
import 'services/app_settings_service.dart'; 
import 'services/firebase_bootstrap.dart';
import 'services/hazard_notification_service.dart'; 
import 'theme/app_theme.dart'; 

Future<void> main() async { 
  WidgetsFlutterBinding.ensureInitialized(); 
  await HazardNotificationService.initialize(); 
  await AppSettings.instance.load();
  final firebaseReady = await FirebaseBootstrap.initialize();
  if (firebaseReady) CommunitySeeder.seedIfNeeded(); 
  runApp(Together(firebaseReady: firebaseReady)); 
}

class Together extends StatelessWidget { 
  const Together({
    super.key,
    required this.firebaseReady, 
  });
  final bool firebaseReady; 
  @override
  Widget build(BuildContext context) { 
    ErrorWidget.builder = (details) { 
      return Scaffold( 
        body: Center(
          child: Padding( 
            padding: const EdgeInsets.all(24), 
            child: Text(
              kDebugMode
                  ? details.exceptionAsString() 
                  : 'Something went wrong.', 
              textAlign: TextAlign.center, 
            ),
          ),
        ),
      );
    };

  return ListenableBuilder( 
      listenable: AppSettings.instance, 
      builder: (context, _) { 
        final settings = AppSettings.instance; 
        final ThemeData activeTheme; 
        if (settings.lowBattery) {
          activeTheme = TogetherTheme.buildAmoledTheme(); 
        } else if (settings.highContrast) { 
          activeTheme = TogetherTheme.buildHighContrastTheme(); 
        } else {
          activeTheme = TogetherTheme.buildTheme(); 
        }
        return MediaQuery(
          data: MediaQueryData.fromView(
            View.of(context),
          ).copyWith(
            textScaler: TextScaler.linear(settings.textScaleFactor), 
          ),
          child: MaterialApp( 
            debugShowCheckedModeBanner: false, 
            title: 'Together', 
            theme: activeTheme, 
            home: SplashScreen(firebaseReady: firebaseReady), 
            routes: {
              '/auth': (context) => AuthGate(firebaseReady: firebaseReady), 
            },
          ),
        );
      },
    );
  }
}
