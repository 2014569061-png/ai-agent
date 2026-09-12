plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.io.FileInputStream

// 读取 android/key.properties（storeFile 相对本文件所在目录解析）。
// 正式 release 默认必须使用正式签名；仅显式 -PallowDebugSigning=true 才允许本地调试签名。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
val allowDebugSigning = providers.gradleProperty("allowDebugSigning").orNull == "true"
val releaseTaskRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
if (hasReleaseKey) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
if (releaseTaskRequested && !hasReleaseKey && !allowDebugSigning) {
    throw GradleException("Missing android/key.properties. Refusing unsigned/debug-signed release; pass -PallowDebugSigning=true only for local testing.")
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
        // 正式包名固定为 com.nexusagent.app。
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

            // 正式密钥缺失时，仅显式 allowDebugSigning 开关允许调试签名。
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    // PRoot is launched as an executable from applicationInfo.nativeLibraryDir.
    // Keep the ARM64 native payload extracted instead of leaving it only in the APK.
    packaging {
        jniLibs {
            useLegacyPackaging = true
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
