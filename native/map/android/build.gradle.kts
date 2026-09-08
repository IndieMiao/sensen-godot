// B5 地图垫底（Android）：Mapbox MapView 垫在 Godot 透明渲染面之下，Godot 插件 v2 打成 AAR。
// 原来这份代码是「覆盖到 Godot 安卓构建模板上」用的（tools/android/overlay，农场那条线），
// 模板一重装就没了，社交包也没人去铺；改成独立 AAR 后与选图 / 推送 / 语音三个插件同一形状。
// 构建：JAVA_HOME=<Android Studio 的 jbr> ./gradlew copyAars
plugins {
    id("com.android.library") version "8.7.3"
    id("org.jetbrains.kotlin.android") version "2.1.20"
}

android {
    namespace = "com.sensen.map"
    compileSdk = 35
    defaultConfig { minSdk = 24 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    testOptions { unitTests.isReturnDefaultValues = true }
}

dependencies {
    compileOnly("org.godotengine:godot:4.7.2.stable")
    implementation("com.mapbox.maps:android:11.30.0")
    testImplementation("org.jetbrains.kotlin:kotlin-test-junit:2.1.20")
}

tasks.register<Copy>("copyAars") {
    dependsOn("assembleDebug", "assembleRelease")
    from(layout.buildDirectory.dir("outputs/aar"))
    into(layout.projectDirectory.dir("bin"))
}
