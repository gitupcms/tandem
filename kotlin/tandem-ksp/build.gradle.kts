plugins {
    kotlin("jvm")
}

group = "dev.tandem"

repositories { mavenCentral() }

dependencies {
    implementation("com.google.devtools.ksp:symbol-processing-api:2.3.14")
}

kotlin { jvmToolchain(17) }
