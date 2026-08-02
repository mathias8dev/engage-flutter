import org.jetbrains.kotlin.gradle.dsl.JvmTarget

group = "io.engage"
version = "0.1.0"

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
        mavenLocal()
        google()
        mavenCentral()
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
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    val engageSdkVersion = findProperty("engageSdkVersion")?.toString() ?: "0.1.0-SNAPSHOT"
    implementation("io.engage:engage-core:$engageSdkVersion")
    implementation("io.engage:engage-push-fcm:$engageSdkVersion")
    implementation("io.engage:engage-in-app:$engageSdkVersion")
    implementation("io.engage:engage-message-center:$engageSdkVersion")
    implementation("io.engage:engage-message-center-divkit:$engageSdkVersion")
}
