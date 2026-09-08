// C4 语音（Android）：Godot Android 插件 v2，打成 AAR 给导出插件塞进 Gradle 构建。
// 构建：JAVA_HOME=<Android Studio 的 jbr> ./gradlew copyAars
plugins {
    id("com.android.library") version "8.7.3"
    id("org.jetbrains.kotlin.android") version "2.1.20"
}

android {
    namespace = "app.sensen.voice"
    compileSdk = 35
    defaultConfig { minSdk = 24 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    compileOnly("org.godotengine:godot:4.7.2.stable")
    implementation("io.livekit:livekit-android:2.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
}

tasks.register<Copy>("copyAars") {
    dependsOn("assembleDebug", "assembleRelease")
    from(layout.buildDirectory.dir("outputs/aar"))
    into(layout.projectDirectory.dir("bin"))
}
