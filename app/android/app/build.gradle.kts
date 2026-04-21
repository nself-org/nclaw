import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Derive versionCode from git tag: v1.1.0 -> 1*10000 + 1*100 + 0 = 10100
// Falls back to flutter.versionCode if no git tag found.
val gitVersionCode: Int by lazy {
    try {
        val tag = providers.exec {
            commandLine("git", "describe", "--tags", "--abbrev=0")
        }.standardOutput.asText.get().trim()
        val match = Regex("""v?(\d+)\.(\d+)\.(\d+)""").find(tag)
        if (match != null) {
            val (major, minor, patch) = match.destructured
            major.toInt() * 10000 + minor.toInt() * 100 + patch.toInt()
        } else {
            flutter.versionCode
        }
    } catch (_: Exception) {
        flutter.versionCode
    }
}

val gitVersionName: String by lazy {
    try {
        val tag = providers.exec {
            commandLine("git", "describe", "--tags", "--abbrev=0")
        }.standardOutput.asText.get().trim()
        tag.removePrefix("v")
    } catch (_: Exception) {
        flutter.versionName
    }
}

// Load key.properties for release signing (CI writes this from secrets)
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = java.util.Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(java.io.FileInputStream(keyPropertiesFile))
}

android {
    namespace = "com.nself.claw"
    compileSdk = 34
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.nself.claw"
        minSdk = 24
        targetSdk = 34
        versionCode = gitVersionCode
        versionName = gitVersionName
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

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = if (keyPropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    flavorDimensions += "environment"
    productFlavors {
        create("dev") {
            dimension = "environment"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            resValue("string", "app_name", "ɳClaw Dev")
        }
        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".staging"
            versionNameSuffix = "-staging"
            resValue("string", "app_name", "ɳClaw Staging")
        }
        create("prod") {
            dimension = "environment"
            resValue("string", "app_name", "ɳClaw")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
