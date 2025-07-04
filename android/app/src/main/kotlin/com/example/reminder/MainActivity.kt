package com.example.reminder //  Replace with your app's package name!

import io.flutter.embedding.android.FlutterActivity
import android.content.Intent
import android.os.Bundle
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        println("MainActivity: onCreate called") // Debug print

        // Handle the intent when the app is launched from a share
        if (intent?.action == Intent.ACTION_SEND) {
            handleSendIntent(intent)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        println("MainActivity: onNewIntent called") // Debug print
        // Handle the intent if the app is already running and receives a share
        if (intent.action == Intent.ACTION_SEND) {
            handleSendIntent(intent)
        }
    }

    private fun handleSendIntent(intent: Intent) {
        intent.getStringExtra(Intent.EXTRA_TEXT)?.let { sharedText ->
            // Pass the shared text to the Flutter app via platform channels
            val channel = MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, "app.channel.shared.data")
            channel.invokeMethod("handleSharedText", sharedText)
        }
    }
}