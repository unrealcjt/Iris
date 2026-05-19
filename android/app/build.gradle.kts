plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.iris"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

//    kotlinOptions {
//        jvmTarget = JavaVersion.VERSION_17.toString()
//    }
    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.iris"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
//        ndk { abiFilters.add("arm64-v8a") }
    }

    buildTypes {
        release {
            // 确保启用了签名配置（如果你配置了的话）
            signingConfig = signingConfigs.getByName("debug")

            // 🛠️ 关键：确保有下面这一行来加载 proguard-rules.pro
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // 加入以下 Lint 配置
    @Suppress("DEPRECATION")
    lintOptions {
        isAbortOnError = false
        isCheckReleaseBuilds = false
    }
}

flutter {
    source = "../.."
}

// 告诉 R8/Proguard：不要因为找不到某些类而中断编译
project.extensions.extraProperties.set("android.r8.failOnMissingClasses", "false")
