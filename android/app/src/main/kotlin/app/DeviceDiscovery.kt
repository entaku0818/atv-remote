package app

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper

/**
 * Discovers Android TVs advertising _androidtvremote2._tcp via mDNS/NSD.
 * Android-only counterpart to DeviceDiscovery.swift (which uses NWBrowser);
 * the atvremotekit module stays pure JVM, so this lives in the app module.
 */
class DeviceDiscovery(context: Context) {
    data class Device(val name: String, val host: String?, val port: Int?)

    private val appContext = context.applicationContext
    private val nsdManager = appContext.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val wifiManager = appContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    private val mainHandler = Handler(Looper.getMainLooper())

    private var multicastLock: WifiManager.MulticastLock? = null
    private var discoveryListener: NsdManager.DiscoveryListener? = null
    private val devices = linkedMapOf<String, Device>()
    private var onUpdate: ((List<Device>) -> Unit)? = null

    fun start(onUpdate: (List<Device>) -> Unit) {
        this.onUpdate = onUpdate
        devices.clear()

        multicastLock = wifiManager.createMulticastLock("atvremote-discovery").apply {
            setReferenceCounted(true)
            acquire()
        }

        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) {}
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onServiceFound(serviceInfo: NsdServiceInfo) = resolve(serviceInfo)
            override fun onServiceLost(serviceInfo: NsdServiceInfo) {
                devices.remove(serviceInfo.serviceName)
                notifyUpdate()
            }
        }
        discoveryListener = listener
        nsdManager.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
    }

    fun stop() {
        discoveryListener?.let {
            try {
                nsdManager.stopServiceDiscovery(it)
            } catch (_: IllegalArgumentException) {
                // Already stopped.
            }
        }
        discoveryListener = null
        try {
            multicastLock?.release()
        } catch (_: RuntimeException) {
            // Already released.
        }
        multicastLock = null
    }

    @Suppress("DEPRECATION") // NsdManager.resolveService(NsdServiceInfo, ResolveListener) is deprecated since API 34;
    // the API 34+ registerServiceInfoCallback replacement needs minSdk 34, which this app doesn't require yet.
    private fun resolve(serviceInfo: NsdServiceInfo) {
        nsdManager.resolveService(
            serviceInfo,
            object : NsdManager.ResolveListener {
                override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
                override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                    devices[serviceInfo.serviceName] = Device(
                        name = serviceInfo.serviceName,
                        host = serviceInfo.host?.hostAddress,
                        port = serviceInfo.port,
                    )
                    notifyUpdate()
                }
            },
        )
    }

    private fun notifyUpdate() {
        val snapshot = devices.values.sortedBy { it.name }
        mainHandler.post { onUpdate?.invoke(snapshot) }
    }

    companion object {
        private const val SERVICE_TYPE = "_androidtvremote2._tcp."
    }
}
