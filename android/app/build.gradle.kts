import java.net.URI
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Stockfish 19, official Android arm64 build (tag sf_19, commit edb0d9db6731067ec50ce619ff372b463bc4dd5d).
// Downloaded at build time, checksum-verified and packaged unmodified as lib/arm64-v8a/libstockfish.so.
val stockfishUrl =
    "https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-android-arm64-universal.tar.gz"
val stockfishArchiveSha256 = "ebb24051aa4a222b4daaf049b882ecf1163d370c128fe02316602643f4d5e426"
val stockfishBinarySha256 = "ffd8fc2004d3d19f9fdab95d84c92709aea92e8d3af405eda0b281b23cf1daf8"
val stockfishJniDir = layout.buildDirectory.dir("stockfish/jniLibs")

fun sha256(f: File): String =
    MessageDigest.getInstance("SHA-256").digest(f.readBytes()).joinToString("") { "%02x".format(it) }

val fetchStockfish by tasks.registering {
    description = "Downloads and verifies the official Stockfish Android binary."
    val out = stockfishJniDir.map { it.file("arm64-v8a/libstockfish.so") }
    outputs.file(out)
    doLast {
        val target = out.get().asFile
        if (target.exists() && sha256(target) == stockfishBinarySha256) return@doLast
        val archive = layout.buildDirectory.file("stockfish/stockfish-android-arm64-universal.tar.gz").get().asFile
        archive.parentFile.mkdirs()
        if (!archive.exists() || sha256(archive) != stockfishArchiveSha256) {
            logger.lifecycle("Downloading $stockfishUrl")
            URI(stockfishUrl).toURL().openStream().use {
                Files.copy(it, archive.toPath(), StandardCopyOption.REPLACE_EXISTING)
            }
        }
        check(sha256(archive) == stockfishArchiveSha256) { "Stockfish archive checksum mismatch" }
        copy {
            from(tarTree(resources.gzip(archive))) {
                include("stockfish/stockfish-android-arm64-universal")
                eachFile { path = "libstockfish.so" }
            }
            includeEmptyDirs = false
            into(target.parentFile)
        }
        check(sha256(target) == stockfishBinarySha256) { "Stockfish binary checksum mismatch" }
    }
}

tasks.named("preBuild") { dependsOn(fetchStockfish) }

android {
    namespace = "dev.simpledog1.ply"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.simpledog1.ply"
        // The official Stockfish binary is built for Android 10 (API 29) and newer.
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Stockfish ships for arm64 only: build with --target-platform android-arm64.
    }

    sourceSets {
        getByName("main") { jniLibs.directories.add(stockfishJniDir.get().asFile.path) }
    }

    packaging {
        jniLibs {
            // Extract native libs to disk: Android may only exec files from nativeLibraryDir.
            useLegacyPackaging = true
            // Keep the Stockfish binary byte-identical to the official release.
            keepDebugSymbols += "**/libstockfish.so"
            // Plugins add stray libs for ABIs Ply cannot run on; drop them so the
            // APK only installs on arm64 devices.
            excludes += listOf("lib/armeabi-v7a/**", "lib/x86_64/**", "lib/x86/**")
        }
    }

    buildTypes {
        release {
            // Personal sideloaded build: signed with the local debug key (see README).
            signingConfig = signingConfigs.getByName("debug")
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
