rootProject.name = "ktor"

dependencyResolutionManagement {
    repositories {
        mavenCentral()
        maven("https://packages.confluent.io/maven/")
    }
}

include(":server")
include(":core")
include(":client")
