plugins {
    kotlin("jvm")
}

group = "dev.tandem"

repositories { mavenCentral() }

dependencies {
    implementation(project(":tandem-kit"))
}

kotlin { jvmToolchain(17) }
