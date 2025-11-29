package com.saadmohammed2000.flex_reminder

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import org.json.JSONObject

class MyFirebaseMessagingService : FirebaseMessagingService() {

    companion object {
        private const val TAG = "FCMService"
        private const val CHANNEL_ID = "fcm_notifications"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val FCM_DATA_KEY = "flutter.fcm_data"
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)
        
        Log.d(TAG, "📬 ========== FCM MESSAGE RECEIVED ==========")
        Log.d(TAG, "📤 From: ${remoteMessage.from}")
        Log.d(TAG, "📦 Message ID: ${remoteMessage.messageId}")
        Log.d(TAG, "⏰ Sent Time: ${remoteMessage.sentTime}")
        
        try {
            // معالجة البيانات (data payload)
            if (remoteMessage.data.isNotEmpty()) {
                Log.d(TAG, "📋 Data payload: ${remoteMessage.data}")
                handleDataMessage(remoteMessage.data)
            }
            
            // معالجة الإشعار (notification payload)
            remoteMessage.notification?.let { notification ->
                Log.d(TAG, "🔔 Notification payload:")
                Log.d(TAG, "  - Title: ${notification.title}")
                Log.d(TAG, "  - Body: ${notification.body}")
                
                // دمج بيانات notification مع data
                val combinedData = remoteMessage.data.toMutableMap()
                notification.title?.let { title -> combinedData["notification_title"] = title }
                notification.body?.let { body -> combinedData["notification_body"] = body }
                
                showNotification(
                    notification.title ?: "تذكير جديد",
                    notification.body ?: "لديك تذكير جديد",
                    combinedData
                )
            }
            
            Log.d(TAG, "✅ FCM message processed successfully")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error processing FCM message: ${e.message}", e)
        }
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d(TAG, "🔑 New FCM token generated: $token")
        
        // حفظ التوكن في SharedPreferences
        saveTokenToPreferences(token)
        
        // إرسال التوكن إلى Flutter إذا كان التطبيق يعمل
        sendTokenToFlutter(token)
        
