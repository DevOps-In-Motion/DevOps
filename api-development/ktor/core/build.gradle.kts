plugins {
    alias(libs.plugins.kotlin.multiplatform)
}

kotlin {
    jvm()

    sourceSets {
        commonMain.dependencies {
            api(libs.opentelemetry.sdk.extension.autoconfigure)
            api(libs.opentelemetry.semconv)
            api(libs.opentelemetry.exporter.otlp)
            api(libs.opentelemetry.ktor)
        }
    }
}
