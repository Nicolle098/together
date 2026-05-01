import 'package:firebase_core/firebase_core.dart'; // Imports the core Firebase package needed to initialise the SDK
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb; // Imports only the platform-detection helpers we need

import '../firebase_options.dart'; // Imports the auto-generated Firebase config for each platform

class FirebaseBootstrap { // A helper class that handles starting Firebase safely
  const FirebaseBootstrap._(); // Private constructor — prevents anyone from creating an instance of this class

  static Future<bool> initialize() async { // A static method; call it without creating an object: FirebaseBootstrap.initialize()
    try { // Wrap everything in a try-catch so any Firebase error is caught instead of crashing the app
      if (kIsWeb) { // Check whether the app is running in a web browser
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform, // Use the web-specific Firebase settings from firebase_options.dart
        );
        return true; // Firebase started successfully on web
      }

      switch (defaultTargetPlatform) { // Check which native platform the app is running on
        case TargetPlatform.android:
          await Firebase.initializeApp(); // On Android, Firebase reads its config from google-services.json automatically
          return true; // Firebase started successfully on Android
        case TargetPlatform.iOS:   // Firebase on iOS is not wired up in this project
        case TargetPlatform.macOS: // Firebase on macOS is not wired up in this project
        case TargetPlatform.windows: // Firebase on Windows is not wired up in this project
        case TargetPlatform.linux:   // Firebase on Linux is not wired up in this project
        case TargetPlatform.fuchsia: // Firebase on Fuchsia is not wired up in this project
          return false; // Tell the app that Firebase is not available on this platform
      }
    } catch (_) { // If any error is thrown during initialisation (e.g. missing config file)
      return false; // Safely report failure instead of letting the app crash
    }
  }
}
