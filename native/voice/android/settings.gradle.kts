// LiveKit Android 依赖 com.github.davidliu:audioswitch，只在 JitPack 上有，Maven Central 没有。
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositories { google(); mavenCentral(); maven { url = uri("https://jitpack.io") } }
}
rootProject.name = "sensen_voice"
