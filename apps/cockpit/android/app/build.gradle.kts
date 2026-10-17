plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.boardwalklabs.octopilot"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Registered in Firebase (octopilot-ai-7b29e) under this ID.
        applicationId = "com.boardwalklabs.octopilot"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // sherpa-onnx (OctoNotes captions) and onnxruntime (Pocket TTS) both
    // bundle libonnxruntime.so; one copy goes in. It must be sherpa's newer
    // build: the older plugin only asks for ORT API 14, which it still serves.
    // sherpa's libraries are added as this module's own, so they're the
    // copies picked (a module's own files come before its dependencies').
    sourceSets["main"].jniLibs.srcDirs(
        listOf("arm64", "armeabi", "x86", "x86_64")
            .mapNotNull { rootProject.findProject(":sherpa_onnx_android_$it")?.projectDir }
            .map { File(it, "src/main/jniLibs") },
    )
    packaging {
        jniLibs {
            pickFirsts += setOf("lib/*/libonnxruntime.so", "lib/*/libsherpa-onnx-c-api.so", "lib/*/libsherpa-onnx-cxx-api.so")
        }
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

flutter {
    source = "../.."
}

// Firebase reads google-services.json, which is kept out of git (public
// repo). Builds without it still work, just without sign-in (dev user).
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}
