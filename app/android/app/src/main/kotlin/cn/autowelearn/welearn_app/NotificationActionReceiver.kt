package cn.autowelearn.welearn_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 通知栏「开始 / 停止」按钮的接收器。
 *
 * 转发给正在运行的 Flutter 引擎；如果界面已经销毁，就把应用拉回前台，
 * 由用户在界面上重新操作，避免在无引擎时假装成功。
 */
class NotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = when (intent.action) {
            BackgroundService.ACTION_START_TASK -> "start"
            BackgroundService.ACTION_STOP_TASK -> "stop"
            else -> return
        }
        if (MainActivity.sendTaskAction(action)) return

        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: return
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        context.startActivity(launch)
    }
}
