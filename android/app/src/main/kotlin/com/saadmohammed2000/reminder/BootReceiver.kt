package com.saadmohammed2000.flex_reminder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import android.app.AlarmManager
import android.app.PendingIntent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

class BootReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TAG = "BootReceiver"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val SCHEDULED_REMINDERS_KEY = "flutter.scheduled_reminders"
        private const val FCM_DATA_KEY = "flutter.fcm_data"
        const val ALARM_ACTION = "ALARM_ACTION" // إضافة هذا الثابت
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "📱 ========== BOOT RECEIVER TRIGGERED ==========")
        Log.d(TAG, "📱 Action: ${intent.action}")
        
        // ✅ معالجة أحداث الإقلاع والتحديث فقط
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            Intent.ACTION_REBOOT,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                Log.d(TAG, "🔄 Device booted or app updated - rescheduling alarms")
                rescheduleAlarms(context)
                restoreFcmData(context)
                startForegroundService(context)
            }
            else -> {
                Log.d(TAG, "⚠️ Unknown action, ignoring: ${intent.action}")
            }
        }
    }

    private fun rescheduleAlarms(context: Context) {
        try {
            Log.d(TAG, "📋 Reading scheduled reminders from SharedPreferences...")
            
            // قراءة التذكيرات المجدولة من SharedPreferences
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val scheduledRemindersJson = prefs.getString(SCHEDULED_REMINDERS_KEY, null)
            
            if (scheduledRemindersJson.isNullOrEmpty()) {
                Log.d(TAG, "⚠️ No scheduled reminders found in SharedPreferences")
                return
            }

            Log.d(TAG, "📋 Found scheduled reminders data")
            
            // تحليل JSON وإعادة جدولة الإنذارات
            val remindersArray = JSONArray(scheduledRemindersJson)
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            
            // التحقق من الأذونات (Android 12+)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (!alarmManager.canScheduleExactAlarms()) {
                    Log.e(TAG, "❌ Cannot schedule exact alarms - permission not granted")
                    return
                }
            }
            
            val currentTime = System.currentTimeMillis()
            var rescheduledCount = 0
            
            for (i in 0 until remindersArray.length()) {
                try {
                    val reminder = remindersArray.getJSONObject(i)
                    
                    val reminderId = reminder.getInt("id")
                    val title = reminder.getString("title")
                    val body = reminder.optString("body", "حان وقت التذكير!")
                    val url = reminder.optString("url", "")
                    val importance = reminder.optString("importance", "medium")
                    val scheduledTime = reminder.getLong("scheduledTime")
                    
                    // جدولة فقط التذكيرات المستقبلية
                    if (scheduledTime > currentTime) {
                        scheduleAlarm(
                            context, 
                            alarmManager,
                            reminderId, 
                            title, 
                            body, 
                            url, 
                            importance, 
                            scheduledTime
                        )
                        rescheduledCount++
                        Log.d(TAG, "✅ Rescheduled reminder #$reminderId: $title")
                    } else {
                        Log.d(TAG, "⏭️ Skipped past reminder #$reminderId: $title")
                    }
                    
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Error processing reminder at index $i: ${e.message}")
                }
            }
            
            Log.d(TAG, "🎉 Successfully rescheduled $rescheduledCount alarms")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error rescheduling alarms: ${e.message}", e)
        }
    }

    private fun restoreFcmData(context: Context) {
        try {
            Log.d(TAG, "📋 Restoring FCM data from SharedPreferences...")
            
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val fcmDataJson = prefs.getString(FCM_DATA_KEY, null)
            
            if (fcmDataJson.isNullOrEmpty()) {
                Log.d(TAG, "⚠️ No FCM data found in SharedPreferences")
                return
            }
            
            // إرسال البيانات إلى Flutter
            val intent = Intent("FCM_DATA_RESTORED").apply {
                setPackage(context.packageName)
                putExtra("fcm_data", fcmDataJson)
            }
            context.sendBroadcast(intent)
            
            Log.d(TAG, "✅ FCM data restored and sent to Flutter")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error restoring FCM data: ${e.message}", e)
        }
    }

    private fun startForegroundService(context: Context) {
        try {
            Log.d(TAG, "🚀 Starting FCM Foreground Service...")
            
            val serviceIntent = Intent(context, FCMForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
            
            Log.d(TAG, "✅ FCM Foreground Service started")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error starting foreground service: ${e.message}", e)
        }
    }

    private fun scheduleAlarm(
        context: Context,
        alarmManager: AlarmManager,
        reminderId: Int,
        title: String,
        body: String,
        url: String,
        importance: String,
        scheduledTimeMillis: Long
    ) {
        try {
            // إنشاء Intent للإنذار
            val intent = Intent(context, AlarmReceiver::class.java).apply {
                action = ALARM_ACTION // استخدام الثابت المحدد
                putExtra(AlarmReceiver.EXTRA_REMINDER_ID, reminderId)
                putExtra(AlarmReceiver.EXTRA_TITLE, title)
                putExtra(AlarmReceiver.EXTRA_BODY, body)
                putExtra(AlarmReceiver.EXTRA_URL, url)
                putExtra(AlarmReceiver.EXTRA_IMPORTANCE, importance)
                addFlags(Intent.FLAG_RECEIVER_FOREGROUND)
            }
            
            // إنشاء PendingIntent
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                reminderId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            // جدولة الإنذار
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                val alarmClockInfo = AlarmManager.AlarmClockInfo(
                    scheduledTimeMillis,
                    pendingIntent
                )
                alarmManager.setAlarmClock(alarmClockInfo, pendingIntent)
            } else {
                alarmManager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    scheduledTimeMillis,
                    pendingIntent
                )
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error scheduling alarm for reminder #$reminderId: ${e.message}")
        }
    }
}