plugins {
    id("org.jetbrains.kotlin.jvm")
    application
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation(project(":atvremotekit"))
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.11.0")
}

application {
    mainClass.set("cli.MainKt")
}

// Matches the Python PoC's certs/ convention: run from the repo root so
// ClientIdentity persists to <repo-root>/certs/android/ rather than android/cli/.
tasks.named<JavaExec>("run") {
    workingDir = rootDir.parentFile
    standardInput = System.`in`
}

