plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.io.FileInputStream

// 读取 android/key.properties（storeFile 相对本文件所在目录解析）。
// 缺失时回退 debug 签名，保证 `flutter run --release` 仍可用。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.nexusagent.app"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications 需要 Java 8+ API 脱糖。
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: 正式包名（发布后不可修改）。当前为默认值 com.nexusagent.app。
        // 如需更换请在首次上架前修改并重新出包。
        applicationId = "com.nexusagent.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // [体积优化] 仅打包现代 Android 设备使用的 ARM64 ABI，减少原生库体积
        ndk {
            abiFilters.clear()
            abiFilters.add("arm64-v8a")
        }
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        debug {
            // 调试包装在独立包名（com.nexusagent.app.debug）下，与正式签名包并存，
            // 热重载调试不影响已安装的正式版，也不会被误分享。
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
        release {
            // [体积优化] 开启 R8 代码压缩与资源收缩，删除未使用的原生代码与资源
            isMinifyEnabled = true
            isShrinkResources = true

            // 优先使用正式签名（key.properties）；缺失时回退 debug 签名。
            signingConfig = if (hasReleaseKey) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
