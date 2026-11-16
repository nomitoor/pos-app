# mobile_scanner / MLKit barcode
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**

# CameraX
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**

# Flutter
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# flutter_local_notifications (online order alerts)
-keep class com.dexterous.** { *; }
