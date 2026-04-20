package com.nself.claw.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.nself.claw.data.Message

private val NClawBackground = Color(0xFF0F0F1A)
private val NClawAccent = Color(0xFF6366F1)
private val AssistantBubble = Color(0xFF1E1E2E)

@Composable
fun ChatScreen(modifier: Modifier = Modifier, chatViewModel: ChatViewModel = viewModel()) {
    val messages by chatViewModel.messages.collectAsState()
    val isLoading by chatViewModel.isLoading.collectAsState()
    val error by chatViewModel.error.collectAsState()

    var input by remember { mutableStateOf(TextFieldValue("")) }
    val listState = rememberLazyListState()

    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) {
            listState.animateScrollToItem(messages.size - 1)
        }
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(NClawBackground)
    ) {
        LazyColumn(
            state = listState,
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            items(messages, key = { it.id }) { message ->
                MessageItem(message = message)
            }

            if (isLoading) {
                item {
                    Row(modifier = Modifier.padding(horizontal = 8.dp)) {
                        CircularProgressIndicator(
                            color = NClawAccent,
                            strokeWidth = 2.dp,
                            modifier = Modifier.padding(8.dp)
                        )
                    }
                }
            }
        }

        error?.let { errorText ->
            Text(
                text = errorText,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)
            )
        }

        HorizontalDivider(color = Color.White.copy(alpha = 0.1f))

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(NClawBackground)
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            OutlinedTextField(
                value = input,
                onValueChange = { input = it },
                placeholder = { Text("Ask anything...", color = Color.White.copy(alpha = 0.4f)) },
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(20.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = Color.White,
                    unfocusedTextColor = Color.White,
                    cursorColor = NClawAccent,
                    focusedBorderColor = NClawAccent,
                    unfocusedBorderColor = Color.White.copy(alpha = 0.2f)
                ),
                singleLine = true
            )

            Spacer(modifier = Modifier.width(8.dp))

            val canSend = input.text.isNotBlank() && !isLoading
            IconButton(
                onClick = {
                    if (canSend) {
                        chatViewModel.sendMessage(input.text.trim())
                        input = TextFieldValue("")
                    }
                },
                enabled = canSend
            ) {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.Send,
                    contentDescription = "Send",
                    tint = if (canSend) NClawAccent else Color.Gray
                )
            }
        }
    }
}

@Composable
private fun MessageItem(message: Message) {
    val isUser = message.role == Message.Role.USER
    val screenWidth = LocalConfiguration.current.screenWidthDp.dp

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start
    ) {
        Box(
            modifier = Modifier
                .widthIn(max = screenWidth * 0.75f)
                .clip(RoundedCornerShape(16.dp))
                .background(if (isUser) NClawAccent else AssistantBubble)
                .padding(horizontal = 14.dp, vertical = 10.dp)
        ) {
            Text(
                text = message.content,
                color = Color.White,
                style = MaterialTheme.typography.bodyMedium
            )
        }
    }
}
