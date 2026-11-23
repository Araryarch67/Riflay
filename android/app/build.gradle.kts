plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.riflay.riflay"
    // 37, not Flutter's 36: libusbdac (Direct USB) and the androidx.core it brings are built against it. Only the
    // APIs compiled against; minSdk and targetSdk (which phones run it, and how) stay Flutter's.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "dev.riflay.riflay"
        // `flutter build apk --android-project-arg=riflayDev=true`: "Riflay Dev" (dev.riflay.riflay.dev), installed
        // beside the release one with data of its own, to try a local build on a phone without replacing the app.
        if (project.hasProperty("riflayDev")) applicationIdSuffix = ".dev"
        manifestPlaceholders["appLabel"] = if (project.hasProperty("riflayDev")) "Riflay Dev" else "Riflay"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release key from the environment (the release workflow sets these from
    // repository secrets). Without it, release builds use the debug key, so
    // `flutter run --release` still works locally.
    val releaseKeystore = System.getenv("ANDROID_KEYSTORE_PATH")?.let { file(it) }?.takeIf { it.exists() }
    signingConfigs {
        if (releaseKeystore != null) {
            create("release") {
                storeFile = releaseKeystore
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
            }
        }
    }

    // The dex stored uncompressed: Android then maps it from the APK (file pages it can drop and read again) instead
    // of inflating every class into the app's own memory. With Flutter's minSdk it would be compressed, and an APK
    // installed from GitHub (no Play Store compilation) kept the whole inflated dex in RAM until Android got round to
    // compiling it. The download is a few MB larger.
    packaging {
        dex {
            useLegacyPackaging = false
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (releaseKeystore != null) "release" else "debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Direct USB (DirectUsb.kt): a USB Audio Class driver that streams to the DAC itself, on any phone.
    implementation("com.github.ostrichbat2k:libusbdac:v0.1.0")
    // Its AudioSink / AudioOutput types (no ExoPlayer player is used).
    implementation("androidx.media3:media3-exoplayer:1.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
}

flutter {
    source = "../.."
}

val spotiflacAar = layout.buildDirectory.file("spotiflac/spotiflac.aar")
val buildSpotiflac by tasks.registering(Exec::class) {
    val repo = rootProject.projectDir.parentFile
    inputs.files(fileTree("$repo/tool/spotiflac_bridge") { include("**/*.go", "go.mod", "go.sum") })
    inputs.files(fileTree("$repo/third_party/spotiflac_backend") { include("*.go", "go.mod", "go.sum") })
    inputs.file("$repo/tool/build_spotiflac.py")
    outputs.file(spotiflacAar)
    environment("ANDROID_HOME", android.sdkDirectory.absolutePath)
    environment("ANDROID_NDK_HOME", android.ndkDirectory.absolutePath)
    commandLine(if (System.getProperty("os.name").startsWith("Windows")) "python" else "python3",
        "$repo/tool/build_spotiflac.py", "--target", "android", "--output", spotiflacAar.get().asFile.absolutePath)
}
tasks.named("preBuild").configure { dependsOn(buildSpotiflac) }
dependencies { implementation(files(spotiflacAar).builtBy(buildSpotiflac)) }
