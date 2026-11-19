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

// Debug distribution: the release one plus the socket transport (the JVM's `debugImplementation`).
val debugRuntime by configurations.creating {
    extendsFrom(configurations.runtimeClasspath.get())
    isCanBeConsumed = false
    attributes { attribute(Usage.USAGE_ATTRIBUTE, objects.named(Usage.JAVA_RUNTIME)) }
}

dependencies {
    debugRuntime(project(":tandem-socket"))
}

val debugStartScripts by tasks.registering(CreateStartScripts::class) {
    mainClass.set(application.mainClass)
    applicationName = "probe-host"
    outputDir = layout.buildDirectory.dir("debugScripts").get().asFile
    classpath = files(tasks.jar) + debugRuntime
}

distributions {
    create("debug") {
        contents {
            into("bin") { from(debugStartScripts) }
            into("lib") { from(tasks.jar, debugRuntime) }
        }
    }
}
