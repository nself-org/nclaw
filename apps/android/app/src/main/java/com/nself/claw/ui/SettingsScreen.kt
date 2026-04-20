package com.nself.claw.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.nself.claw.data.ClawClient

private val NClawBackground = Color(0xFF0F0F1A)
private val NClawAccent = Color(0xFF6366F1)

@Composable
fun SettingsScreen(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val client = remember { ClawClient(context) }

    var serverURL by remember { mutableStateOf(client.serverURL) }
    var apiKey by remember { mutableStateOf(client.apiKey) }
    var saved by remember { mutableStateOf(false) }

    val fieldColors = OutlinedTextFieldDefaults.colors(
        focusedTextColor = Color.White,
        unfocusedTextColor = Color.White,
        cursorColor = NClawAccent,
        focusedBorderColor = NClawAccent,
        unfocusedBorderColor = Color.White.copy(alpha = 0.2f),
        focusedLabelColor = NClawAccent,
        unfocusedLabelColor = Color.White.copy(alpha = 0.5f)
    )

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(NClawBackground)
            .padding(24.dp)
    ) {
        Text(
            text = "Connection",
            style = MaterialTheme.typography.titleMedium,
            color = Color.White.copy(alpha = 0.7f)
        )

        Spacer(modifier = Modifier.height(16.dp))

        OutlinedTextField(
            value = serverURL,
            onValueChange = {
                serverURL = it
                saved = false
            },
            label = { Text("Server URL") },
            placeholder = { Text("https://your-server.example.com", color = Color.White.copy(alpha = 0.3f)) },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            colors = fieldColors
        )

        Spacer(modifier = Modifier.height(12.dp))

        OutlinedTextField(
            value = apiKey,
            onValueChange = {
                apiKey = it
                saved = false
            },
            label = { Text("API Key") },
            placeholder = { Text("Bearer token", color = Color.White.copy(alpha = 0.3f)) },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            colors = fieldColors
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "Enter the URL and API key of your nSelf server running the claw plugin.",
            style = MaterialTheme.typography.bodySmall,
            color = Color.White.copy(alpha = 0.4f)
        )

        Spacer(modifier = Modifier.height(24.dp))

        Button(
            onClick = {
                client.serverURL = serverURL
                client.apiKey = apiKey
                saved = true
            },
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(containerColor = NClawAccent),
            shape = RoundedCornerShape(12.dp)
        ) {
            Text(if (saved) "Saved" else "Save", color = Color.White)
        }
    }
}
