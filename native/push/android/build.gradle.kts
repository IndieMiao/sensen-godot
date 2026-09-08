// C2 推送（Android）：Godot Android 插件 v2，打成 AAR 给导出插件塞进 Gradle 构建。
// 构建：JAVA_HOME=<Android Studio 的 jbr> ./gradlew copyAars
//
// 接入还需要两件事（都在应用侧，不在本 AAR 里）：
//   1. Firebase 控制台下发的 google-services.json 放进 Android 导出模板的 app/ 目录；
//   2. 模板的 build.gradle 加 com.google.gms.google-services 插件。
// 缺这两样时 FirebaseMessaging.getInstance() 会抛，插件按 token_failed 回报，不崩。
plugins {
    id("com.android.library") version "8.7.3"
    id("org.jetbrains.kotlin.android") version "2.1.20"
}

android {
    namespace = "app.sensen.push"
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
    implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
    implementation("com.google.firebase:firebase-messaging")
}

tasks.register<Copy>("copyAars") {
    dependsOn("assembleDebug", "assembleRelease")
    from(layout.buildDirectory.dir("outputs/aar"))
    into(layout.projectDirectory.dir("bin"))
}
