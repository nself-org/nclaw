package com.nself.claw.data

import java.util.UUID

data class Message(
    val id: String = UUID.randomUUID().toString(),
    val role: Role,
    val content: String,
    val timestamp: Long = System.currentTimeMillis()
) {
    enum class Role {
        USER,
        ASSISTANT
    }
}
