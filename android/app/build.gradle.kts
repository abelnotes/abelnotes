import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing config. Non-secret fields (keyAlias, storeFile path) come
// from android/key.properties (gitignored — see android/.gitignore); the
// PASSWORD itself is fetched from the OS keyring (libsecret / gnome-keyring)
// via `secret-tool`, never stored in a plaintext file. Falls back to a
// `storePassword=` line in key.properties when the keyring lookup fails
// (e.g. a CI runner with no keyring daemon) — set one there if needed on
// such a machine. Absent key.properties entirely -> debug signing, so a
// fresh checkout without any of this still builds for local dev/testing.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasKeystoreProperties = keystorePropertiesFile.exists()
if (hasKeystoreProperties) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

fun secretToolLookup(vararg attributes: String): String? = try {
    val process = ProcessBuilder("secret-tool", "lookup", *attributes).start()
    val output = process.inputStream.bufferedReader().readText().trim()
    process.waitFor()
    output.ifEmpty { null }
} catch (e: Exception) {
    null
}

val keystorePassword: String? = if (hasKeystoreProperties) {
    secretToolLookup("service", "abelnotes-keystore", "key", "upload")
        ?: (keystoreProperties["storePassword"] as String?)
} else null

android {
    namespace = "app.abelnotes.notes"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.abelnotes.notes"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasKeystoreProperties && keystorePassword != null) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystorePassword
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystorePassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasKeystoreProperties && keystorePassword != null) {
                signingConfigs.getByName("release")
            } else {
                // No keystore on this machine — fall back to debug signing
                // so local `flutter build`/`flutter run --release` still
                // works. NEVER upload an app-signed-with-debug-keys build
                // to Play Store (it gets rejected) — that's exactly what
                // happened before this file had a real signing config.
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
