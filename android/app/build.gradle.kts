import java.util.Properties
import java.io.FileInputStream
import java.util.Base64
import org.gradle.api.GradleException
import com.android.build.VariantOutput
import com.android.build.gradle.api.ApkVariantOutput

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

fun releaseStoreFile(): File? {
    val storePath = ksProp("storeFile", "DUOYI_KEYSTORE_PATH")
    if (!storePath.isNullOrBlank()) {
        return file(storePath)
    }
    val encoded = System.getenv("DUOYI_KEYSTORE_BASE64")?.trim()
    if (encoded.isNullOrEmpty()) {
        return null
    }
    val target = layout.buildDirectory.file("generated/signing/duoyi-release.jks").get().asFile
    target.parentFile.mkdirs()
    try {
        target.writeBytes(Base64.getMimeDecoder().decode(encoded))
    } catch (e: IllegalArgumentException) {
        throw GradleException("DUOYI_KEYSTORE_BASE64 is not valid base64.", e)
    }
    return target
}

android {
    namespace = "com.duoyi.duoyi"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
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
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        create("release") {
            val store = releaseStoreFile()
            val storePass = ksProp("storePassword", "DUOYI_KEYSTORE_PASSWORD")
            val keyAlias = ksProp("keyAlias", "DUOYI_KEY_ALIAS")
            val keyPass = ksProp("keyPassword", "DUOYI_KEY_PASSWORD")
            if (store != null && storePass != null && keyAlias != null && keyPass != null) {
                storeFile = store
                storePassword = storePass
                this.keyAlias = keyAlias
                keyPassword = keyPass
            }
        }
    }

    buildTypes {
        release {
            val sc = signingConfigs.getByName("release")
            val releaseTaskRequested = gradle.startParameter.taskNames.any {
                it.contains("release", ignoreCase = true)
            }
            if (sc.storeFile != null) {
                signingConfig = sc
            } else if (releaseTaskRequested) {
                throw GradleException(
                    "Release signing is not configured. Set android/key.properties or DUOYI_KEYSTORE_* env vars; refusing to build a release APK with debug signing."
                )
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // Override FlutterPlugin's abiVersionCode * 1000 + versionCode so split APKs stay
    // strictly inside the +10 release stride and below the universal APK (+9).
    @Suppress("DEPRECATION")
    applicationVariants.all {
        val baseCode = flutter.versionCode
        outputs.all {
            val apkOutput = this as? ApkVariantOutput ?: return@all
            val abi = apkOutput.getFilter(VariantOutput.FilterType.ABI)
            val offset = when (abi) {
                "armeabi-v7a" -> 1
                "arm64-v8a" -> 2
                "x86_64" -> 4
                null, "" -> 9
                else -> 0
            }
            apkOutput.versionCodeOverride = baseCode + offset
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("com.google.android.gms:play-services-location:21.3.0")
    testImplementation("junit:junit:4.13.2")
    // Exercise the canonical stored-row boundary with a real JSON parser on the JVM.
    testImplementation("org.json:json:20240303")
    // integration_test exposes an older runner on the target debug classpath.
    // Align it with androidTest for AGP's consistent dependency resolution.
    debugImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
}
