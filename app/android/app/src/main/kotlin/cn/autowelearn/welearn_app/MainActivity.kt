package cn.autowelearn.welearn_app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 手机端「保持后台运行 / 任务栏常驻」的原生入口。
 *
 * 桌面端靠托盘，安卓上等价物是 Wake Lock + 前台服务常驻通知。
 * Flutter 侧只发两个布尔开关，权限与服务的生命周期都在原生处理。
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "cn.autowelearn.welearn/background"
        private const val REQ_NOTIFICATION = 1001
    }

    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setMode" -> {
                        val awake = call.argument<Boolean>("keepAwake") ?: false
                        val persistent = call.argument<Boolean>("persistent") ?: false
                        applyMode(awake, persistent)
                        result.success(null)
                    }
                    "status" -> result.success(statusMap())
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
                    else -> result.notImplemented()
                }
            }
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

    private fun statusMap(): Map<String, Boolean> = mapOf(
        // WAKE_LOCK 是安装时权限，声明后即授予；这里仍读真实状态给界面显示
        "wakeLock" to hasPermission(Manifest.permission.WAKE_LOCK),
        "notification" to
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                hasPermission(Manifest.permission.POST_NOTIFICATIONS)
            } else {
                true
            },
    )

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
