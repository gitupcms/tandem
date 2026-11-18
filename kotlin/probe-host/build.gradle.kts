plugins {
    kotlin("jvm")
    application
}

repositories { mavenCentral() }

dependencies {
    implementation(project(":tandem-kit"))
}

kotlin { jvmToolchain(17) }

application {
    mainClass.set("tandem.probe.MainKt")
}
