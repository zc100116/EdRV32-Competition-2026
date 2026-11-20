// build.gradle.kts — showcase R5-10/13; native offline tablet demo, host Gradle.
plugins {
    id("com.android.application") version "8.13.2"
    id("org.jetbrains.kotlin.android") version "2.0.21"
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.21"
    id("app.cash.paparazzi") version "1.3.5"
}

layout.buildDirectory.set(file("../../../build/demo-app/gradle"))
android {
    namespace = "cn.edrv32.demo"
    compileSdk = 35
    buildToolsVersion = "37.0.0"
    defaultConfig {
        applicationId = "cn.edrv32.demo"
        minSdk = 24
        targetSdk = 36
        versionCode = 3
        versionName = "1.2"
    }
    buildFeatures { compose = true }
    sourceSets["main"].assets.srcDir(file("../../../build/demo-app/assets"))
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    testOptions.unitTests.isIncludeAndroidResources = true
    packaging.resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
}
tasks.withType<Test>().configureEach {
    maxHeapSize = "512m"
    maxParallelForks = 1
    systemProperty("demo.output", file("../../../outputs/demo-app").absolutePath)
    systemProperty("demo.build", file("../../../build/demo-app").absolutePath)
}
tasks.matching { it.name == "assembleDebug" }.configureEach {
    doLast {
        copy {
            from(layout.buildDirectory.file("outputs/apk/debug/EdRV32Demo-debug.apk"))
            into(file("../../../build/demo-app"))
            rename { "edrv32-demo.apk" }
        }
    }
}
dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.11.00"))
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.media3:media3-exoplayer:1.5.1")
    implementation("androidx.media3:media3-ui:1.5.1")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
// JVM snapshot exporters use java.desktop, which Android production compilation omits.
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>()
    .matching { it.name == "compileDebugUnitTestKotlin" }.configureEach {
    compilerOptions.noJdk.set(false)
}
