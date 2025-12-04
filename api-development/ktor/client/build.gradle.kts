plugins {
    alias(libs.plugins.kotlin.multiplatform)
}

kotlin {
    jvm()

    sourceSets {
        commonMain.dependencies {
            api(project(":core"))
            api(libs.opentelemetry.ktor)
            api(libs.ktor.client.core)
        }
    }
}
