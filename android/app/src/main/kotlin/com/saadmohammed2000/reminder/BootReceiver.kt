package com.saadmohammed2000.flex_reminder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import android.app.AlarmManager
import android.app.PendingIntent
import android.os.Build

class BootReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TAG = "BootReceiver"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val SCHEDULED_REMINDERS_KEY = "flutter.scheduled_reminders"
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "📱 BootReceiver triggered with action: ${intent.action}")
        
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                Log.d(TAG, "🔄 Rescheduling alarms after boot/update")
                rescheduleAlarms(context)
            }
        }
    }

    private fun rescheduleAlarms(context: Context) {
        try {
            // قراءة التذكيرات المجدولة من SharedPreferences
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val scheduledRemindersJson = prefs.getString(SCHEDULED_REMINDERS_KEY, null)
            
            if (scheduledRemindersJson == null) {
                Log.d(TAG, "⚠️ No scheduled reminders found")
                return
            }

            Log.d(TAG, "📋 Found scheduled reminders: $scheduledRemindersJson")
            
            // هنا يمكنك تحليل JSON وإعادة جدولة الإنذارات
            // مثال بسيط - يجب تكييفه حسب بنية بياناتك
            
            // ملاحظة: هذا مثال بسيط. قد تحتاج إلى تخزين معلومات أكثر
            // مثل العنوان، URL، الأهمية، إلخ في SharedPreferences
            
            Log.d(TAG, "✅ Alarms rescheduling initiated")
            
            // بدلاً من ذلك، يمكنك إطلاق التطبيق في الخلفية لإعادة الجدولة
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra("reschedule_alarms", true)
            }
            context.startActivity(launchIntent)
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error rescheduling alarms: ${e.message}", e)
        }
    }
}