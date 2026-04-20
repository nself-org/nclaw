package com.nself.claw.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import com.nself.claw.data.ClawClient
import com.nself.claw.data.Message

class ChatViewModel(application: Application) : AndroidViewModel(application) {

    private val client = ClawClient(application)

    private val _messages = MutableStateFlow<List<Message>>(emptyList())
    val messages: StateFlow<List<Message>> = _messages.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    fun sendMessage(text: String) {
        if (text.isBlank() || _isLoading.value) return

        val userMessage = Message(role = Message.Role.USER, content = text)
        _messages.value = _messages.value + userMessage
        _error.value = null
        _isLoading.value = true

        viewModelScope.launch {
            try {
                val reply = client.sendMessage(text)
                val assistantMessage = Message(role = Message.Role.ASSISTANT, content = reply)
                _messages.value = _messages.value + assistantMessage
            } catch (e: Exception) {
                _error.value = e.message ?: "An unexpected error occurred."
            } finally {
                _isLoading.value = false
            }
        }
    }
}
