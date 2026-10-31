plugins {
    alias(libs.plugins.android.application)
}

// Independent instrumentation APK: do not deduplicate its runner against the
// app's compile classpath, where Skip exposes test APIs that R8 removes.
android {
    namespace = "xatu.devicetests"
    compileSdk = libs.versions.android.sdk.compile.get().toInt()
    defaultConfig {
        applicationId = "com.cell.xatuapp.test"
        minSdk = 28
        targetSdk = libs.versions.android.sdk.compile.get().toInt()
    }
    compileOptions {
        sourceCompatibility = JavaVersion.toVersion(libs.versions.jvm.get())
        targetCompatibility = JavaVersion.toVersion(libs.versions.jvm.get())
    }
    sourceSets.getByName("main") {
        assets.srcDir("../app/src/androidTest/assets")
    }
}
kotlin {
    compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.fromTarget(libs.versions.jvm.get().toString()) }
}
dependencies {
    implementation("androidx.test.ext:junit:1.2.1")
    implementation("androidx.test:runner:1.6.2")
    implementation("androidx.test.uiautomator:uiautomator:2.3.0")
    implementation("androidx.webkit:webkit:1.15.0")
}
