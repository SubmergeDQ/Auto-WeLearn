package cn.autowelearn.welearn_app

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * 手机端的「托盘替身」：前台服务常驻通知 + Partial Wake Lock。
 *
 * 只用 PARTIAL_WAKE_LOCK（CPU 保持、屏幕可以关），不要全量 WakeLock。
 * 两个开关独立：关掉常驻通知时服务仍在，只是把通知移除。
 */
class BackgroundService : Service() {
    companion object {
        const val EXTRA_KEEP_AWAKE = "keepAwake"
        const val EXTRA_PERSISTENT = "persistent"
        private const val CHANNEL_ID = "welearn_background"
        private const val NOTIFICATION_ID = 1001
        private const val WAKE_LOCK_TAG = "WeLearn:BackgroundRun"
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    @Suppress("DEPRECATION")
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val awake = intent?.getBooleanExtra(EXTRA_KEEP_AWAKE, false) ?: false
        val persistent = intent?.getBooleanExtra(EXTRA_PERSISTENT, false) ?: false

        // Android 8+ 用 startForegroundService 启动后，必须在几秒内调用
        // startForeground，否则系统直接杀掉应用。即使随后要移除通知也要先调用。
        startForeground(NOTIFICATION_ID, buildNotification())
        if (!persistent) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                stopForeground(true)
            }
        }

        if (awake) acquireWakeLock() else releaseWakeLock()
        if (!awake && !persistent) {
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    @SuppressLint("WakelockTimeout")
    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG).apply {
            setReferenceCounted(false)
        }
        try {
            wakeLock?.acquire()
        } catch (security: SecurityException) {
            // 没有 WAKE_LOCK 权限时降级为普通后台运行
            wakeLock = null
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (runtime: RuntimeException) {
            // 锁已被系统回收，忽略
        }
        wakeLock = null
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "后台运行",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "任务在后台运行时显示常驻通知"
                setSound(null, null)
                enableVibration(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    @Suppress("DEPRECATION")
    private fun buildNotification(): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val mutabilityFlag =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or mutabilityFlag
        val pending = PendingIntent.getActivity(this, 0, launch, flags)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("WeLearn 助手在后台运行")
            .setContentText("任务进行中，点此回到应用")
            .setSmallIcon(R.drawable.ic_stat_welearn)
            .setContentIntent(pending)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }
}
