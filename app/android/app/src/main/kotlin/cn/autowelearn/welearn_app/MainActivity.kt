package cn.autowelearn.welearn_app

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

/**
 * 手机端「保持后台运行 / 任务栏常驻」的原生入口。
 *
 * 桌面端靠托盘，安卓上等价物是 Wake Lock + 前台服务常驻通知。
 * Flutter 侧发布尔开关、任务进度与权限请求；权限与服务的生命周期都在原生处理。
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "cn.autowelearn.welearn/background"
        private const val REQ_NOTIFICATION = 1001

        @Volatile
        private var channel: MethodChannel? = null

        /**
         * 通知栏按钮的点击由 [NotificationActionReceiver] 转发到这里。
         * 返回 false 表示 Flutter 侧已销毁，调用方应把应用拉回前台。
         */
        fun sendTaskAction(action: String): Boolean {
            val current = channel ?: return false
            Handler(Looper.getMainLooper()).post {
                current.invokeMethod("taskAction", action)
            }
            return true
        }
    }

    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = methodChannel
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setMode" -> {
                    val awake = call.argument<Boolean>("keepAwake") ?: false
                    val persistent = call.argument<Boolean>("persistent") ?: false
                    applyMode(awake, persistent)
                    result.success(null)
                }
                "status" -> result.success(statusMap())
                "updateTask" -> {
                    BackgroundService.updateTask(
                        running = call.argument<Boolean>("running") ?: false,
                        current = call.argument<Int>("current") ?: 0,
                        total = call.argument<Int>("total") ?: 0,
                        text = call.argument<String>("text") ?: "",
                        detail = call.argument<String>("detail") ?: "",
                    )
                    result.success(null)
                }
                // 会等用户在系统弹窗里选完再返回，界面不假装申请成功
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                        hasPermission(Manifest.permission.POST_NOTIFICATIONS)
                    ) {
                        result.success(true)
                    } else if (pendingPermissionResult != null) {
                        result.success(false)
                    } else {
                        pendingPermissionResult = result
                        requestPermissions(
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            REQ_NOTIFICATION,
                        )
                    }
                }
                "requestIgnoreBatteryOptimizations" -> {
                    openBatteryOptimizationSettings()
                    result.success(null)
                }
                "openAutoStartSettings" -> {
                    openAutoStartSettings()
                    result.success(null)
                }
                "openAppSettings" -> {
                    openAppDetailsSettings()
                    result.success(null)
                }
                "installApk" -> {
                    val path = call.argument<String>("path") ?: ""
                    result.success(installApk(path))
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        channel = null
        super.onDestroy()
    }

    private fun applyMode(awake: Boolean, persistent: Boolean) {
        val intent = Intent(this, BackgroundService::class.java).apply {
            putExtra(BackgroundService.EXTRA_KEEP_AWAKE, awake)
            putExtra(BackgroundService.EXTRA_PERSISTENT, persistent)
        }
        if (!awake && !persistent) {
            stopService(intent)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun hasPermission(name: String): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            checkSelfPermission(name) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }

    private fun isBatteryUnrestricted(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun statusMap(): Map<String, Boolean> = mapOf(
        // WAKE_LOCK 是安装时权限，声明后即授予；这里仍读真实状态给界面显示
        "wakeLock" to hasPermission(Manifest.permission.WAKE_LOCK),
        "notification" to
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                hasPermission(Manifest.permission.POST_NOTIFICATIONS)
            } else {
                true
            },
        // true = 已加入电池优化白名单（无限制）
        "batteryOptimized" to isBatteryUnrestricted(),
    )

    /** 打开「电池优化」授权弹窗；系统没有该页面时退回电池优化列表。 */
    private fun openBatteryOptimizationSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || isBatteryUnrestricted()) return
        try {
            startActivity(
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:$packageName"),
                ),
            )
        } catch (_: ActivityNotFoundException) {
            try {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (_: Exception) {
                openAppDetailsSettings()
            }
        }
    }

    /** 厂商自启动管理页的常见入口，识别不到就退回应用详情页。 */
    private fun openAutoStartSettings() {
        val manufacturer = Build.MANUFACTURER.lowercase(Locale.getDefault())
        val candidates = mutableListOf<Intent>()
        when {
            manufacturer.contains("xiaomi") || manufacturer.contains("redmi") -> {
                candidates += Intent().setComponent(
                    ComponentName(
                        "com.miui.securitycenter",
                        "com.miui.permcenter.autostart.AutoStartManagementActivity",
                    ),
                )
                candidates += Intent("miui.intent.action.OP_AUTO_START")
                    .addCategory(Intent.CATEGORY_DEFAULT)
            }
            manufacturer.contains("huawei") || manufacturer.contains("honor") -> {
                candidates += Intent().setComponent(
                    ComponentName(
                        "com.huawei.systemmanager",
                        "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
                    ),
                )
            }
            manufacturer.contains("oppo") || manufacturer.contains("realme") -> {
                candidates += Intent().setComponent(
                    ComponentName(
                        "com.coloros.safecenter",
                        "com.coloros.safecenter.startupapp.StartupAppListActivity",
                    ),
                )
                candidates += Intent().setComponent(
                    ComponentName(
                        "com.oppo.safe",
                        "com.oppo.safe.permission.startup.StartupAppListActivity",
                    ),
                )
            }
            manufacturer.contains("vivo") || manufacturer.contains("iqoo") -> {
                candidates += Intent().setComponent(
                    ComponentName(
                        "com.vivo.permissionmanager",
                        "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
                    ),
                )
            }
            manufacturer.contains("meizu") -> {
                candidates += Intent().setComponent(
                    ComponentName(
                        "com.meizu.safe",
                        "com.meizu.safe.permission.SmartBGActivity",
                    ),
                )
            }
        }
        for (intent in candidates) {
            try {
                if (intent.resolveActivity(packageManager) != null) {
                    startActivity(intent)
                    return
                }
            } catch (_: Exception) {
                // 继续尝试下一个厂商入口
            }
        }
        openAppDetailsSettings()
    }

    private fun openAppDetailsSettings() {
        try {
            startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName"),
                ),
            )
        } catch (_: Exception) {
            // 极少数定制系统没有详情页，忽略
        }
    }

    /**
     * 调起系统安装器安装已下载的 APK。
     * 返回 `started` / `permission` / `failed`，让界面给出对应提示。
     */
    private fun installApk(path: String): String {
        val file = File(path)
        if (!file.exists()) return "failed"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            try {
                startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName"),
                    ),
                )
            } catch (_: Exception) {
                openAppDetailsSettings()
            }
            return "permission"
        }
        return try {
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file,
            )
            startActivity(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_ACTIVITY_NEW_TASK,
                    )
                },
            )
            "started"
        } catch (_: Exception) {
            "failed"
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_NOTIFICATION) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }
}
