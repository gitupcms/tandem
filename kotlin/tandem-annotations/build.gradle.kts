plugins {
    kotlin("jvm")
}

group = "dev.tandem"

repositories { mavenCentral() }

kotlin { jvmToolchain(17) }
