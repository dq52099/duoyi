import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Read keystore properties from android/key.properties (local) or env (CI).
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) {
        FileInputStream(file).use { load(it) }
    }
}

fun ksProp(name: String, env: String): String? =
    (keystoreProperties[name] as? String) ?: System.getenv(env)

android {
    namespace = "com.duoyi.duoyi"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.duoyi.duoyi"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val storePath = ksProp("storeFile", "DUOYI_KEYSTORE_PATH")
            val storePass = ksProp("storePassword", "DUOYI_KEYSTORE_PASSWORD")
            val keyAlias = ksProp("keyAlias", "DUOYI_KEY_ALIAS")
            val keyPass = ksProp("keyPassword", "DUOYI_KEY_PASSWORD")
            if (storePath != null && storePass != null && keyAlias != null && keyPass != null) {
                storeFile = file(storePath)
                storePassword = storePass
                this.keyAlias = keyAlias
                keyPassword = keyPass
            }
        }
    }

    buildTypes {
        release {
            val sc = signingConfigs.getByName("release")
            signingConfig = if (sc.storeFile != null) sc else signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