        // حفظ التوكن في secure storage للـ Flutter
        saveTokenForFlutter(token)
    }

    override fun onDeletedMessages() {
        super.onDeletedMessages()
        Log.d(TAG, "🗑️ FCM messages deleted on server")
        
        // إعلام الـ Flutter
        val intent = Intent("FCM_MESSAGES_DELETED").apply {
            setPackage(packageName)
        }
        sendBroadcast(intent)
    }

    override fun onMessageSent(msgId: String) {
        super.onMessageSent(msgId)
        Log.d(TAG, "📤 Message sent successfully: $msgId")
    }

    override fun onSendError(msgId: String, exception: Exception) {
        super.onSendError(msgId, exception)
        Log.e(TAG, "❌ Error sending message $msgId: ${exception.message}")
        
        // إعلام الـ Flutter بالخطأ
        val intent = Intent("FCM_SEND_ERROR").apply {
            setPackage(packageName)
            putExtra("message_id", msgId)
            putExtra("error", exception.message)
        }
        sendBroadcast(intent)
    }

    private fun handleDataMessage(data: Map<String, String>) {
        try {
            // استخراج البيانات من رسالتك
            val postId = data["post_id"] ?: ""
            val action = data["action"] ?: ""
            val postTitle = data["post_title"] ?: ""
            val postUrl = data["post_url"] ?: ""
            val timestamp = data["timestamp"] ?: ""
            val nextReminderTime = data["next_reminder_time"] ?: ""
            
            Log.d(TAG, "📋 Handling data message:")
            Log.d(TAG, "  - Post ID: $postId")
            Log.d(TAG, "  - Action: $action")
            Log.d(TAG, "  - Post Title: $postTitle")
            Log.d(TAG, "  - Post URL: $postUrl")
            Log.d(TAG, "  - Timestamp: $timestamp")
            Log.d(TAG, "  - Next Reminder: $nextReminderTime")
            
            // حفظ البيانات في SharedPreferences
            saveFcmDataToPreferences(data)
            
            // إرسال broadcast إلى Flutter
            val broadcastIntent = Intent("FCM_MESSAGE_RECEIVED").apply {
                setPackage(packageName)
                putExtra("action", action)
                putExtra("post_id", postId)
                putExtra("post_title", postTitle)
                putExtra("post_url", postUrl)
                putExtra("timestamp", timestamp)
                putExtra("next_reminder_time", nextReminderTime)
            }
            sendBroadcast(broadcastIntent)
            
            when (action) {
                "new" -> {
                    // عرض إشعار للتذكير الجديد
                    val title = if (postTitle.isNotEmpty()) postTitle else "تذكير جديد"
                    val body = "موعد التذكير التالي: $nextReminderTime"
                    showNotification(title, body, data)
                }
                "reminder_updated" -> {
                    // عرض إشعار للتحديث
                    val title = if (postTitle.isNotEmpty()) postTitle else "تحديث التذكير"
                    val body = "تم تحديث التذكير: $nextReminderTime"
                    showNotification(title, body, data)
                }
                "reschedule" -> {
                    // عرض إشعار لإعادة الجدولة
                    val title = if (postTitle.isNotEmpty()) postTitle else "إعادة جدولة التذكير"
                    val body = "موعد التذكير الجديد: $nextReminderTime"
                    showNotification(title, body, data)
                }
                "markas_read" -> {
                    // عرض إشعار للعلامة كمقروء
                    val title = if (postTitle.isNotEmpty()) postTitle else "تم قراءة التذكير"
                    val body = "تم وضع علامة مقروء على التذكير"
                    showNotification(title, body, data)
                }
                "delete" -> {
                    // عرض إشعار للحذف
                    val title = if (postTitle.isNotEmpty()) postTitle else "حذف التذكير"
                    val body = "تم حذف التذكير"
                    showNotification(title, body, data)
                }
                else -> {
                    // عرض إشعار عام
                    val title = if (postTitle.isNotEmpty()) postTitle else "تذكير"
                    val body = "موعد التذكير التالي: $nextReminderTime"
                    showNotification(title, body, data)
                }
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error handling data message: ${e.message}", e)
        }
    }

    private fun showNotification(title: String, body: String, data: Map<String, String>) {
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            createNotificationChannel(notificationManager)
            
            // استخراج post_id من البيانات
            val postId = data["post_id"]?.toIntOrNull() ?: -1
            
            // إنشاء Intent لفتح التطبيق
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                
                // إضافة البيانات من FCM
                data.forEach { (key, value) ->
                    putExtra(key, value)
                }
                putExtra("from_fcm", true)
                putExtra("open_reminder_detail", true)
                putExtra("reminder_id", postId)
            }
            
            val pendingIntent = PendingIntent.getActivity(
                this,
                System.currentTimeMillis().toInt(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            // بناء الإشعار
            val notificationBuilder = NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.drawable.notification)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                .setAutoCancel(true)
                .setContentIntent(pendingIntent)
                .setVibrate(longArrayOf(0, 500, 250, 500))
                .setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION))
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
            
            // عرض الإشعار
            val notificationId = if (postId != -1) postId else System.currentTimeMillis().toInt()
            notificationManager.notify(notificationId, notificationBuilder.build())
            
            Log.d(TAG, "✅ Notification displayed successfully")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error showing notification: ${e.message}", e)
        }
    }

    private fun createNotificationChannel(notificationManager: NotificationManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            var channel = notificationManager.getNotificationChannel(CHANNEL_ID)
            
            if (channel == null) {
                Log.d(TAG, "📢 Creating FCM notification channel")
                
                val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                val audioAttributes = AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .build()
                
                channel = NotificationChannel(
                    CHANNEL_ID,
                    "إشعارات FCM",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "إشعارات Firebase Cloud Messaging"
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 500, 250, 500)
                    enableLights(true)
                    lightColor = android.graphics.Color.BLUE
                    setShowBadge(true)
                    lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
                    setSound(soundUri, audioAttributes)
                }
                
                notificationManager.createNotificationChannel(channel)
                Log.d(TAG, "✅ FCM notification channel created")
            }
        }
    }

    private fun sendTokenToFlutter(token: String) {
        try {
            val intent = Intent("FCM_TOKEN_REFRESH").apply {
                setPackage(packageName)
                putExtra("token", token)
            }
            sendBroadcast(intent)
            Log.d(TAG, "📡 Token sent to Flutter")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error sending token to Flutter: ${e.message}", e)
        }
    }

    private fun saveTokenToPreferences(token: String) {
        try {
            val prefs = getSharedPreferences("fcm_prefs", Context.MODE_PRIVATE)
            prefs.edit().putString("fcm_token", token).apply()
            Log.d(TAG, "💾 Token saved to SharedPreferences")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error saving token: ${e.message}", e)
        }
    }

    private fun saveTokenForFlutter(token: String) {
        try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().putString("flutter.fcm_token", token).apply()
            Log.d(TAG, "💾 Token saved for Flutter")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error saving token for Flutter: ${e.message}", e)
        }
    }

    private fun saveFcmDataToPreferences(data: Map<String, String>) {
        try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val editor = prefs.edit()
            
            // حفظ كل بيانات FCM
            data.forEach { (key, value) ->
                editor.putString("fcm_$key", value)
            }
            
            // حفظ كـ JSON أيضاً
            val jsonData = JSONObject(data as Map<*, *>).toString()
            editor.putString(FCM_DATA_KEY, jsonData)
            
            editor.apply()
            Log.d(TAG, "💾 FCM data saved to SharedPreferences")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error saving FCM data: ${e.message}", e)
        }
    }
}