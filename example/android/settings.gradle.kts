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
            content { includeGroup("com.github.mathias8dev") }
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
    val localAndroidSdkDirectory = file("../../../../android").canonicalFile
    val localModules = mapOf(
        "engage_core" to "com.github.mathias8dev:engage-android-core",
        "engage_push_fcm" to "com.github.mathias8dev:engage-android-push-fcm",
        "engage_in_app" to "com.github.mathias8dev:engage-android-in-app",
        "engage_message_center" to "com.github.mathias8dev:engage-android-message-center",
        "engage_message_center_divkit" to "com.github.mathias8dev:engage-android-message-center-divkit",
    )
    localModules.forEach { (directory, coordinate) ->
        val moduleDirectory = localAndroidSdkDirectory.resolve(directory)
        require(moduleDirectory.resolve("settings.gradle.kts").isFile) {
            "Local Engage Android module not found: $moduleDirectory"
        }
        includeBuild(moduleDirectory) {
            dependencySubstitution {
                substitute(module(coordinate)).using(project(":"))
            }
        }
    }
}
