// FCM 下行入口：新 token 与消息都先到这里，再转交插件单例。
// 应用没在跑（插件单例为空）时静默丢弃：通知本身由系统托盘显示，路由等下次进应用再说。
package app.sensen.push

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class SensenMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        SensenPushPlugin.instance?.onToken(token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        SensenPushPlugin.instance?.onNotification(message.data, false)
    }
}
