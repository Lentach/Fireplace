import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Load key.properties if it exists (release signing)
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(FileInputStream(keyPropertiesFile))
}

// HARD GATE: a release build without a real keystore must FAIL LOUDLY, never
// silently fall back to debug signing (a debug-signed "release" looks shippable
// but is not: Play rejects it and its signature can't ever be upgraded in place).
// Debug/profile builds and non-release tasks are unaffected.
val releaseRequested = gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
if (releaseRequested && !keyPropertiesFile.exists()) {
    throw GradleException(
        "Release build requested but android/key.properties is missing. " +
        "Create the release keystore first — see docs/runbooks/android-release.md " +
        "(copy android/key.properties.example to android/key.properties and fill it in)."
    )
}

android {
    namespace = "com.fireplace.app"
    // Pinned explicitly (= Flutter 3.44.6 defaults) so an SDK upgrade cannot
    // silently change backup semantics, Keystore behavior, or 16KB compliance.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        if (keyPropertiesFile.exists()) {
            create("release") {
                keyAlias = keyProperties["keyAlias"] as String
                keyPassword = keyProperties["keyPassword"] as String
                storeFile = file(keyProperties["storeFile"] as String)
                storePassword = keyProperties["storePassword"] as String
            }
        }
    }

    defaultConfig {
        applicationId = "com.fireplace.app"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // The hard gate above guarantees key.properties exists whenever a
            // Release task runs; the fallback only keeps configuration of
            // non-release invocations (e.g. assembleDebug) from crashing.
            signingConfig = if (keyPropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
