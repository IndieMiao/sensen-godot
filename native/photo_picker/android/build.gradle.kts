// C3 Photo Picker（Android）：Godot Android 插件 v2，打成 AAR 给 addons/sensen_photo_picker 的导出插件塞进 Gradle 构建。
// 构建：JAVA_HOME=<Android Studio 的 jbr> ./gradlew assembleDebug assembleRelease（产物拷到 bin/）。
plugins {
    id("com.android.library") version "8.7.3"
    id("org.jetbrains.kotlin.android") version "2.1.20"
}

android {
    namespace = "app.sensen.photopicker"
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
    implementation("androidx.exifinterface:exifinterface:1.3.7")
}

// 产物固定名字放到 bin/，导出插件按这个路径找。
tasks.register<Copy>("copyAars") {
    dependsOn("assembleDebug", "assembleRelease")
    from(layout.buildDirectory.dir("outputs/aar"))
    into(layout.projectDirectory.dir("bin"))
}
