pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositories {
        mavenLocal()
        google()
        mavenCentral()
        maven("https://jitpack.io") {
            content { includeGroup("com.github.mathias8dev.engage-android") }
        }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")

if (providers.gradleProperty("engageUseLocalAndroidSdk").orNull == "true") {
    val configuredDirectory = providers.environmentVariable("ENGAGE_ANDROID_SDK_DIR").orNull
    val localAndroidSdkDirectory = configuredDirectory
        ?.let(::file)
        ?.canonicalFile
        ?: file("../../../../android/engage_android").canonicalFile
    require(localAndroidSdkDirectory.resolve("settings.gradle.kts").isFile) {
        "Local Engage Android repository not found: $localAndroidSdkDirectory"
    }
    includeBuild(localAndroidSdkDirectory) {
        dependencySubstitution {
            val group = "com.github.mathias8dev.engage-android"
            substitute(module("$group:engage-android-core")).using(project(":engage_core"))
            substitute(module("$group:engage-android-push-fcm")).using(project(":engage_push_fcm"))
            substitute(module("$group:engage-android-in-app")).using(project(":engage_in_app"))
            substitute(module("$group:engage-android-message-center")).using(project(":engage_message_center"))
            substitute(module("$group:engage-android-message-center-divkit"))
                .using(project(":engage_message_center_divkit"))
        }
    }
}
