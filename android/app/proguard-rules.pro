# flutter_secure_storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# flutter_tts
-keep class com.tundralabs.fluttertts.** { *; }

# geolocator
-keep class com.baseflow.geolocator.** { *; }

# permission_handler
-keep class com.baseflow.permissionhandler.** { *; }

# url_launcher
-keep class io.flutter.plugins.urllauncher.** { *; }

# Keep Flutter plugin registrant
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# flutter_gemma / MediaPipe — suppress missing proto classes that are never called at runtime
-dontwarn com.google.mediapipe.proto.CalculatorProfileProto$CalculatorProfile
-dontwarn com.google.mediapipe.proto.GraphTemplateProto$CalculatorGraphTemplate
-keep class com.google.mediapipe.** { *; }

# nearby_connections
-keep class com.pkmnapps.nearby_connections.** { *; }
