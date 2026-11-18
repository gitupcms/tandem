plugins {
    kotlin("jvm")
    id("com.google.devtools.ksp")
}

repositories { mavenCentral() }

dependencies {
    implementation(project(":tandem-kit"))
    implementation(project(":tandem-annotations"))
    ksp(project(":tandem-ksp"))
    testImplementation(kotlin("test"))
}

kotlin { jvmToolchain(17) }

tasks.test { useJUnitPlatform() }
