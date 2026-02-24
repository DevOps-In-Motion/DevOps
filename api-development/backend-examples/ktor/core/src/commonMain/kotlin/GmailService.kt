package com.api-example

interface GmailService {
    suspend fun readEmails(userId: String, maxResults: Int, query: String?): List<EmailResponse>
    suspend fun getEmailById(userId: String, messageId: String): EmailResponse
    suspend fun searchEmails(userId: String, maxResults: Int, query: String?): List<EmailResponse>
}

data class EmailResponse(
    val id: String,
    val threadId: String,
    val subject: String,
    val from: String,
    val snippet: String,
    val receivedDate: Long
)