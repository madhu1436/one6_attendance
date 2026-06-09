plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") // <--- MAKE SURE THIS IS HERE
}

android {
    namespace = "com.one6.attedance"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Enable desugaring to support modern Java APIs on older devices
        isCoreLibraryDesugaringEnabled = true

        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }


    defaultConfig {
        applicationId = "com.one6.attedance"

        // Manual override to 21 to support notifications and modern plugins
        minSdk = flutter.minSdkVersion

        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // In Kotlin DSL (.kts), use these exact names:
            isMinifyEnabled = false
            isShrinkResources = false

            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // This library handles the "translation" of Java 8+ features for older Android versions
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
