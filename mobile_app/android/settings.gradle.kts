pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        maven { url = uri("https://jitpack.io") }
        mavenLocal()
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
        maven { url = uri("https://repo.huaweicloud.com/repository/maven/") }
        maven { url = uri("https://repo.huaweicloud.com/repository/google/") }
        maven { url = uri("https://repo.huaweicloud.com/repository/maven-public/") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
    }
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.5.2" apply false
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") version("4.3.15") apply false
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
}

include(":app")

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        maven { url = uri("https://jitpack.io") }
        google()
        mavenCentral()
        mavenLocal()
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
        maven {
            url = uri("https://repo.huaweicloud.com/repository/maven/")
            content {
                excludeGroupByRegex("com\\.github\\..*")
            }
        }
        maven {
            url = uri("https://repo.huaweicloud.com/repository/google/")
            content {
                excludeGroupByRegex("com\\.github\\..*")
            }
        }
        maven { url = uri("https://github.com/jitsi/jitsi-maven-repository/raw/master/releases") }
    }
}
