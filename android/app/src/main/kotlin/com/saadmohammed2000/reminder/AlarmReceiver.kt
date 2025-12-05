package com.saadmohammed2000.flex_reminder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import android.app.NotificationManager
import android.app.NotificationChannel
import android.os.Build
import androidx.core.app.NotificationCompat
import android.app.PendingIntent
import android.media.RingtoneManager
import android.os.PowerManager
import android.media.AudioAttributes


class AlarmReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TAG = "AlarmReceiver"
        const val EXTRA_REMINDER_ID = "reminder_id"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_URL = "url"
        const val EXTRA_IMPORTANCE = "importance"
        const val CHANNEL_ID = "scheduled_channel"
        const val ALARM_ACTION = "ALARM_ACTION" // إضافة هذا الثابت
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "🔔 ========== ALARM TRIGGERED ==========")
        Log.d(TAG, "📱 Intent Action: ${intent.action}")
        Log.d(TAG, "📦 Package: ${context.packageName}")
        
        // التأكد من أن هذا هو intent صحيح
        if (intent.action != ALARM_ACTION && 
            intent.action != "android.intent.action.NOTIFY") {
            Log.w(TAG, "⚠️ Unknown action: ${intent.action}")
            return
        }
        
        // إيقاظ الجهاز
        wakeUpDevice(context)
        
        val reminderId = intent.getIntExtra(EXTRA_REMINDER_ID, -1)
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "تذكير"
        val body = intent.getStringExtra(EXTRA_BODY) ?: "حان وقت التذكير!"
        val url = intent.getStringExtra(EXTRA_URL) ?: ""
        val importance = intent.getStringExtra(EXTRA_IMPORTANCE) ?: "medium"

        Log.d(TAG, "📋 Reminder ID: $reminderId")
        Log.d(TAG, "📝 Title: $title")
        Log.d(TAG, "💬 Body: $body")
        Log.d(TAG, "🔗 URL: $url")
        Log.d(TAG, "⚡ Importance: $importance")

        if (reminderId == -1) {
            Log.e(TAG, "❌ Invalid reminder ID")
            return
        }

        // إنشاء وعرض الإشعار
        showNotification(context, reminderId, title, body, url, importance)
        
        // إرسال broadcast للتطبيق إذا كان مفتوحاً
        sendBroadcastToApp(context, reminderId, title, url, importance)
        
        Log.d(TAG, "✅ ========== ALARM COMPLETED ==========")
    }

    private fun wakeUpDevice(context: Context) {
        try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            
            @Suppress("DEPRECATION")
            val wakeLock = powerManager.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or 
                PowerManager.ACQUIRE_CAUSES_WAKEUP or
                PowerManager.ON_AFTER_RELEASE,
                "SmartReminder:AlarmWakeLock"
            )
            
            wakeLock.acquire(10000) // 10 seconds
            Log.d(TAG, "📱 Device screen woken up")
            
            // تحرير WakeLock بعد فترة
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                try {
                    if (wakeLock.isHeld) {
                        wakeLock.release()
                        Log.d(TAG, "🔓 WakeLock released")
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Error releasing WakeLock: ${e.message}")
                }
            }, 10000)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error waking device: ${e.message}", e)
        }
    }

    private fun showNotification(
    context: Context,
    reminderId: Int,
    title: String,
    body: String,
    url: String,
    importance: String
) {
    try {
        Log.d(TAG, "📱 Creating notification with custom icon and deep link...")

        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        createNotificationChannel(notificationManager, context)

        // ==== Intent لفتح ReminderDetailScreen مباشرة ====
        val deepLinkIntent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP

            // تمرير reminderId عبر extras
            putExtra("open_reminder_detail", true)
            putExtra("reminder_id", reminderId)
            putExtra("from_notification", true)
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            reminderId,
            deepLinkIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // ==== بناء الإشعار مع الأيقونة المخصصة ====
        val notificationBuilder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.notification)  // ← هنا الأيقونة المخصصة
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body)) // لعرض النص كاملاً إذا طويل
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setFullScreenIntent(pendingIntent, true) // لإظهار Full Screen Intent
            .setVibrate(longArrayOf(0, 1000, 500, 1000, 500, 1000))
            .setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM))
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setTimeoutAfter(60000)

        // زر إغلاق
        val dismissIntent = Intent(context, NotificationDismissReceiver::class.java).apply {
            putExtra(EXTRA_REMINDER_ID, reminderId)
        }
        val dismissPendingIntent = PendingIntent.getBroadcast(
            context,
            reminderId + 10000,
            dismissIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        notificationBuilder.addAction(
            android.R.drawable.ic_menu_close_clear_cancel,
            "إغلاق",
            dismissPendingIntent
        )

        val notification = notificationBuilder.build()
        notification.flags = notification.flags or
                NotificationCompat.FLAG_INSISTENT

        notificationManager.notify(reminderId, notification)
        Log.d(TAG, "✅ Notification displayed with custom icon and deep link to reminder $reminderId")

    } catch (e: Exception) {
        Log.e(TAG, "❌ Error showing notification: ${e.message}", e)
    }
}

    private fun createNotificationChannel(
        notificationManager: NotificationManager,
        context: Context
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            var channel = notificationManager.getNotificationChannel(CHANNEL_ID)
            
            if (channel == null) {
                Log.d(TAG, "📢 Creating new notification channel")
                
                // استخدام نغمة المنبه
                val alarmSoundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                
                val audioAttributes = AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .build()
                
                channel = NotificationChannel(
                    CHANNEL_ID,
                    "التذكيرات المجدولة",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "إشعارات التذكيرات المجدولة"
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 1000, 500, 1000, 500, 1000)
                    enableLights(true)
                    lightColor = android.graphics.Color.RED
                    setShowBadge(true)
                    lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
                    setSound(alarmSoundUri, audioAttributes)
                    setBypassDnd(true)
                }
                
                notificationManager.createNotificationChannel(channel)
                Log.d(TAG, "✅ Notification channel created successfully")
            } else {
                Log.d(TAG, "📢 Using existing notification channel")
            }
        }
    }

    private fun sendBroadcastToApp(
        context: Context,
        reminderId: Int,
        title: String,
        url: String,
        importance: String
    ) {
        try {
            val broadcastIntent = Intent("REMINDER_TRIGGERED").apply {
                setPackage(context.packageName)
                putExtra(EXTRA_REMINDER_ID, reminderId)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_URL, url)
                putExtra(EXTRA_IMPORTANCE, importance)
            }
            
            context.sendBroadcast(broadcastIntent)
            Log.d(TAG, "📡 Broadcast sent to app")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error sending broadcast: ${e.message}", e)
        }
    }
}

// مستقبل لإغلاق الإشعار
class NotificationDismissReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val reminderId = intent.getIntExtra(AlarmReceiver.EXTRA_REMINDER_ID, -1)
        if (reminderId != -1) {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancel(reminderId)
            Log.d("NotificationDismiss", "✅ Notification dismissed: $reminderId")
        }
    }
}