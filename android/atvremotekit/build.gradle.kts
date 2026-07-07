plugins {
    id("org.jetbrains.kotlin.jvm")
    id("java-library")
    id("com.google.protobuf")
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    // api, not implementation: consumers (cli, app) work directly with the
    // generated message/enum types, which extend protobuf-java's classes.
    api("com.google.protobuf:protobuf-java:4.35.1")
    api("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.11.0")
    testImplementation(kotlin("test-junit5"))
}

sourceSets {
    main {
        proto {
            // Single source of truth shared with the iOS implementation —
            // see ios/proto/*.proto for provenance notes on each file.
            srcDir("${rootDir}/../ios/proto")
        }
    }
}

protobuf {
    protoc {
        artifact = "com.google.protobuf:protoc:4.35.1"
    }
}

tasks.test {
    useJUnitPlatform()
}
