package com.saadmohammed2000.flex_reminder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log

class MyFCMReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TAG = "FCMReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "📱 ========== FCM RECEIVER TRIGGERED ==========")
        Log.d(TAG, "📱 Action: ${intent.action}")
        
        when (intent.action) {
            "com.google.android.c2dm.intent.RECEIVE" -> {
                Log.d(TAG, "📬 FCM message received in BroadcastReceiver")
                // معالجة الرسالة إذا لزم الأمر
            }
            "com.google.firebase.MESSAGING_EVENT" -> {
                Log.d(TAG, "🔔 FCM messaging event")
                // تمرير للـ Service
                val serviceIntent = Intent(context, MyFirebaseMessagingService::class.java)
                // نسخ البيانات من الـ intent الحالي
                val extras = Bundle(intent.extras ?: Bundle())
                serviceIntent.putExtras(extras)
                context.startService(serviceIntent)
            }
            else -> {
                Log.d(TAG, "⚠️ Unknown action: ${intent.action}")
            }
        }
    }
}