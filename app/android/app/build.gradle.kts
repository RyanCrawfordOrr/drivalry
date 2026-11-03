import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Flutter forwards every `--dart-define` (including the entries read from
// `--dart-define-from-file=../.env`) to Gradle as the `dart-defines` project
// property: a comma-separated list where each `KEY=VALUE` entry is base64-encoded
// (UTF-8) on its own. Decode it once so manifest placeholders can use the values
// without a second copy of the secrets anywhere under android/.
val dartDefines: Map<String, String> =
    (project.findProperty("dart-defines") as String?)
        ?.split(',')
        ?.filter { it.isNotBlank() }
        ?.mapNotNull { encoded ->
            val entry = runCatching { String(Base64.getDecoder().decode(encoded), Charsets.UTF_8) }
                .getOrNull() ?: return@mapNotNull null
            val separator = entry.indexOf('=')
            if (separator <= 0) null else entry.substring(0, separator) to entry.substring(separator + 1)
        }
        ?.toMap()
        ?: emptyMap()

android {
    namespace = "app.drivalry"
    // permission_handler_android 14.1 ships AAR metadata that demands API 37.
    // Compiling against 37 changes no runtime behaviour (targetSdk is still
    // Flutter's default); AGP 9.0.1 only warns, silenced in gradle.properties.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time and refuses to build without this
        // (checkDebugAarMetadata). Pairs with the coreLibraryDesugaring dependency below.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "app.drivalry"
        // Android 10+ only: the tracking plugin relies on ACCESS_BACKGROUND_LOCATION,
        // ACTIVITY_RECOGNITION and the API 29 foreground-service location type.
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Baked into <meta-data android:name="com.google.android.geo.API_KEY"> by the
        // manifest. Empty when the build runs without --dart-define-from-file so the
        // app still compiles (the map just shows no tiles).
        manifestPlaceholders["googleMapsApiKey"] = dartDefines["GOOGLE_MAPS_API_KEY"] ?: ""
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Fused location, geofencing and the Activity Recognition Transition API.
    implementation("com.google.android.gms:play-services-location:21.3.0")
    // ServiceCompat.startForeground(type), ContextCompat.registerReceiver flags,
    // IntentCompat, NotificationCompat.
    implementation("androidx.core:core-ktx:1.17.0")
    // Java 8+ library desugaring (java.time etc.) required by flutter_local_notifications.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // JVM unit tests for the pure tracking rules (CrashDetector).
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}
