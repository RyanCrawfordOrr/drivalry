# Release shrinking (R8) keep rules for plugins that reach into their own
# classes by reflection. Flutter and most plugins ship consumer rules; these
# cover the ones that do not.

# flutter_local_notifications serialises scheduled notifications with Gson.
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-keepattributes Signature, *Annotation*, EnclosingMethod, InnerClasses

# Our own Kotlin bridges are reached from the Flutter engine by name.
-keep class app.drivalry.** { *; }

# WebRTC (convoy radio) loads its JNI classes by name.
-keep class org.webrtc.** { *; }
-keep class com.cloudwebrtc.webrtc.** { *; }

# Android Auto templates are instantiated by the host through reflection.
-keep class androidx.car.app.** { *; }
