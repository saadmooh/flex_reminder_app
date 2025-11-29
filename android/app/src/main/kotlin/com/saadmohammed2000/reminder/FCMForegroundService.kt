package com.saadmohammed2000.flex_reminder

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*

class FCMForegroundService : Service() {

    companion object {
        private const val TAG = "FCMForegroundService"
        private const val CHANNEL_ID = "fcm_foreground_service"
        private const val NOTIFICATION_ID = 9999
        private const val SYNC_DURATION = 30000L // 30 ثانية
    }

    private val serviceScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var syncJob: Job? = null

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "🚀 FCM Foreground Service created")
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "▶️ FCM Foreground Service started")
        
        try {
            // إنشاء إشعار foreground
            val notification = createForegroundNotification()
            startForeground(NOTIFICATION_ID, notification)
            Log.d(TAG, "✅ Foreground notification displayed")
            
            // بدء مهمة المزامنة
            startSyncTask()
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error starting foreground service: ${e.message}", e)
        }
        
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        Log.d(TAG, "💀 FCM Foreground Service destroyed")
        syncJob?.cancel()
        serviceScope.cancel()
        super.onDestroy()
    }

    private fun createForegroundNotification(): Notification { // إصلاح: تحديد نوع الإرجاع
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        // تحديث الإشعار ديناميكياً
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Smart Reminder")
            .setContentText("مزامنة التذكيرات نشطة...")
            .setSmallIcon(R.drawable.notification)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .build()
            
        return notification
    }

    private fun startSyncTask() {
        syncJob?.cancel()
        
        syncJob = serviceScope.launch {
            while (isActive) {
                try {
                    Log.d(TAG, "🔄 Syncing reminders...")
                    
                    // إرسال broadcast للـ Flutter للمزامنة
                    val syncIntent = Intent("REMINDER_SYNC_REQUEST").apply {
                        setPackage(packageName)
                    }
                    sendBroadcast(syncIntent)
                    
                    delay(SYNC_DURATION)
                    
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Error in sync task: ${e.message}", e)
                    delay(SYNC_DURATION) // انتظر قبل المحاولة مرة أخرى
                }
            }
        }
    }

    private fun createNotificationChannel() { // إصلاح: إزالة نوع الإرجاع
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            var channel = notificationManager.getNotificationChannel(CHANNEL_ID)
            if (channel == null) {
                Log.d(TAG, "📢 Creating foreground service channel")
                
                channel = NotificationChannel(
                    CHANNEL_ID,
                    "خدمة المزامنة الخلفية",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "إشعارات خدمة مزامنة التذكيرات"
                    setShowBadge(false)
                    setSound(null, null)
                    enableVibration(false)
                }
                
                notificationManager.createNotificationChannel(channel)
                Log.d(TAG, "✅ Foreground service channel created")
            }
        }
    }
}