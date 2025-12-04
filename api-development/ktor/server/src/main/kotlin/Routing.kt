package com.api-example

import io.github.flaxoos.ktor.server.plugins.kafka.Kafka
import io.github.flaxoos.ktor.server.plugins.kafka.MessageTimestampType
import io.github.flaxoos.ktor.server.plugins.kafka.TopicName
import io.github.flaxoos.ktor.server.plugins.kafka.admin
import io.github.flaxoos.ktor.server.plugins.kafka.common
import io.github.flaxoos.ktor.server.plugins.kafka.consumer
import io.github.flaxoos.ktor.server.plugins.kafka.consumerConfig
import io.github.flaxoos.ktor.server.plugins.kafka.consumerRecordHandler
import io.github.flaxoos.ktor.server.plugins.kafka.producer
import io.github.flaxoos.ktor.server.plugins.kafka.registerSchemas
import io.github.flaxoos.ktor.server.plugins.kafka.topic
import io.github.flaxoos.ktor.server.plugins.ratelimiter.*
import io.github.flaxoos.ktor.server.plugins.ratelimiter.implementations.*
import io.ktor.client.HttpClient
import io.ktor.http.*
import io.ktor.serialization.gson.*
import io.ktor.server.application.*
import io.ktor.server.plugins.calllogging.*
import io.ktor.server.plugins.contentnegotiation.*
import io.ktor.server.plugins.requestvalidation.RequestValidation
import io.ktor.server.plugins.requestvalidation.ValidationResult
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import io.opentelemetry.api.trace.SpanKind
import io.opentelemetry.instrumentation.ktor.v3_0.KtorServerTelemetry
import kotlin.time.Duration.Companion.seconds
import org.slf4j.event.*

data class EmailRequest(
    val maxResults: Int = 10,
    val query: String? = null
)

data class EmailResponse(
    val id: String,
    val threadId: String,
    val subject: String,
    val from: String,
    val snippet: String,
    val receivedDate: Long
)

data class EmailListResponse(
    val emails: List<EmailResponse>,
    val totalCount: Int
)

fun Application.configureRouting() {
    val gmailService: GmailService? = try {
      val credentialsPath = environment.config.propertyOrNull("gmail.credentialsPath")?.getString()
      val applicationName = environment.config.propertyOrNull("gmail.applicationName")?.getString() 
          ?: "Ktor Gmail Integration"
      
      if (credentialsPath != null) {
          GmailServiceImpl(credentialsPath, applicationName)
      } else {
          log.warn("Gmail credentials not configured. Gmail endpoints will return 503.")
          null
      }
      } catch (e: Exception) {
          log.error("Failed to initialize Gmail service", e)
          null
      }
        
    install(RequestValidation) {
        validate<String> { bodyText ->
            if (!bodyText.startsWith("Hello"))
                ValidationResult.Invalid("Body text should start with 'Hello'")
            else ValidationResult.Valid
        }
        
        validate<EmailRequest> { request ->
            when {
                request.maxResults <= 0 -> 
                    ValidationResult.Invalid("maxResults must be greater than 0")
                request.maxResults > 100 -> 
                    ValidationResult.Invalid("maxResults cannot exceed 100")
                else -> ValidationResult.Valid
            }
        }
    }
    
    routing {
        get("/") {
            call.respondText("Hello World!")
        }
        
        route("/api/gmail") {
            
            get("/emails") {
                if (gmailService == null) {
                    return@get call.respond(
                        HttpStatusCode.ServiceUnavailable,
                        mapOf("error" to "Gmail service not configured")
                    )
                }
                
                try {
                    val maxResults = call.request.queryParameters["maxResults"]?.toIntOrNull() ?: 10
                    val query = call.request.queryParameters["query"]
                    val userId = call.request.queryParameters["userId"] ?: "me"
                    
                    val emails = gmailService.readEmails(userId, maxResults, query)
                    
                    call.respond(
                        HttpStatusCode.OK, 
                        EmailListResponse(
                            emails = emails,
                            totalCount = emails.size
                        )
                    )
                } catch (e: Exception) {
                    log.error("Error fetching emails", e)
                    call.respond(
                        HttpStatusCode.InternalServerError, 
                        mapOf("error" to "Failed to fetch emails")
                    )
                }
            }
            
            get("/emails/{messageId}") {
                if (gmailService == null) {
                    return@get call.respond(
                        HttpStatusCode.ServiceUnavailable,
                        mapOf("error" to "Gmail service not configured")
                    )
                }
                
                try {
                    val messageId = call.parameters["messageId"]
                        ?: return@get call.respond(
                            HttpStatusCode.BadRequest, 
                            mapOf("error" to "messageId is required")
                        )
                    
                    val userId = call.request.queryParameters["userId"] ?: "me"
                    val email = gmailService.getEmailById(userId, messageId)
                    
                    call.respond(HttpStatusCode.OK, email)
                } catch (e: NoSuchElementException) {
                    call.respond(
                        HttpStatusCode.NotFound,
                        mapOf("error" to "Email not found")
                    )
                } catch (e: Exception) {
                    log.error("Error fetching email", e)
                    call.respond(
                        HttpStatusCode.InternalServerError, 
                        mapOf("error" to "Failed to fetch email")
                    )
                }
            }
            
            post("/emails/search") {
                if (gmailService == null) {
                    return@post call.respond(
                        HttpStatusCode.ServiceUnavailable,
                        mapOf("error" to "Gmail service not configured")
                    )
                }
                
                try {
                    val request = call.receive<EmailRequest>()
                    val userId = call.request.queryParameters["userId"] ?: "me"
                    
                    val emails = gmailService.searchEmails(userId, request.maxResults, request.query)
                    
                    call.respond(
                        HttpStatusCode.OK,
                        EmailListResponse(
                            emails = emails,
                            totalCount = emails.size
                        )
                    )
                } catch (e: Exception) {
                    log.error("Error searching emails", e)
                    call.respond(
                        HttpStatusCode.InternalServerError, 
                        mapOf("error" to "Failed to search emails")
                    )
                }
            }
            
            get("/health") {
                val isConfigured = gmailService != null
                call.respond(
                    if (isConfigured) HttpStatusCode.OK else HttpStatusCode.ServiceUnavailable,
                    mapOf(
                        "status" to if (isConfigured) "healthy" else "not_configured",
                        "service" to "gmail-integration"
                    )
                )
            }
        }
    }
}