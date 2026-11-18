pluginManagement {
    repositories {
        gradlePluginPortal()
        mavenCentral()
    }
}

rootProject.name = "tandem-kotlin"

include("tandem-kit", "tandem-annotations", "tandem-ksp", "tandem-ksp-tests", "probe-host")
