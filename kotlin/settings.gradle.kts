pluginManagement {
    repositories {
        gradlePluginPortal()
        mavenCentral()
    }
}

rootProject.name = "tandem-kotlin"

include("tandem-kit", "tandem-annotations", "tandem-ksp", "tandem-ksp-tests", "tandem-socket", "probe-host")
