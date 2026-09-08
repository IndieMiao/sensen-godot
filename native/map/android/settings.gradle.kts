// Mapbox Maps SDK v11 在自家 maven 上（匿名可下）；不加这条解析不到 com.mapbox.maps:android。
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://api.mapbox.com/downloads/v2/releases/maven") }
    }
}
rootProject.name = "sensen_map"
