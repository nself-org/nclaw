# nClaw ProGuard Rules

# Keep NClaw native methods (libnclaw FFI)
-keepclasseswithmembernames class org.nself.nclaw.** {
    native <methods>;
}

# Keep data classes used for JSON serialization
-keepclassmembers class org.nself.nclaw.data.** {
    <fields>;
    <init>(...);
}

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }

# Compose
-dontwarn androidx.compose.**

# Keep Kotlin metadata for reflection
-keepattributes *Annotation*
-keepattributes KotlinMetadata
