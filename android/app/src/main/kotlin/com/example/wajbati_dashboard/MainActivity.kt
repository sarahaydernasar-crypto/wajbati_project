package com.example.wajbati_dashboard

import io.flutter.embedding.android.FlutterActivity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel("orders", "تحديثات الطلبات", NotificationManager.IMPORTANCE_HIGH)
            channel.description = "جاهزية الوجبات وتحديث حالة الطلب"
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}
