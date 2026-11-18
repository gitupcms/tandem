plugins {
    kotlin("jvm")
    id("com.google.devtools.ksp")
}

repositories { mavenCentral() }

dependencies {
    implementation("dev.tandem:tandem-kit")
    implementation("dev.tandem:tandem-annotations")
    ksp("dev.tandem:tandem-ksp")
}

kotlin { jvmToolchain(17) }
