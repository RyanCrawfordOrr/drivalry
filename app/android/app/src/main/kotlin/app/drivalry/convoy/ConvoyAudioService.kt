package app.drivalry.convoy

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import app.drivalry.MainActivity
import app.drivalry.R

/**
 * Keeps the process alive and the microphone usable while the convoy radio is
 * on (docs/10 §4): a foreground service of type microphone|mediaPlayback with a
 * quiet "Convoy radio is on" notification and a Stop action. It does no audio
 * work itself; WebRTC runs in the Flutter engine.
 */
class ConvoyAudioService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            // The user tapped Stop on the notification: tell the plugin so Dart
            // tears the mesh down, then go away.
            sendBroadcast(Intent(ACTION_STOPPED).setPackage(packageName))
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        ensureChannel()
        val types = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
        } else {
            0
        }
        ServiceCompat.startForeground(this, NOTIFICATION_ID, buildNotification(), types)
        // Not sticky: without the Flutter engine there is nothing to keep alive.
        return START_NOT_STICKY
    }

    private fun ensureChannel() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Convoy radio", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Shown while the convoy push-to-talk radio is on"
                    setSound(null, null)
                    enableVibration(false)
                },
            )
        }
    }

    private fun buildNotification(): Notification {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stop = PendingIntent.getService(
            this,
            1,
            Intent(this, ConvoyAudioService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_tracking)
            .setContentTitle("Convoy radio is on")
            .setContentText("Hold the button in Drivalry to talk to your convoy.")
            .setOngoing(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setContentIntent(open)
            .addAction(0, "Stop", stop)
            .build()
    }

    companion object {
        const val CHANNEL_ID = "convoy"
        const val NOTIFICATION_ID = 7202
        const val ACTION_STOP = "app.drivalry.convoy.STOP"
        const val ACTION_STOPPED = "app.drivalry.convoy.STOPPED"

        fun start(context: Context) {
            context.startForegroundService(Intent(context, ConvoyAudioService::class.java))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ConvoyAudioService::class.java))
        }
    }
}
