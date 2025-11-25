package com.saadmohammed2000.flex_reminder

import io.flutter.embedding.android.FlutterFragmentActivity
import android.content.Intent
import android.os.Bundle
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngine
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.os.Build
import android.util.Log
import android.provider.Settings

class MainActivity: FlutterFragmentActivity() {
    
    private val SHARED_DATA_CHANNEL = "app.channel.shared.data"
    private val ALARM_CHANNEL = "com.saadmohammed2000.flex_reminder/alarm"
    private var sharedText: String? = null
    
    companion object {
        private const val TAG = "MainActivity"
        const val ALARM_ACTION = "ALARM_ACTION"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "🚀 ========== APP STARTED ==========")
        Log.d(TAG, "📱 App Package: ${packageName}")
        Log.d(TAG, "📦 Android Version: ${Build.VERSION.SDK_INT}")
        
        // معالجة البيانات المشتركة
        if (intent?.action == Intent.ACTION_SEND) {
            sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
            Log.d(TAG, "📝 Shared text stored: $sharedText")
        }
        // داخل onCreate و onNewIntent (نفس الكود في المكانين)
if (intent.hasExtra("open_reminder_detail") && intent.getBooleanExtra("open_reminder_detail", false)) {
    val reminderId = intent.getIntExtra("reminder_id", -1)
    Log.d(TAG, "🎯 Deep link: Opening ReminderDetailScreen for ID: $reminderId")

    // إرسال event إلى Flutter
    flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
        val channel = MethodChannel(messenger, "com.saadmohammed2000.flex_reminder/deeplink")
        channel.invokeMethod("openReminderDetail", reminderId)
    }
}
        
        // التحقق من الأذونات الضرورية
        checkExactAlarmPermission()
        checkBatteryOptimization()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "⚙️ Configuring Flutter engine...")
        
        // ==================== قناة البيانات المشتركة ====================
        val sharedDataChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, 
            SHARED_DATA_CHANNEL
        )
        
        sharedText?.let { text ->
            Log.d(TAG, "📤 Sending shared text to Flutter: $text")
            sharedDataChannel.invokeMethod("handleSharedText", text)
            sharedText = null
        }
        
        // ==================== قناة الإنذارات ====================
        val alarmChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ALARM_CHANNEL
        )
        
        alarmChannel.setMethodCallHandler { call, result ->
            Log.d(TAG, "📞 Method call received: ${call.method}")
            
            when (call.method) {
                "scheduleAlarm" -> {
                    try {
                        val reminderId = call.argument<Int>("reminderId")
                        val title = call.argument<String>("title")
                        val body = call.argument<String>("body")
                        val url = call.argument<String>("url")
                        val importance = call.argument<String>("importance")
                        val scheduledTime = call.argument<Long>("scheduledTime")
                        
                        Log.d(TAG, "📋 ========== SCHEDULE REQUEST ==========")
                        Log.d(TAG, "  - Reminder ID: $reminderId")
                        Log.d(TAG, "  - Title: $title")
                        Log.d(TAG, "  - Body: $body")
                        Log.d(TAG, "  - URL: $url")
                        Log.d(TAG, "  - Importance: $importance")
                        Log.d(TAG, "  - Scheduled Time: $scheduledTime")
                        Log.d(TAG, "  - Current Time: ${System.currentTimeMillis()}")
                        
                        if (reminderId != null && title != null && scheduledTime != null) {
                            // التحقق من أن الوقت في المستقبل
                            if (scheduledTime <= System.currentTimeMillis()) {
                                Log.e(TAG, "❌ Scheduled time is in the past!")
                                result.error("INVALID_TIME", "Scheduled time must be in the future", null)
                                return@setMethodCallHandler
                            }
                            
                            val success = scheduleExactAlarm(
                                reminderId, 
                                title, 
                                body ?: "حان وقت التذكير!", 
                                url ?: "", 
                                importance ?: "medium", 
                                scheduledTime
                            )
                            
                            if (success) {
                                Log.d(TAG, "✅ Alarm scheduled successfully")
                                result.success(true)
                            } else {
                                Log.e(TAG, "❌ Failed to schedule alarm")
                                result.success(false)
                            }
                        } else {
                            Log.e(TAG, "❌ Invalid arguments - Missing required fields")
                            result.error("INVALID_ARGS", "Missing required arguments", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Exception in scheduleAlarm: ${e.message}", e)
                        result.error("EXCEPTION", e.message, null)
                    }
                }
                
                "cancelAlarm" -> {
                    try {
                        val reminderId = call.argument<Int>("reminderId")
                        Log.d(TAG, "🗑️ ========== CANCEL REQUEST ==========")
                        Log.d(TAG, "  - Reminder ID: $reminderId")
                        
                        if (reminderId != null) {
                            cancelAlarm(reminderId)
                            Log.d(TAG, "✅ Alarm cancelled successfully")
                            result.success(true)
                        } else {
                            Log.e(TAG, "❌ Invalid reminderId")
                            result.error("INVALID_ARGS", "Missing reminderId", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Exception in cancelAlarm: ${e.message}", e)
                        result.error("EXCEPTION", e.message, null)
                    }
                }
                
                "canScheduleExactAlarms" -> {
                    try {
                        val canSchedule = canScheduleExactAlarms()
                        Log.d(TAG, "🔍 Can schedule exact alarms: $canSchedule")
                        result.success(canSchedule)
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Exception in canScheduleExactAlarms: ${e.message}", e)
                        result.success(false)
                    }
                }
                
                "requestExactAlarmPermission" -> {
                    try {
                        Log.d(TAG, "🔐 Requesting exact alarm permission")
                        requestExactAlarmPermission()
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Exception in requestExactAlarmPermission: ${e.message}", e)
                        result.error("EXCEPTION", e.message, null)
                    }
                }
                
                else -> {
                    Log.w(TAG, "⚠️ Unknown method: ${call.method}")
                    result.notImplemented()
                }
            }
        }
        
        Log.d(TAG, "✅ Flutter engine configured successfully")
    }

    /**
     * جدولة إنذار دقيق باستخدام AlarmManager
     */
    private fun scheduleExactAlarm(
        reminderId: Int,
        title: String,
        body: String,
        url: String,
        importance: String,
        scheduledTimeMillis: Long
    ): Boolean {
        return try {
            Log.d(TAG, "🔧 ========== SCHEDULING EXACT ALARM ==========")
            
            val currentTime = System.currentTimeMillis()
            val delaySeconds = (scheduledTimeMillis - currentTime) / 1000
            
            Log.d(TAG, "📊 Alarm Details:")
            Log.d(TAG, "  ├─ Reminder ID: $reminderId")
            Log.d(TAG, "  ├─ Title: $title")
            Log.d(TAG, "  ├─ Body: $body")
            Log.d(TAG, "  ├─ URL: $url")
            Log.d(TAG, "  ├─ Importance: $importance")
            Log.d(TAG, "  ├─ Current Time: $currentTime")
            Log.d(TAG, "  ├─ Scheduled Time: $scheduledTimeMillis")
            Log.d(TAG, "  └─ Delay: $delaySeconds seconds")
            
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            
            // ==================== التحقق من الصلاحيات ====================
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (!alarmManager.canScheduleExactAlarms()) {
                    Log.e(TAG, "❌ Cannot schedule exact alarms - Permission not granted")
                    Log.e(TAG, "❌ Please request permission first")
                    requestExactAlarmPermission()
                    return false
                } else {
                    Log.d(TAG, "✅ Exact alarm permission granted")
                }
            }
            
            // ==================== إلغاء الإنذار السابق ====================
            Log.d(TAG, "🗑️ Cancelling any existing alarm for ID: $reminderId")
            cancelAlarm(reminderId)
            
            // ==================== إنشاء Intent ====================
            val intent = Intent(this, AlarmReceiver::class.java).apply {
                action = ALARM_ACTION
                
                // إضافة البيانات
                putExtra(AlarmReceiver.EXTRA_REMINDER_ID, reminderId)
                putExtra(AlarmReceiver.EXTRA_TITLE, title)
                putExtra(AlarmReceiver.EXTRA_BODY, body)
                putExtra(AlarmReceiver.EXTRA_URL, url)
                putExtra(AlarmReceiver.EXTRA_IMPORTANCE, importance)
                
                // Flags مهمة لضمان تسليم الـ Intent
                addFlags(Intent.FLAG_RECEIVER_FOREGROUND)
            }
            
            Log.d(TAG, "📦 Intent created with action: $ALARM_ACTION")
            
            // ==================== إنشاء PendingIntent ====================
            val pendingIntent = PendingIntent.getBroadcast(
                this,
                reminderId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            Log.d(TAG, "🎫 PendingIntent created for reminderId: $reminderId")
            
            // ==================== جدولة الإنذار ====================
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                // استخدام setAlarmClock - الأكثر موثوقية
                val alarmClockInfo = AlarmManager.AlarmClockInfo(
                    scheduledTimeMillis,
                    pendingIntent
                )
                alarmManager.setAlarmClock(alarmClockInfo, pendingIntent)
                Log.d(TAG, "✅ Alarm scheduled using setAlarmClock (Most Reliable)")
                Log.d(TAG, "📱 Alarm will show in system clock app")
            } else {
                // للإصدارات الأقدم من Android 5.0
                alarmManager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    scheduledTimeMillis,
                    pendingIntent
                )
                Log.d(TAG, "✅ Alarm scheduled using setExact (Legacy)")
            }
            
            Log.d(TAG, "🎉 ========== ALARM SCHEDULED SUCCESSFULLY ==========")
            Log.d(TAG, "⏰ Alarm will trigger in $delaySeconds seconds")
            Log.d(TAG, "📅 At: ${java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date(scheduledTimeMillis))}")
            
            true
            
        } catch (e: SecurityException) {
            Log.e(TAG, "❌ ========== SECURITY EXCEPTION ==========")
            Log.e(TAG, "❌ Missing permissions: ${e.message}", e)
            false
        } catch (e: Exception) {
            Log.e(TAG, "❌ ========== ERROR SCHEDULING ALARM ==========")
            Log.e(TAG, "❌ Error: ${e.message}", e)
            e.printStackTrace()
            false
        }
    }

    /**
     * إلغاء إنذار محدد
     */
    private fun cancelAlarm(reminderId: Int) {
        try {
            Log.d(TAG, "🗑️ Cancelling alarm for reminder: $reminderId")
            
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            
            val intent = Intent(this, AlarmReceiver::class.java).apply {
                action = ALARM_ACTION
            }
            
            val pendingIntent = PendingIntent.getBroadcast(
                this,
                reminderId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            // إلغاء الإنذار
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
            
            Log.d(TAG, "✅ Alarm cancelled successfully")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error cancelling alarm: ${e.message}", e)
        }
    }

    /**
     * التحقق من إمكانية جدولة إنذارات دقيقة
     */
    private fun canScheduleExactAlarms(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val canSchedule = alarmManager.canScheduleExactAlarms()
            Log.d(TAG, "🔍 Can schedule exact alarms (Android 12+): $canSchedule")
            canSchedule
        } else {
            Log.d(TAG, "🔍 Can schedule exact alarms (Android < 12): true")
            true
        }
    }

    /**
     * طلب إذن جدولة الإنذارات الدقيقة
     */
    private fun requestExactAlarmPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                Log.d(TAG, "🔐 Opening exact alarm permission settings...")
                val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                startActivity(intent)
                Log.d(TAG, "📱 Permission settings opened")
            } catch (e: Exception) {
                Log.e(TAG, "❌ Error opening permission settings: ${e.message}", e)
                
                // محاولة فتح إعدادات التطبيق العامة
                try {
                    val fallbackIntent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = android.net.Uri.fromParts("package", packageName, null)
                    }
                    startActivity(fallbackIntent)
                    Log.d(TAG, "📱 Opened app settings as fallback")
                } catch (e2: Exception) {
                    Log.e(TAG, "❌ Error opening app settings: ${e2.message}", e2)
                }
            }
        }
    }

    /**
     * التحقق من إذن الإنذارات الدقيقة عند بدء التطبيق
     */
    private fun checkExactAlarmPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            if (!alarmManager.canScheduleExactAlarms()) {
                Log.w(TAG, "⚠️ ========== WARNING ==========")
                Log.w(TAG, "⚠️ Exact alarm permission NOT granted")
                Log.w(TAG, "⚠️ Alarms may not work properly")
                Log.w(TAG, "⚠️ User needs to grant permission")
            } else {
                Log.d(TAG, "✅ Exact alarm permission is granted")
            }
        } else {
            Log.d(TAG, "✅ Exact alarms supported (Android < 12)")
        }
    }

    /**
     * التحقق من تحسين البطارية
     */
    private fun checkBatteryOptimization() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val powerManager = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
                val packageName = packageName
                val isIgnoringBatteryOptimizations = powerManager.isIgnoringBatteryOptimizations(packageName)
                
                if (!isIgnoringBatteryOptimizations) {
                    Log.w(TAG, "⚠️ ========== BATTERY OPTIMIZATION WARNING ==========")
                    Log.w(TAG, "⚠️ App is subject to battery optimization")
                    Log.w(TAG, "⚠️ Alarms may not work in background")
                    Log.w(TAG, "⚠️ Consider requesting to ignore battery optimization")
                } else {
                    Log.d(TAG, "✅ App is ignoring battery optimization")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error checking battery optimization: ${e.message}", e)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.d(TAG, "🔄 ========== ON NEW INTENT ==========")
        Log.d(TAG, "📱 Action: ${intent.action}")
        
        // معالجة البيانات المشتركة
        if (intent.action == Intent.ACTION_SEND) {
            intent.getStringExtra(Intent.EXTRA_TEXT)?.let { text ->
                Log.d(TAG, "📝 New shared text received: $text")
                flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                    val channel = MethodChannel(messenger, SHARED_DATA_CHANNEL)
                    channel.invokeMethod("handleSharedText", text)
                    Log.d(TAG, "✅ Shared text sent to Flutter")
                }
            }
        }
         // داخل onCreate و onNewIntent (نفس الكود في المكانين)
if (intent.hasExtra("open_reminder_detail") && intent.getBooleanExtra("open_reminder_detail", false)) {
    val reminderId = intent.getIntExtra("reminder_id", -1)
    Log.d(TAG, "🎯 Deep link: Opening ReminderDetailScreen for ID: $reminderId")

    // إرسال event إلى Flutter
    flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
        val channel = MethodChannel(messenger, "com.saadmohammed2000.flex_reminder/deeplink")
        channel.invokeMethod("openReminderDetail", reminderId)
    }
}
        // معالجة الإشعارات
        val fromNotification = intent.getBooleanExtra("from_notification", false)
        if (fromNotification) {
            val reminderId = intent.getIntExtra(AlarmReceiver.EXTRA_REMINDER_ID, -1)
            val url = intent.getStringExtra(AlarmReceiver.EXTRA_URL)
            Log.d(TAG, "📬 Opened from notification - Reminder ID: $reminderId, URL: $url")
        }
    }

    override fun onResume() {
        super.onResume()
        Log.d(TAG, "▶️ App resumed")
        
        // إعادة التحقق من الأذونات
        checkExactAlarmPermission()
    }

    override fun onDestroy() {
        Log.d(TAG, "💀 App destroyed")
        super.onDestroy()
    }
}