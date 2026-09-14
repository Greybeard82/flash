import java.io.FileInputStream
import java.util.Properties

// Release signing credentials, read from android/key.properties, which is
// gitignored and must never be committed. Absent on a fresh clone and in CI —
// that is fine for debug and profile builds, and a release build fails loudly
// below rather than quietly signing with the debug key.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}

fun keystoreProperty(name: String): String? =
    (keystoreProperties[name] as String?)?.trim()?.takeIf { it.isNotEmpty() }

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The three SDK levels are pinned, not inherited.
//
// They used to read flutter.compileSdkVersion / minSdkVersion /
// targetSdkVersion, which are defaults defined in the Flutter SDK
// (packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt), not in
// this repo. That meant upgrading Flutter could move this app's minSdk,
// compileSdk and targetSdk with no line changing here and nothing in review
// showing it.
//
// targetSdk is the one that matters. API 37 makes adaptive UI mandatory on
// large screens: tablets and foldables can no longer opt out of resizability,
// which is exactly what PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY in the
// manifest is holding up, and the tablet landscape lock goes with it. Left
// inherited, that would have arrived in a Flutter upgrade with no related
// change in the diff, and the first symptom would have been a Lenovo Tab M11
// rendering a layout the PRD describes as decided but not built.
//
// Moving any of these is now a deliberate edit. See PRD-Flash.md for the date.
android {
    namespace = "io.getflash.app"
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

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.getflash.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // 24 = Android 7.0. What flutter.minSdkVersion already resolved to;
        // pinned so a Flutter upgrade cannot raise it and drop devices
        // silently.
        minSdk = 24
        // Do not raise to 37 without a portrait tablet layout. See the comment
        // above the android block.
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val storeFilePath = keystoreProperty("storeFile")
            if (storeFilePath != null) {
                storeFile = file(storeFilePath)
                storePassword = keystoreProperty("storePassword")
                keyAlias = keystoreProperty("keyAlias")
                keyPassword = keystoreProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

// A release build must never be signed with the debug key. Shipping one is
// effectively unrecoverable: Play and every installed device treat the signing
// key as the app's identity, so an update signed by a different key is rejected
// and the key cannot be rotated for an existing listing.
//
// Checked against the task graph rather than at configuration time, so debug and
// profile builds — which legitimately have no release credentials — are
// unaffected. Profile task names contain "Profile", not "Release".
gradle.taskGraph.whenReady {
    val buildingRelease = allTasks.any { task ->
        task.name.contains("Release") && task.project.path == project.path
    }
    if (!buildingRelease) return@whenReady

    val problems = mutableListOf<String>()

    if (!keystorePropertiesFile.exists()) {
        problems += "android/key.properties does not exist"
    } else {
        if (keystoreProperty("storeFile") == null) problems += "storeFile is blank"
        if (keystoreProperty("keyAlias") == null) problems += "keyAlias is blank"
        if (keystoreProperty("storePassword") == null) {
            problems += "storePassword is blank — open android/key.properties and fill it in"
        }
        if (keystoreProperty("keyPassword") == null) {
            problems += "keyPassword is blank — open android/key.properties and fill it in"
        }
        val storeFilePath = keystoreProperty("storeFile")
        if (storeFilePath != null && !file(storeFilePath).exists()) {
            problems += "storeFile does not exist at: $storeFilePath"
        }
    }

    val releaseSigning = android.signingConfigs.findByName("release")
    val debugStore = android.signingConfigs.findByName("debug")?.storeFile
    if (releaseSigning?.storeFile == null) {
        problems += "the release signingConfig has no keystore"
    } else if (debugStore != null && releaseSigning.storeFile == debugStore) {
        problems += "the release signingConfig resolves to the DEBUG keystore"
    }

    if (problems.isNotEmpty()) {
        throw GradleException(
            buildString {
                appendLine()
                appendLine("=".repeat(72))
                appendLine("RELEASE BUILD ABORTED — refusing to sign with the debug key.")
                appendLine("=".repeat(72))
                problems.forEach { appendLine("  * $it") }
                appendLine()
                appendLine("Fix: open android/key.properties and fill in storePassword and")
                appendLine("keyPassword. That file is gitignored and must never be committed.")
                appendLine("=".repeat(72))
            }
        )
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // ML Kit GenAI Prompt API — on-device Gemini Nano (Pixel 8+, Android 14+)
    implementation("com.google.mlkit:genai-prompt:1.0.0-beta1")
}
