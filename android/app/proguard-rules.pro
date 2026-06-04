# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Google Play Core (referenced by Flutter deferred components)
-dontwarn com.google.android.play.core.**

# Supabase / Ktor
-keep class io.ktor.** { *; }
-dontwarn io.ktor.**

# Kotlin coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}

# JSON serialization
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Sqflite
-keep class com.tekartik.sqflite.** { *; }

# General Flutter Plugin Classes
-keep class io.flutter.plugins.** { *; }
-keep class com.tekartik.sqflite.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.pichillilorenzo.flutter_inappwebview.** { *; }
-keep class vn.hunghd.flutterdownloader.** { *; }
-keep class com.baseflow.permissionhandler.** { *; }
-keep class dev.fluttercommunity.plus.connectivity.** { *; }

# Plugin registration
-keep public class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-keep public class com.tekartik.sqflite.SqflitePlugin { *; }

# Ensure these methods used by Flutter (reflection) are kept
-keepclassmembers class * extends io.flutter.embedding.engine.plugins.FlutterPlugin {
  public <init>(...);
}
