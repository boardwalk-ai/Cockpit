package com.boardwalklabs.octopilot

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createGhostWriterChannel()
    }

    // The channel the server's push notifications name ("ghostwriter").
    // Creating one that exists already does nothing.
    private fun createGhostWriterChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            "ghostwriter",
            "GhostWriter",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply { description = "Questions from GhostWriter and finished essays" }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }
}
