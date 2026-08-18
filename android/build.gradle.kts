import java.io.File
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

group = "io.engage"
val engageFlutterVersion = File(projectDir, "../pubspec.yaml")
    .useLines { lines ->
        lines.first { it.startsWith("version:") }
            .substringAfter(':')
            .trim()
            .substringBefore(' ')
    }
val engageAndroidSdkDefaultVersion = "2.2.1"
val engageAndroidSdkVersion = providers.gradleProperty("engageAndroidSdkVersion")
    .orElse(engageAndroidSdkDefaultVersion)
    .get()
val engageUseMavenLocalAndroidSdk = providers.gradleProperty("engageUseMavenLocalAndroidSdk")
    .map(String::toBoolean)
    .orElse(false)
    .get()
version = findProperty("engageFlutterVersion")?.toString() ?: engageFlutterVersion

buildscript {
    val kotlinVersion = "2.2.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:8.11.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        if (engageUseMavenLocalAndroidSdk) {
            mavenLocal()
        }
        google()
        mavenCentral()
        maven("https://jitpack.io") {
            content { includeGroup("com.github.mathias8dev.engage-android") }
        }
    }
}

plugins {
    id("com.android.library")
    id("kotlin-android")
}

android {
    namespace = "io.engage.engage_flutter"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
        unitTests.all { it.useJUnit() }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    val engageGroup = "com.github.mathias8dev.engage-android"
    implementation("$engageGroup:engage-android-core:$engageAndroidSdkVersion")
    implementation("$engageGroup:engage-android-push-fcm:$engageAndroidSdkVersion")
    implementation("$engageGroup:engage-android-in-app:$engageAndroidSdkVersion")
    implementation("$engageGroup:engage-android-message-center:$engageAndroidSdkVersion")
    implementation("$engageGroup:engage-android-message-center-divkit:$engageAndroidSdkVersion")

    testImplementation("junit:junit:4.13.2")
    testImplementation("androidx.test:core:1.7.0")
    testImplementation("org.robolectric:robolectric:4.16.1")
}
