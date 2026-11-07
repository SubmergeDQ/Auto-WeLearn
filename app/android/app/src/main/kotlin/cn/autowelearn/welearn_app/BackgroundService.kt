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
 *
 * 通知内容由 Dart 侧通过 `updateTask` 同步：运行时显示第几节、本节剩余时间，
 * 并提供「开始 / 停止」按钮；停止时点击通知可直接回到应用。
 */
class BackgroundService : Service() {
    companion object {
        const val EXTRA_KEEP_AWAKE = "keepAwake"
        const val EXTRA_PERSISTENT = "persistent"
        const val ACTION_START_TASK = "cn.autowelearn.welearn.ACTION_START_TASK"
        const val ACTION_STOP_TASK = "cn.autowelearn.welearn.ACTION_STOP_TASK"

        private const val CHANNEL_ID = "welearn_background"
        private const val NOTIFICATION_ID = 1001
        private const val WAKE_LOCK_TAG = "WeLearn:BackgroundRun"

        @Volatile
        private var instance: BackgroundService? = null

        @Volatile
        private var taskRunning = false

        @Volatile
        private var taskCurrent = 0

        @Volatile
        private var taskTotal = 0

        @Volatile
        private var taskText = ""

        @Volatile
        private var taskDetail = ""

        /** Dart 侧每次进度变化（约每秒一次）调用，刷新常驻通知。 */
        fun updateTask(
            running: Boolean,
            current: Int,
            total: Int,
            text: String,
            detail: String,
        ) {
            taskRunning = running
            taskCurrent = current
            taskTotal = total
            taskText = text
            taskDetail = detail
            instance?.refreshNotification()
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var persistent = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannel()
    }

    override fun onDestroy() {
        instance = null
        releaseWakeLock()
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val awake = intent?.getBooleanExtra(EXTRA_KEEP_AWAKE, false) ?: false
        persistent = intent?.getBooleanExtra(EXTRA_PERSISTENT, false) ?: false

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

    /** 任务进度变化时更新通知；常驻开关关闭时不显示。 */
    private fun refreshNotification() {
        if (!persistent) return
        try {
            val manager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(NOTIFICATION_ID, buildNotification())
        } catch (_: Exception) {
            // 通知权限被撤销时静默降级，任务本身继续运行
        }
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
                description = "任务在后台运行时显示进度与开始 / 停止按钮"
                setSound(null, null)
                enableVibration(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun actionIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, NotificationActionReceiver::class.java).apply {
            this.action = action
        }
        val mutability =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        return PendingIntent.getBroadcast(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or mutability,
        )
    }

    @Suppress("DEPRECATION")
    private fun buildNotification(): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val mutabilityFlag =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val pending = PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or mutabilityFlag,
        )

        val title = if (taskRunning) "WeLearn 助手 · 正在运行" else "WeLearn 助手在后台运行"
        val text = if (taskRunning) {
            taskText.ifEmpty { "任务进行中，点此回到应用" }
        } else {
            "后台常驻中，点此回到应用"
        }
        val detail = if (taskRunning) taskDetail else "任务未运行"

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        builder
            .setContentTitle(title)
            .setContentText(text)
            .setSubText(detail)
            .setSmallIcon(R.drawable.ic_stat_welearn)
            .setContentIntent(pending)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setShowWhen(false)
            .setStyle(Notification.BigTextStyle().bigText("$text\n$detail"))

        if (taskRunning && taskTotal > 0) {
            builder.setProgress(taskTotal, taskCurrent, false)
        }
        if (taskRunning) {
            builder.addAction(
                Notification.Action.Builder(
                    R.drawable.ic_action_stop,
                    "停止",
                    actionIntent(ACTION_STOP_TASK, 2),
                ).build(),
            )
        } else {
            builder.addAction(
                Notification.Action.Builder(
                    R.drawable.ic_action_start,
                    "开始",
                    actionIntent(ACTION_START_TASK, 1),
                ).build(),
            )
        }
        return builder.build()
    }
}
