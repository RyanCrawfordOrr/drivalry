package app.drivalry

import app.drivalry.convoy.ConvoyAudioPlugin
import app.drivalry.tracking.TrackingPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var tracking: TrackingPlugin? = null
    private var convoyAudio: ConvoyAudioPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        tracking = TrackingPlugin.attach(this, flutterEngine)
        convoyAudio = ConvoyAudioPlugin.attach(this, flutterEngine)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        tracking?.detach()
        tracking = null
        convoyAudio?.detach()
        convoyAudio = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        tracking?.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}
