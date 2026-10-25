plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "it.pietrodefilippis.tkclienti"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "it.pietrodefilippis.tkclienti"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // chiave fissa di tk-clienti (la stessa della vecchia app Kotlin), FUORI dal repo: in CI arriva dal segreto
    // ANDROID_KEYSTORE_B64 (percorso nella variabile ANDROID_KEYSTORE). La firma non cambia tra una versione e
    // l'altra, così gli aggiornamenti si installano sopra e i dati restano. Senza la variabile (rami senza
    // segreto, chi compila dal sorgente) = chiave di debug di Flutter.
    val chiaveTk = System.getenv("ANDROID_KEYSTORE")?.takeIf { it.isNotBlank() && file(it).exists() }
    signingConfigs {
        if (chiaveTk != null) {
            create("tk") {
                storeFile = file(chiaveTk)
                storePassword = "android"
                keyAlias = "androiddebugkey"
                keyPassword = "android"
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("tk") ?: signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // file collegati su Drive/Dropbox (gli stessi permessi salvati dalla versione Kotlin)
    implementation("androidx.documentfile:documentfile:1.0.1")
    // FileProvider per condividere e aprire il PDF del preventivo
    implementation("androidx.core:core:1.13.1")
}

flutter {
    source = "../.."
}
