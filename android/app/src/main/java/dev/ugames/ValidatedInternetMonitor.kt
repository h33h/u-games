package dev.ugames

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper

/** Captive portals and networks with no validated internet use the offline surface. */
class ValidatedInternetMonitor(context: Context, private val changed: (Boolean) -> Unit) {
    private val manager = context.getSystemService(ConnectivityManager::class.java)
    private val main = Handler(Looper.getMainLooper())

    @Volatile var available = hasInternet()
        private set
    private var registered = false
    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = refresh()
        override fun onLost(network: Network) = refresh()
        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) =
            refresh()
    }

    fun start() {
        if (registered) return
        manager.registerDefaultNetworkCallback(callback)
        registered = true
        refresh()
    }

    fun stop() {
        if (registered) manager.unregisterNetworkCallback(callback)
        registered = false
        main.removeCallbacksAndMessages(null)
    }

    private fun hasInternet(): Boolean =
        manager.getNetworkCapabilities(manager.activeNetwork)?.let {
            it.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                it.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        } ?: false

    private fun refresh() {
        val value = hasInternet()
        main.post {
            if (available != value) {
                available = value
                changed(value)
            }
        }
    }
}
