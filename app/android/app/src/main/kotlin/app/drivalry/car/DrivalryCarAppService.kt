package app.drivalry.car

import android.content.Intent
import android.content.pm.ApplicationInfo
import androidx.car.app.CarAppService
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator

/**
 * Android Auto entry point (docs/04 §3): a Point-of-Interest category app whose
 * screens are convoy members and stops. The car host binds this service directly, so
 * it must work with no Flutter engine alive; everything it shows comes from [CarState].
 */
class DrivalryCarAppService : CarAppService() {
    override fun createHostValidator(): HostValidator =
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            // Debug builds talk to the Desktop Head Unit, which is not on the allowlist.
            HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
        } else {
            HostValidator.Builder(applicationContext)
                .addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample)
                .build()
        }

    override fun onCreateSession(): Session = DrivalryCarSession()
}

class DrivalryCarSession : Session() {
    override fun onCreateScreen(intent: Intent): Screen {
        CarState.init(carContext)
        return MainTabScreen(carContext)
    }
}
