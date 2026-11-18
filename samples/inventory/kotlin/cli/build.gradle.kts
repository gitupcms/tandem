plugins {
    kotlin("jvm")
    application
}

repositories { mavenCentral() }

dependencies {
    implementation(project(":core"))
    implementation("dev.tandem:tandem-kit")
}

kotlin { jvmToolchain(17) }

application {
    mainClass.set("inventory.cli.MainKt")
}
