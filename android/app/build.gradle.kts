plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.pos_app"
    // 37 is required by flutter_local_notifications. Compile-time only:
    // minSdk/targetSdk (which phones and behaviour) are unchanged.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (order alerts).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.example.pos_app"
        minSdk = flutter.minSdkVersion  // ← change from flutter.minSdkVersion to 21
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Needed for the per-flavor app_name below.
    buildFeatures {
        resValues = true
    }

    // Two installs side by side, each with its own data on the phone:
    //   dev  → com.example.pos_app.dev, "Urban Thread Dev"
    //   prod → com.example.pos_app,     "Urban Thread" (the shop's real app)
    // Build with --flavor dev|prod (see README / .vscode/launch.json).
    flavorDimensions += "env"
    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            resValue("string", "app_name", "Urban Thread Dev")
        }
        create("prod") {
            dimension = "env"
            resValue("string", "app_name", "Urban Thread")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
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

dependencies {
    // FileProvider, used to share bill PDFs with WhatsApp.
    implementation("androidx.core:core-ktx:1.13.1")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
