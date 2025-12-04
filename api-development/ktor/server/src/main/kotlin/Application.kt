package com.api-example

import io.ktor.server.application.*

fun main(args: Array<String>) {
    io.ktor.server.netty.EngineMain.main(args)
}

fun Application.module() {
    configureDatabases()
    configureAdministration()
    configureSerialization()
    configureMonitoring()
    configureSecurity()
    configureRouting()
}
