package com.api-example

import com.google.api.client.googleapis.javanet.GoogleNetHttpTransport
import com.google.api.client.json.gson.GsonFactory
import com.google.api.services.gmail.Gmail
import com.google.api.services.gmail.model.Message
import com.google.auth.http.HttpCredentialsAdapter
import com.google.auth.oauth2.GoogleCredentials
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.FileInputStream
import java.util.Base64

class GmailServiceImpl(
    private val credentialsPath: String,
    private val applicationName: String = "Ktor Gmail Integration"
) : GmailService {

    private val jsonFactory = GsonFactory.getDefaultInstance()
    private val httpTransport = GoogleNetHttpTransport.newTrustedTransport()

    private fun getGmailService(): Gmail {
        val credentials = GoogleCredentials.fromStream(FileInputStream(credentialsPath))
            .createScoped(listOf("https://www.googleapis.com/auth/gmail.readonly"))

        return Gmail.Builder(
            httpTransport,
            jsonFactory,
            HttpCredentialsAdapter(credentials)
        )
            .setApplicationName(applicationName)
            .build()
    }

    override suspend fun readEmails(
        userId: String,
        maxResults: Int,
        query: String?
    ): List<EmailResponse> = withContext(Dispatchers.IO) {
        val service = getGmailService()
        
        val listRequest = service.users().messages().list(userId)
            .setMaxResults(maxResults.toLong())
        
        if (query != null) {
            listRequest.q = query
        }
        
        val messages = listRequest.execute().messages ?: return@withContext emptyList()
        
        messages.mapNotNull { messageRef ->
            try {
                val message = service.users().messages()
                    .get(userId, messageRef.id)
                    .setFormat("metadata")
                    .setMetadataHeaders(listOf("Subject", "From", "Date"))
                    .execute()
                
                mapToEmailResponse(message)
            } catch (e: Exception) {
                null
            }
        }
    }

    override suspend fun getEmailById(
        userId: String,
        messageId: String
    ): EmailResponse = withContext(Dispatchers.IO) {
        val service = getGmailService()
        
        val message = service.users().messages()
            .get(userId, messageId)
            .setFormat("full")
            .execute()
            ?: throw NoSuchElementException("Email with id $messageId not found")
        
        mapToEmailResponse(message)
    }

    override suspend fun searchEmails(
        userId: String,
        maxResults: Int,
        query: String?
    ): List<EmailResponse> = readEmails(userId, maxResults, query)

    private fun mapToEmailResponse(message: Message): EmailResponse {
        val headers = message.payload?.headers ?: emptyList()
        
        val subject = headers.find { it.name.equals("Subject", ignoreCase = true) }?.value ?: "(No Subject)"
        val from = headers.find { it.name.equals("From", ignoreCase = true) }?.value ?: "(Unknown Sender)"
        val date = headers.find { it.name.equals("Date", ignoreCase = true) }?.value
        
        return EmailResponse(
            id = message.id,
            threadId = message.threadId,
            subject = subject,
            from = from,
            snippet = message.snippet ?: "",
            receivedDate = message.internalDate ?: System.currentTimeMillis()
        )
    }
}