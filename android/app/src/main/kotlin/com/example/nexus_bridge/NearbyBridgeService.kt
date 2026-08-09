package com.example.nexus_bridge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import android.util.Base64
import androidx.core.content.ContextCompat
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.AdvertisingOptions
import com.google.android.gms.nearby.connection.ConnectionInfo
import com.google.android.gms.nearby.connection.ConnectionsClient
import com.google.android.gms.nearby.connection.ConnectionsStatusCodes
import com.google.android.gms.nearby.connection.EndpointDiscoveryCallback
import com.google.android.gms.nearby.connection.Payload
import com.google.android.gms.nearby.connection.PayloadCallback
import com.google.android.gms.nearby.connection.PayloadTransferUpdate
import com.google.android.gms.nearby.connection.Strategy
import com.google.android.gms.nearby.connection.ConnectionLifecycleCallback
import com.google.android.gms.nearby.connection.ConnectionResolution
import org.json.JSONObject
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.spec.X509EncodedKeySpec
import javax.crypto.KeyAgreement
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import java.util.Timer
import java.util.TimerTask

class NearbyBridgeService : Service() {
    private val TAG = "NearbyBridgeService"
    private lateinit var connectionsClient: ConnectionsClient
    private data class EndpointInfo(var endpointName: String, var lastSeenMs: Long, var connected: Boolean = false)
    private val endpoints = HashMap<String, EndpointInfo>()
    private val connectedEndpoints = HashSet<String>()
    private var isAdvertising = false
    private var isDiscovering = false
    private val pendingConnectionRetries = HashMap<String, Int>()
    private val pendingConnectionTimers = HashMap<String, Timer>()
    private val pendingJoinTimeoutTimers = HashMap<String, Timer>()
    private var heartbeatTimer: Timer? = null
    private var advertisingRestartTimer: Timer? = null
    private var lastCallback: String? = null
    private var lastNearbyError: String? = null
    // [DISCOVERY_DEBUG] Handler used to schedule periodic discovery restart
    private val discoveryRestartHandler = Handler(Looper.getMainLooper())
    private val discoveryRestartRunnable = Runnable {
        if (isDiscovering) {
            Log.d(TAG, "[DISCOVERY_DEBUG] Periodic restart: stopping discovery for refresh")
            stopDiscovery()
            startDiscovery()
        }
    }

    private fun getMissingNearbyPermissions(): List<String> {
        val sdkInt = Build.VERSION.SDK_INT
        val requiredPermissions = mutableListOf(
            Manifest.permission.ACCESS_WIFI_STATE,
            Manifest.permission.CHANGE_WIFI_STATE,
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        )

        if (sdkInt >= Build.VERSION_CODES.S) {
            requiredPermissions.addAll(
                listOf(
                    Manifest.permission.BLUETOOTH_SCAN,
                    Manifest.permission.BLUETOOTH_ADVERTISE,
                    Manifest.permission.BLUETOOTH_CONNECT,
                )
            )
        }

        if (sdkInt >= Build.VERSION_CODES.TIRAMISU) {
            requiredPermissions.add("android.permission.NEARBY_WIFI_DEVICES")
        }

        return requiredPermissions.filter { permission ->
            ContextCompat.checkSelfPermission(this, permission) != PackageManager.PERMISSION_GRANTED
        }
    }

    private fun hasNearbyPermissions(): Boolean {
        val missing = getMissingNearbyPermissions()
        if (missing.isNotEmpty()) {
            Log.e(TAG, "Nearby service missing runtime permissions: $missing")
            return false
        }
        return true
    }
    private val keyPairs = HashMap<String, java.security.KeyPair>()
    private val sessionKeys = HashMap<String, ByteArray>()
    private val pendingJoinRequests = HashMap<String, JSONObject>()
    private val pendingIncomingConnections = HashMap<String, String>()
    private val acl = HashMap<String, List<String>>()
    private val ongoingUploads = HashMap<String, java.io.RandomAccessFile>()
    private var cleanupTimer: Timer? = null
    private val random = SecureRandom()

    private val serviceId = "NEXUS_BRIDGE"
    private val maxConnectionAttempts = 5
    private val joinTimeoutMs = 25_000L
    private val connectionRetryMinMs = 1_500L
    private val connectionRetryMaxMs = 20_000L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        connectionsClient = Nearby.getConnectionsClient(this)
        logDebug("ConnectionsClient initialized")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val chanId = "nexus_bridge_channel"
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(chanId, "Nexus Bridge", NotificationManager.IMPORTANCE_LOW)
            nm.createNotificationChannel(channel)
            val notification = Notification.Builder(this, chanId)
                .setContentTitle("Nexus Bridge")
                .setContentText("Nearby bridge running")
                .setSmallIcon(android.R.drawable.stat_sys_download_done)
                .build()
            startForeground(101, notification)
        }
        // schedule periodic cleanup of orphaned .upload files
        try {
            cleanupTimer = Timer()
            cleanupTimer?.scheduleAtFixedRate(object : TimerTask() {
                override fun run() {
                    cleanOrphanUploads()
                }
            }, 5 * 60 * 1000L, 60 * 60 * 1000L) // start after 5m, repeat every hour
        } catch (e: Exception) {
            Log.w(TAG, "Failed to schedule cleanup timer: ${e.message}")
        }
    }

        override fun onDestroy() {
            super.onDestroy()
            Log.d(TAG, "NearbyBridgeService onDestroy: closing ${ongoingUploads.size} uploads")
            try {
                stopAdvertising()
            } catch (_: Exception) {
            }
            try {
                stopDiscovery()
            } catch (_: Exception) {
            }
            try {
                ongoingUploads.values.forEach { raf ->
                    try { raf.close() } catch (_: Exception) { }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Error closing uploads: ${e.message}")
            }
            ongoingUploads.clear()
            try {
                cleanupTimer?.cancel()
                cleanupTimer = null
            } catch (e: Exception) {
                Log.w(TAG, "Failed to cancel cleanup timer: ${e.message}")
            }
            cancelDiscoveryTimers()
            advertisingRestartTimer?.cancel()
            advertisingRestartTimer = null
            pendingConnectionTimers.values.forEach { it.cancel() }
            pendingConnectionTimers.clear()
            pendingJoinTimeoutTimers.values.forEach { it.cancel() }
            pendingJoinTimeoutTimers.clear()
        }

        private fun cleanOrphanUploads() {
            try {
                val dir = filesDir
                if (dir == null) return
                val now = System.currentTimeMillis()
                val cutoff = now - 12 * 60 * 60 * 1000L // 12 hours
                dir.listFiles()?.forEach { f ->
                    try {
                        if (f.name.endsWith(".upload")) {
                            val base = f.name.removeSuffix(".upload")
                            val mapped = ongoingUploads.keys.any { it.endsWith(":" + base) }
                            if (!mapped && f.lastModified() < cutoff) {
                                val ok = f.delete()
                                Log.d(TAG, "Deleted orphan upload ${f.name}: $ok")
                            }
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "Orphan check failed for ${f.name}: ${e.message}")
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "cleanOrphanUploads failed: ${e.message}")
            }
        }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.getStringExtra("action")
        when (action) {
            "startAdvertising" -> {
                val communityId = intent.getStringExtra("communityId")
                val name = intent.getStringExtra("name")
                startAdvertising(communityId ?: "", name ?: "Nexus Bridge")
            }
            "stopAdvertising" -> stopAdvertising()
            "startDiscovery" -> startDiscovery()
            "stopDiscovery" -> stopDiscovery()
            "sendJoinRequest" -> {
                val payload = intent.getSerializableExtra("payload") as? HashMap<String, Any>
                val target = intent.getStringExtra("hostDevice")
                logDebug("Action: sendJoinRequest to $target")
                if (payload != null && target != null) {
                    val endpointId = target
                    val joinPayload = JSONObject()
                    joinPayload.put("type", "JOIN_REQUEST")
                    joinPayload.put("payload", JSONObject(payload as Map<*, *>))
                    logDebug("Queued join request for $endpointId, pendingRequests count: ${pendingJoinRequests.size}")
                    queueJoinRequest(endpointId, joinPayload)
                } else {
                    logError("sendJoinRequest", "payload=$payload, target=$target")
                }
            }
            "respondJoin" -> {
                val response = intent.getSerializableExtra("response") as? HashMap<String, Any>
                val target = intent.getStringExtra("targetDevice")
                if (response != null && target != null) {
                    val endpointId = target
                    val joinResponse = JSONObject()
                    joinResponse.put("type", "JOIN_RESPONSE")
                    joinResponse.put("response", JSONObject(response as Map<*, *>))
                    try {
                        if ((response["accepted"] as? Boolean) == false) {
                            connectionsClient.rejectConnection(endpointId)
                            logDebug("Rejected connection for $endpointId after join denial")
                        } else {
                            connectionsClient.sendPayload(endpointId, Payload.fromBytes(joinResponse.toString().toByteArray(Charsets.UTF_8)))
                        }
                    } catch (e: Exception) {
                        logError("respondJoin", e)
                    }
                    // Persist granted rights for ACL if provided
                    try {
                        val respJo = JSONObject(response as Map<*, *>)
                        val granted = respJo.optJSONArray("granted_rights")
                        if (granted != null) {
                            val rightsList = mutableListOf<String>()
                            for (i in 0 until granted.length()) {
                                rightsList.add(granted.optString(i))
                            }
                            acl[endpointId] = rightsList
                            Log.d(TAG, "Stored ACL for $endpointId: $rightsList")
                        }
                    } catch (e: Exception) {
                        // ignore
                    }
                }
            }
            "sendControl" -> {
                val control = intent.getSerializableExtra("control") as? HashMap<String, Any>
                val target = intent.getStringExtra("target")
                if (control != null) {
                    val bytes = JSONObject(control as Map<*, *>).toString().toByteArray(Charsets.UTF_8)
                    if (target != null) {
                        if (connectedEndpoints.contains(target)) {
                            connectionsClient.sendPayload(target, Payload.fromBytes(bytes))
                        } else {
                            logError("sendControl", "Target $target not connected")
                        }
                    } else {
                        connectedEndpoints.forEach { eid -> connectionsClient.sendPayload(eid, Payload.fromBytes(bytes)) }
                    }
                }
            }
            "sendPayload" -> {
                val bytes = intent.getByteArrayExtra("bytes")
                val target = intent.getStringExtra("target")
                if (bytes != null) {
                    if (target != null) {
                        val endpointId = target
                        if (!connectedEndpoints.contains(endpointId)) {
                            logError("sendPayload", "Target $endpointId not connected")
                        } else {
                            val key = sessionKeys[endpointId]
                            if (key != null) {
                                try {
                                    val encrypted = encryptFrame(bytes, key)
                                    connectionsClient.sendPayload(endpointId, Payload.fromBytes(encrypted))
                                } catch (e: Exception) {
                                    Log.e(TAG, "Encryption failed: ${e.message}")
                                }
                            } else {
                                connectionsClient.sendPayload(endpointId, Payload.fromBytes(bytes))
                            }
                        }
                    } else {
                        connectedEndpoints.forEach { eid ->
                            val key = sessionKeys[eid]
                            if (key != null) {
                                try {
                                    val encrypted = encryptFrame(bytes, key)
                                    connectionsClient.sendPayload(eid, Payload.fromBytes(encrypted))
                                } catch (e: Exception) {
                                    Log.e(TAG, "Encryption failed: ${e.message}")
                                }
                            } else {
                                connectionsClient.sendPayload(eid, Payload.fromBytes(bytes))
                            }
                        }
                    }
                }
            }
        }
        return START_STICKY
    }

    private fun startAdvertising(communityId: String, name: String) {
        if (!hasNearbyPermissions()) {
            logError("Advertising", "Skipping advertising: required Nearby permissions are missing")
            return
        }
        if (isAdvertising) {
            logDebug("Advertising already running")
            sendFlutterEvent("onAdvertisingState", mapOf("running" to true))
            return
        }
        logDebug("Starting advertising as '$name'")
        val options = AdvertisingOptions.Builder().setStrategy(Strategy.P2P_CLUSTER).build()
        connectionsClient.startAdvertising(name, "NEXUS_BRIDGE", connectionLifecycleCallback, options)
            .addOnSuccessListener {
                isAdvertising = true
                logDebug("Advertising started successfully")
                sendFlutterEvent("onAdvertisingState", mapOf("running" to true))
            }
            .addOnFailureListener {
                logError("Advertising", it)
                isAdvertising = false
                sendFlutterEvent("onAdvertisingState", mapOf("running" to false))
            }
    }

    private fun stopAdvertising() {
        if (!isAdvertising) {
            logDebug("stopAdvertising called but advertising was not active")
            return
        }
        logDebug("Stopping advertising")
        connectionsClient.stopAdvertising()
        isAdvertising = false
        sendFlutterEvent("onAdvertisingState", mapOf("running" to false))
    }

    private fun startDiscovery() {
        val missingPermissions = getMissingNearbyPermissions()
        if (missingPermissions.isNotEmpty()) {
            val message = "Skipping discovery: required Nearby permissions are missing: $missingPermissions"
            logError("Discovery", message)
            sendFlutterEvent(
                "onDiscoveryState",
                mapOf(
                    "running" to false,
                    "error" to "MISSING_PERMISSIONS",
                    "missingPermissions" to missingPermissions
                )
            )
            return
        }
        if (isDiscovering) {
            logDebug("Discovery already running, ignoring duplicate start request")
            sendFlutterEvent("onDiscoveryState", mapOf("running" to true))
            return
        }
        // Remove all endpoints that are not part of an active connection.
        // Previously only removed entries flagged connected=false; stale connected=true
        // entries from prior sessions (service is START_STICKY) silently blocked re-discovery.
        val stale = endpoints.keys.filter { !connectedEndpoints.contains(it) }.toList()
        stale.forEach { endpoints.remove(it) }
        Log.d(TAG, "[DISCOVERY_DEBUG] startDiscovery: removed ${stale.size} stale endpoints, active=${connectedEndpoints.size}")
        cancelDiscoveryTimers()
        logDebug("Starting discovery")
        val options = com.google.android.gms.nearby.connection.DiscoveryOptions.Builder().setStrategy(Strategy.P2P_CLUSTER).build()
        connectionsClient.startDiscovery("NEXUS_BRIDGE", endpointDiscoveryCallback, options)
            .addOnSuccessListener {
                isDiscovering = true
                logDebug("Discovery started successfully")
                Log.d(TAG, "[DISCOVERY_DEBUG] startDiscovery success — scheduling restart in 30s")
                discoveryRestartHandler.postDelayed(discoveryRestartRunnable, 30_000L)
                sendFlutterEvent("onDiscoveryState", mapOf("running" to true))
            }
            .addOnFailureListener {
                logError("Discovery", it)
                isDiscovering = false
                sendFlutterEvent("onDiscoveryState", mapOf("running" to false))
            }
    }

    private fun stopDiscovery() {
        if (!isDiscovering) {
            logDebug("stopDiscovery called but discovery was not active")
            cancelDiscoveryTimers()
            return
        }
        logDebug("Stopping discovery")
        connectionsClient.stopDiscovery()
        isDiscovering = false
        cancelDiscoveryTimers()
        sendFlutterEvent("onDiscoveryState", mapOf("running" to false))
    }

    private fun handleNearbyFailure(operation: String, exception: Throwable) {
        if (exception is ApiException) {
            val statusCode = exception.statusCode
            Log.e(TAG, "$operation failed: ${getConnectionsStatusName(statusCode)} ($statusCode) - ${exception.message}")
        } else {
            Log.e(TAG, "$operation failed", exception)
        }
    }

    private fun getConnectionsStatusName(statusCode: Int): String {
        return when (statusCode) {
            ConnectionsStatusCodes.STATUS_OK -> "STATUS_OK"
            ConnectionsStatusCodes.STATUS_ERROR -> "STATUS_ERROR"
            ConnectionsStatusCodes.STATUS_NETWORK_NOT_CONNECTED -> "STATUS_NETWORK_NOT_CONNECTED"
            ConnectionsStatusCodes.STATUS_ALREADY_ADVERTISING -> "STATUS_ALREADY_ADVERTISING"
            ConnectionsStatusCodes.STATUS_ALREADY_DISCOVERING -> "STATUS_ALREADY_DISCOVERING"
            ConnectionsStatusCodes.STATUS_ALREADY_CONNECTED_TO_ENDPOINT -> "STATUS_ALREADY_CONNECTED_TO_ENDPOINT"
            ConnectionsStatusCodes.STATUS_CONNECTION_REJECTED -> "STATUS_CONNECTION_REJECTED"
            ConnectionsStatusCodes.STATUS_NOT_CONNECTED_TO_ENDPOINT -> "STATUS_NOT_CONNECTED_TO_ENDPOINT"
            ConnectionsStatusCodes.STATUS_BLUETOOTH_ERROR -> "STATUS_BLUETOOTH_ERROR"
            ConnectionsStatusCodes.STATUS_RADIO_ERROR -> "STATUS_RADIO_ERROR"
            ConnectionsStatusCodes.STATUS_ALREADY_HAVE_ACTIVE_STRATEGY -> "STATUS_ALREADY_HAVE_ACTIVE_STRATEGY"
            ConnectionsStatusCodes.STATUS_OUT_OF_ORDER_API_CALL -> "STATUS_OUT_OF_ORDER_API_CALL"
            ConnectionsStatusCodes.STATUS_ENDPOINT_UNKNOWN -> "STATUS_ENDPOINT_UNKNOWN"
            ConnectionsStatusCodes.STATUS_ENDPOINT_IO_ERROR -> "STATUS_ENDPOINT_IO_ERROR"
            ConnectionsStatusCodes.STATUS_PAYLOAD_IO_ERROR -> "STATUS_PAYLOAD_IO_ERROR"
            ConnectionsStatusCodes.MISSING_SETTING_LOCATION_MUST_BE_ON -> "MISSING_SETTING_LOCATION_MUST_BE_ON"
            ConnectionsStatusCodes.MISSING_PERMISSION_BLUETOOTH -> "MISSING_PERMISSION_BLUETOOTH"
            ConnectionsStatusCodes.MISSING_PERMISSION_BLUETOOTH_ADMIN -> "MISSING_PERMISSION_BLUETOOTH_ADMIN"
            ConnectionsStatusCodes.MISSING_PERMISSION_ACCESS_WIFI_STATE -> "MISSING_PERMISSION_ACCESS_WIFI_STATE"
            ConnectionsStatusCodes.MISSING_PERMISSION_CHANGE_WIFI_STATE -> "MISSING_PERMISSION_CHANGE_WIFI_STATE"
            ConnectionsStatusCodes.MISSING_PERMISSION_ACCESS_COARSE_LOCATION -> "MISSING_PERMISSION_ACCESS_COARSE_LOCATION"
            ConnectionsStatusCodes.MISSING_PERMISSION_RECORD_AUDIO -> "MISSING_PERMISSION_RECORD_AUDIO"
            ConnectionsStatusCodes.MISSING_PERMISSION_ACCESS_FINE_LOCATION -> "MISSING_PERMISSION_ACCESS_FINE_LOCATION"
            else -> "STATUS_UNKNOWN"
        }
    }

    private fun runOnMainThread(action: () -> Unit) {
        Handler(Looper.getMainLooper()).post {
            try {
                action()
            } catch (e: Throwable) {
                Log.e(TAG, "runOnMainThread failed", e)
            }
        }
    }

    private fun sendJoinRequestPayload(endpointId: String) {
        val pending = pendingJoinRequests[endpointId]
        if (pending != null) {
            logDebug("Sending queued join request to $endpointId")
            connectionsClient.sendPayload(endpointId, Payload.fromBytes(pending.toString().toByteArray(Charsets.UTF_8)))
        } else {
            logDebug("No pending join request for $endpointId")
        }
    }

    private fun queueJoinRequest(endpointId: String, joinPayload: JSONObject) {
        pendingJoinRequests[endpointId] = joinPayload
        cancelConnectionRetry(endpointId)
        cancelJoinTimeout(endpointId)
        pendingConnectionRetries.remove(endpointId)
        if (connectedEndpoints.contains(endpointId)) {
            logDebug("Already connected to $endpointId, sending join request immediately")
            sendJoinRequestPayload(endpointId)
            scheduleJoinTimeout(endpointId)
        } else {
            requestConnectionWithRetry(endpointId)
        }
    }

    private fun requestConnectionWithRetry(endpointId: String) {
        if (!pendingJoinRequests.containsKey(endpointId)) {
            logDebug("No pending join request for $endpointId to retry")
            return
        }

        if (connectedEndpoints.contains(endpointId)) {
            logDebug("Endpoint $endpointId already connected, delivering queued join request")
            sendJoinRequestPayload(endpointId)
            scheduleJoinTimeout(endpointId)
            return
        }

        val attempt = (pendingConnectionRetries[endpointId] ?: 0) + 1
        pendingConnectionRetries[endpointId] = attempt
        if (attempt > maxConnectionAttempts) {
            logError("RequestConnection", "Max retry attempts exceeded for $endpointId")
            pendingJoinRequests.remove(endpointId)
            cancelConnectionRetry(endpointId)
            sendFlutterEvent("onJoinRequestFailed", mapOf("endpointId" to endpointId, "reason" to "max_retries"))
            return
        }

        logDebug("Requesting connection to $endpointId attempt $attempt")
        connectionsClient.requestConnection(Build.MODEL ?: "Nexus Bridge", endpointId, connectionLifecycleCallback)
            .addOnSuccessListener {
                logDebug("Connection request initiated to $endpointId")
            }
            .addOnFailureListener {
                logError("RequestConnection", it)
                scheduleConnectionRetry(endpointId, attempt)
            }
    }

    private fun scheduleConnectionRetry(endpointId: String, attempt: Int) {
        cancelConnectionRetry(endpointId)
        val delayMs = (connectionRetryMinMs * attempt).coerceAtMost(connectionRetryMaxMs)
        logDebug("Scheduling connection retry to $endpointId in ${delayMs}ms")
        val timer = Timer()
        val task = object : TimerTask() {
            override fun run() {
                runOnMainThread {
                    requestConnectionWithRetry(endpointId)
                }
            }
        }
        timer.schedule(task, delayMs)
        pendingConnectionTimers[endpointId] = timer
    }

    private fun cancelConnectionRetry(endpointId: String) {
        pendingConnectionTimers.remove(endpointId)?.cancel()
        pendingConnectionRetries.remove(endpointId)
    }

    private fun scheduleJoinTimeout(endpointId: String) {
        cancelJoinTimeout(endpointId)
        val timer = Timer()
        val task = object : TimerTask() {
            override fun run() {
                runOnMainThread {
                    if (pendingJoinRequests.containsKey(endpointId)) {
                        logError("JoinTimeout", "No join response from $endpointId after ${joinTimeoutMs}ms")
                        pendingJoinRequests.remove(endpointId)
                        pendingIncomingConnections.remove(endpointId)
                        cancelConnectionRetry(endpointId)
                        stopConnection(endpointId)
                        sendFlutterEvent("onJoinTimeout", mapOf("endpointId" to endpointId))
                    }
                }
            }
        }
        timer.schedule(task, joinTimeoutMs)
        pendingJoinTimeoutTimers[endpointId] = timer
    }

    private fun cancelJoinTimeout(endpointId: String) {
        pendingJoinTimeoutTimers.remove(endpointId)?.cancel()
    }

    private fun markEndpointConnected(endpointId: String) {
        connectedEndpoints.add(endpointId)
        endpoints[endpointId]?.connected = true
    }

    private fun cleanupDisconnectedEndpoint(endpointId: String) {
        connectedEndpoints.remove(endpointId)
        endpoints.remove(endpointId)
        pendingIncomingConnections.remove(endpointId)
        keyPairs.remove(endpointId)
        sessionKeys.remove(endpointId)
        pendingJoinRequests.remove(endpointId)
        cancelConnectionRetry(endpointId)
        cancelJoinTimeout(endpointId)
    }

    private fun stopConnection(endpointId: String) {
        try {
            connectionsClient.disconnectFromEndpoint(endpointId)
        } catch (e: Exception) {
            Log.w(TAG, "stopConnection failed for $endpointId: ${e.message}")
        }
    }

    private fun sendEcdhHandshake(endpointId: String) {
        try {
            val kpg = KeyPairGenerator.getInstance("X25519")
            val kp = kpg.generateKeyPair()
            keyPairs[endpointId] = kp
            val pubB64 = Base64.encodeToString(kp.public.encoded, Base64.NO_WRAP)
            val jo = JSONObject()
            jo.put("type", "ECDH_INIT")
            jo.put("pub", pubB64)
            logDebug("Sending ECDH_INIT to $endpointId")
            connectionsClient.sendPayload(endpointId, Payload.fromBytes(jo.toString().toByteArray(Charsets.UTF_8)))
        } catch (e: Exception) {
            logError("ECDH handshake", e)
        }
    }

    private fun logDebug(message: String) {
        Log.d(TAG, message)
    }

    private fun logError(context: String, error: Any?) {
        when (error) {
            is Throwable -> {
                Log.e(TAG, "$context failed", error)
                handleNearbyFailure(context, error)
            }
            else -> Log.e(TAG, "$context failed: ${error?.toString()}")
        }
    }

    private fun sendFlutterEvent(method: String, payload: Map<String, Any?>) {
        runOnMainThread {
            try {
                NearbyBridgeModule.channelStatic?.invokeMethod(method, payload)
                    ?: Log.w(TAG, "Flutter channel missing while sending $method")
            } catch (e: Exception) {
                Log.w(TAG, "sendFlutterEvent failed for $method: ${e.message}")
            }
        }
    }

    private fun invokeFlutterCallback(method: String, payload: Map<String, Any?>) {
        runOnMainThread {
            try {
                NearbyBridgeModule.channelStatic?.invokeMethod(method, payload)
                    ?: Log.w(TAG, "Flutter channel missing while invoking $method")
            } catch (e: Exception) {
                Log.w(TAG, "invokeFlutterCallback failed for $method: ${e.message}")
            }
        }
    }

    private fun cancelDiscoveryTimers() {
        discoveryRestartHandler.removeCallbacks(discoveryRestartRunnable)
        Log.d(TAG, "[DISCOVERY_DEBUG] cancelDiscoveryTimers: restart callback removed")
    }

    private fun scheduleAdvertisingRestart(delayMs: Long = 10_000L) {
        // Host advertising is managed by the Dart layer; no automatic restart here.
    }

    private val connectionLifecycleCallback = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(endpointId: String, info: ConnectionInfo) {
            val endpointName = info.endpointName
            Log.d(TAG, "onConnectionInitiated: endpointId=$endpointId, name=$endpointName")
            val existing = endpoints[endpointId]
            if (existing != null && existing.connected) {
                Log.w(TAG, "Duplicate incoming connection for already connected endpoint $endpointId")
                try {
                    connectionsClient.rejectConnection(endpointId)
                } catch (e: Exception) {
                    Log.w(TAG, "Failed reject duplicate connection: ${e.message}")
                }
                return
            }

            endpoints[endpointId] = EndpointInfo(endpointName, System.currentTimeMillis(), false)
            pendingIncomingConnections[endpointId] = endpointName
            try {
                connectionsClient.acceptConnection(endpointId, payloadCallback)
                logDebug("Accepted incoming connection for $endpointId")
                sendEcdhHandshake(endpointId)
            } catch (e: Exception) {
                logError("acceptConnection", e)
            }
        }

        override fun onConnectionResult(endpointId: String, resolution: ConnectionResolution) {
            Log.d(TAG, "onConnectionResult: endpointId=$endpointId, statusCode=${resolution.status.statusCode}")
            when (resolution.status.statusCode) {
                ConnectionsStatusCodes.STATUS_OK -> {
                    Log.d(TAG, "Connection ACCEPTED to $endpointId")
                    markEndpointConnected(endpointId)
                    cancelConnectionRetry(endpointId)
                    if (pendingJoinRequests.containsKey(endpointId)) {
                        sendJoinRequestPayload(endpointId)
                        scheduleJoinTimeout(endpointId)
                    }
                    sendEcdhHandshake(endpointId)
                }
                ConnectionsStatusCodes.STATUS_ALREADY_CONNECTED_TO_ENDPOINT -> {
                    Log.d(TAG, "Already connected to endpoint $endpointId")
                    markEndpointConnected(endpointId)
                    if (pendingJoinRequests.containsKey(endpointId)) {
                        sendJoinRequestPayload(endpointId)
                        scheduleJoinTimeout(endpointId)
                    }
                }
                ConnectionsStatusCodes.STATUS_CONNECTION_REJECTED -> {
                    Log.d(TAG, "Connection REJECTED: $endpointId")
                    if (pendingJoinRequests.containsKey(endpointId)) {
                        pendingJoinRequests.remove(endpointId)
                        sendFlutterEvent("onJoinRequestFailed", mapOf("endpointId" to endpointId, "reason" to "rejected"))
                    }
                    cancelConnectionRetry(endpointId)
                }
                ConnectionsStatusCodes.STATUS_ERROR -> {
                    Log.e(TAG, "Connection ERROR: $endpointId")
                    if (pendingJoinRequests.containsKey(endpointId) && endpoints.containsKey(endpointId)) {
                        scheduleConnectionRetry(endpointId, pendingConnectionRetries[endpointId] ?: 1)
                    } else {
                        pendingJoinRequests.remove(endpointId)
                    }
                }
                else -> {
                    Log.w(TAG, "Connection unknown status: ${resolution.status.statusCode}")
                }
            }
        }

        override fun onDisconnected(endpointId: String) {
            Log.d(TAG, "onDisconnected: $endpointId")
            cleanupDisconnectedEndpoint(endpointId)
        }
    }

    private val payloadCallback = object : PayloadCallback() {
        override fun onPayloadReceived(endpointId: String, payload: Payload) {
            val bytes = payload.asBytes()
            if (bytes == null) return
            try {
                val asText = String(bytes, Charsets.UTF_8)
                val jo = JSONObject(asText)
                val messageType = jo.optString("type")
                when (messageType) {
                    "ECDH_INIT" -> handleEcdhInit(endpointId, jo)
                    "JOIN_REQUEST" -> {
                        val payloadObject = jo.optJSONObject("payload")
                        val map = HashMap<String, Any?>()
                        map["request"] = payloadObject?.toString()
                        map["fromEndpointId"] = endpointId
                        map["fromEndpointName"] = endpoints[endpointId]?.endpointName
                        invokeFlutterCallback("onJoinRequest", map)
                    }
                    "FILE_LIST_REQUEST" -> {
                        // Enforce ACL: only allow if endpoint has 'list' or 'read'
                        try {
                            val rights = acl[endpointId] ?: emptyList()
                            if (!rights.contains("list") && !rights.contains("read")) {
                                Log.w(TAG, "Endpoint $endpointId not allowed to list files: $rights")
                                val err = JSONObject()
                                err.put("type", "FILE_LIST_RESPONSE")
                                err.put("error", "permission_denied")
                                connectionsClient?.sendPayload(endpointId, Payload.fromBytes(err.toString().toByteArray(Charsets.UTF_8)))
                            } else {
                                val dir = filesDir
                                val filesArr = org.json.JSONArray()
                                dir?.listFiles()?.forEach { f ->
                                    val fo = JSONObject()
                                    fo.put("id", f.name)
                                    fo.put("name", f.name)
                                    fo.put("size", f.length())
                                    filesArr.put(fo)
                                }
                                val resp = JSONObject()
                                resp.put("type", "FILE_LIST_RESPONSE")
                                resp.put("files", filesArr)
                                connectionsClient?.sendPayload(endpointId, Payload.fromBytes(resp.toString().toByteArray(Charsets.UTF_8)))
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "FILE_LIST_RESPONSE failed: ${e.message}")
                        }
                    }
                    "FILE_CHUNK_REQUEST" -> {
                        // client wants a single chunk for file_id at seq
                        try {
                            val fileId = jo.optString("file_id")
                            val seq = jo.optInt("seq", 0)
                            val rights = acl[endpointId] ?: emptyList()
                            if (!rights.contains("read")) {
                                Log.w(TAG, "Endpoint $endpointId not allowed to read file: $fileId")
                                val err = JSONObject()
                                err.put("type", "FILE_CHUNK_RESPONSE")
                                err.put("error", "permission_denied")
                                connectionsClient?.sendPayload(endpointId, Payload.fromBytes(err.toString().toByteArray(Charsets.UTF_8)))
                            } else {
                                val dir = filesDir
                                val f = dir?.listFiles()?.firstOrNull { it.name == fileId }
                                if (f == null) {
                                    val err = JSONObject()
                                    err.put("type", "FILE_CHUNK_RESPONSE")
                                    err.put("error", "not_found")
                                    connectionsClient?.sendPayload(endpointId, Payload.fromBytes(err.toString().toByteArray(Charsets.UTF_8)))
                                } else {
                                    val CHUNK_SIZE = 64 * 1024
                                    val offset = seq * CHUNK_SIZE
                                    if (offset >= f.length()) {
                                        val err = JSONObject()
                                        err.put("type", "FILE_CHUNK_RESPONSE")
                                        err.put("error", "eof")
                                        connectionsClient?.sendPayload(endpointId, Payload.fromBytes(err.toString().toByteArray(Charsets.UTF_8)))
                                    } else {
                                        val raf = java.io.RandomAccessFile(f, "r")
                                        raf.seek(offset.toLong())
                                        val remaining = (f.length() - offset).toInt()
                                        val readSize = Math.min(CHUNK_SIZE, remaining)
                                        val buf = ByteArray(readSize)
                                        raf.readFully(buf)
                                        raf.close()
                                        // build frame header: idLen(1) + id bytes + seq(4)
                                        val idBytes = fileId.toByteArray(Charsets.UTF_8)
                                        val header = ByteArray(1 + idBytes.size + 4)
                                        header[0] = (idBytes.size and 0xff).toByte()
                                        System.arraycopy(idBytes, 0, header, 1, idBytes.size)
                                        val seqBuf = java.nio.ByteBuffer.allocate(4).putInt(seq).array()
                                        System.arraycopy(seqBuf, 0, header, 1 + idBytes.size, 4)
                                        val frame = ByteArray(header.size + buf.size)
                                        System.arraycopy(header, 0, frame, 0, header.size)
                                        System.arraycopy(buf, 0, frame, header.size, buf.size)
                                        val key = sessionKeys[endpointId]
                                        if (key != null) {
                                            val encrypted = encryptFrame(frame, key)
                                            connectionsClient?.sendPayload(endpointId, Payload.fromBytes(encrypted))
                                        } else {
                                            connectionsClient?.sendPayload(endpointId, Payload.fromBytes(frame))
                                        }
                                    }
                                }
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "FILE_CHUNK_REQUEST failed: ${e.message}")
                        }
                    }
                    "FILE_UPLOAD_REQUEST" -> {
                        // client wants to upload a file to host
                        try {
                            val fileId = jo.optString("file_id")
                            val fileName = jo.optString("name", fileId)
                            val size = jo.optLong("size", -1)
                            val rights = acl[endpointId] ?: emptyList()
                            if (!rights.contains("write")) {
                                Log.w(TAG, "Endpoint $endpointId not allowed to upload: $rights")
                                val err = JSONObject()
                                err.put("type", "FILE_UPLOAD_RESPONSE")
                                err.put("file_id", fileId)
                                err.put("error", "permission_denied")
                                connectionsClient?.sendPayload(endpointId, Payload.fromBytes(err.toString().toByteArray(Charsets.UTF_8)))
                            } else {
                                val dir = filesDir
                                val tmp = java.io.File(dir, "$fileId.upload")
                                val raf = java.io.RandomAccessFile(tmp, "rw")
                                // optional: pre-allocate
                                if (size > 0) {
                                    try { raf.setLength(size) } catch (_: Exception) { }
                                }
                                // compute resume sequence if tmp already has data
                                val CHUNK_SIZE = 64 * 1024
                                val resumeSeq = if (tmp.exists()) ((tmp.length() / CHUNK_SIZE).toInt()) else 0
                                ongoingUploads[endpointId + ":" + fileId] = raf
                                val resp = JSONObject()
                                resp.put("type", "FILE_UPLOAD_RESPONSE")
                                resp.put("file_id", fileId)
                                resp.put("status", "ok")
                                resp.put("resume_seq", resumeSeq)
                                connectionsClient?.sendPayload(endpointId, Payload.fromBytes(resp.toString().toByteArray(Charsets.UTF_8)))
                                Log.d(TAG, "Ready to receive upload $fileId from $endpointId")
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "FILE_UPLOAD_REQUEST failed: ${e.message}")
                        }
                    }
                    "FILE_DELETE" -> {
                        try {
                            val fileId = jo.optString("file_id")
                            val rights = acl[endpointId] ?: emptyList()
                            val resp = JSONObject()
                            resp.put("type", "FILE_DELETE_RESULT")
                            resp.put("file_id", fileId)
                            if (!rights.contains("write")) {
                                resp.put("status", "permission_denied")
                                connectionsClient?.sendPayload(endpointId, Payload.fromBytes(resp.toString().toByteArray(Charsets.UTF_8)))
                            } else {
                                val dir = filesDir
                                val f = dir?.listFiles()?.firstOrNull { it.name == fileId }
                                if (f == null) {
                                    resp.put("status", "not_found")
                                } else {
                                    val ok = f.delete()
                                    resp.put("status", if (ok) "ok" else "failed")
                                }
                                connectionsClient?.sendPayload(endpointId, Payload.fromBytes(resp.toString().toByteArray(Charsets.UTF_8)))
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "FILE_DELETE failed: ${e.message}")
                        }
                    }
                    "JOIN_RESPONSE" -> {
                        val responseObject = jo.optJSONObject("response")
                        val map = HashMap<String, Any?>()
                        map["response"] = responseObject?.toString()
                        map["fromEndpointId"] = endpointId
                        map["fromEndpointName"] = endpoints[endpointId]?.endpointName
                        invokeFlutterCallback("onJoinResponse", map)
                        pendingJoinRequests.remove(endpointId)
                        cancelJoinTimeout(endpointId)
                    }
                    "FILE_LIST_RESPONSE" -> {
                        val files = jo.optJSONArray("files")
                        val map = HashMap<String, Any?>()
                        map["fromEndpointId"] = endpointId
                        map["files"] = files?.toString()
                        invokeFlutterCallback("onFileList", map)
                    }
                    else -> {
                        val controlMap = HashMap<String, Any?>()
                        controlMap["control"] = jo.toString()
                        controlMap["endpointId"] = endpointId
                        controlMap["endpointName"] = endpoints[endpointId]?.endpointName
                        invokeFlutterCallback("onControl", controlMap)
                    }
                }
                return
            } catch (e: Exception) {
                // Not JSON or encrypted payload; fall through to binary parsing
            }

            val key = sessionKeys[endpointId]
            if (key != null) {
                decryptFramedPayload(endpointId, bytes, key)
            } else {
                val map = HashMap<String, Any?>()
                map["endpointId"] = endpointId
                map["bytes"] = bytes
                invokeFlutterCallback("onPayloadBytes", map)
            }
        }

        override fun onPayloadTransferUpdate(endpointId: String, update: PayloadTransferUpdate) {
            val map = HashMap<String, Any?>()
            map["endpointId"] = endpointId
            map["status"] = update.status
            map["bytesTransferred"] = update.bytesTransferred
            map["totalBytes"] = update.totalBytes
            invokeFlutterCallback("onPayloadTransferUpdate", map)
        }
    }

    private fun handleEcdhInit(endpointId: String, jo: JSONObject) {
        try {
            val peerB64 = jo.optString("pub")
            val peerBytes = Base64.decode(peerB64, Base64.DEFAULT)
            val myPair = keyPairs[endpointId]
            if (myPair != null) {
                val kf = KeyFactory.getInstance("X25519")
                val peerPub = kf.generatePublic(X509EncodedKeySpec(peerBytes))
                val ka = KeyAgreement.getInstance("X25519")
                ka.init(myPair.private)
                ka.doPhase(peerPub, true)
                val secret = ka.generateSecret()
                val derived = MessageDigest.getInstance("SHA-256").digest(secret)
                sessionKeys[endpointId] = derived
                Log.d(TAG, "Derived session key for $endpointId")
            }
        } catch (e: Exception) {
            Log.e(TAG, "ECDH handle failed: ${e.message}")
        }
    }

    private fun decryptFramedPayload(endpointId: String, bytes: ByteArray, key: ByteArray) {
        if (bytes.size < 6) return
        val idLen = bytes[0].toInt() and 0xff
        val headerLen = 1 + idLen + 4
        if (bytes.size <= headerLen) return
        val payloadBytes = bytes.copyOfRange(headerLen, bytes.size)
        if (payloadBytes.size < 12) return
        try {
            val nonce = payloadBytes.copyOfRange(0, 12)
            val ciphertext = payloadBytes.copyOfRange(12, payloadBytes.size)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            val spec = GCMParameterSpec(128, nonce)
            val sk = SecretKeySpec(key, "AES")
            cipher.init(Cipher.DECRYPT_MODE, sk, spec)
            val plain = cipher.doFinal(ciphertext)
            val headerBytes = bytes.copyOfRange(0, headerLen)
            val fullBytes = ByteArray(headerBytes.size + plain.size)
            System.arraycopy(headerBytes, 0, fullBytes, 0, headerBytes.size)
            System.arraycopy(plain, 0, fullBytes, headerBytes.size, plain.size)
            // If there's an ongoing upload for this transfer id, write the chunk to disk
            var handledAsUpload = false
            try {
                if (headerBytes.size >= 5) {
                    val idLen2 = headerBytes[0].toInt() and 0xff
                    if (headerBytes.size >= 1 + idLen2 + 4) {
                        val idStart2 = 1
                        val idEnd2 = 1 + idLen2
                        val idBytes2 = headerBytes.copyOfRange(idStart2, idEnd2)
                        val transferId = String(idBytes2, Charsets.UTF_8)
                        val seqBytes2 = headerBytes.copyOfRange(idEnd2, idEnd2 + 4)
                        val seq = java.nio.ByteBuffer.wrap(seqBytes2).int
                        val keyName = endpointId + ":" + transferId
                        var raf = ongoingUploads[keyName]
                        if (raf == null) {
                            // try to open a tmp upload file if present (resume after restart)
                            try {
                                val dir = filesDir
                                val tmpF = java.io.File(dir, "$transferId.upload")
                                if (tmpF.exists()) {
                                    val opened = java.io.RandomAccessFile(tmpF, "rw")
                                    ongoingUploads[keyName] = opened
                                    raf = opened
                                    Log.d(TAG, "Reopened tmp upload for $keyName (size=${tmpF.length()})")
                                }
                            } catch (e: Exception) {
                                Log.w(TAG, "Failed to reopen tmp for $transferId: ${e.message}")
                            }
                        }
                        if (raf != null) {
                            try {
                                val CHUNK_SIZE = 64 * 1024
                                raf.seek(seq.toLong() * CHUNK_SIZE)
                                raf.write(plain)
                                // if this chunk is smaller than chunk size, finalize
                                if (plain.size < CHUNK_SIZE) {
                                    try { raf.close() } catch (_: Exception) { }
                                    ongoingUploads.remove(keyName)
                                    val dir = filesDir
                                    val tmp = java.io.File(dir, "$transferId.upload")
                                    val finalFile = java.io.File(dir, transferId)
                                    var savedStatus = "failed"
                                    var savedSize: Long = 0
                                    try {
                                        if (finalFile.exists()) {
                                            try { finalFile.delete() } catch (_: Exception) { }
                                        }
                                        val ok = try { tmp.renameTo(finalFile) } catch (e: Exception) { false }
                                        if (ok && finalFile.exists()) {
                                            savedStatus = "ok"
                                            savedSize = finalFile.length()
                                        } else {
                                            // fallback: attempt copy
                                            try {
                                                tmp.copyTo(finalFile, overwrite = true)
                                                if (finalFile.exists()) {
                                                    savedStatus = "ok"
                                                    savedSize = finalFile.length()
                                                }
                                            } catch (_: Exception) { }
                                        }
                                    } catch (e: Exception) {
                                        Log.e(TAG, "Finalize upload failed: ${e.message}")
                                    }
                                    val result = JSONObject()
                                    result.put("type", "FILE_UPLOAD_RESULT")
                                    result.put("transfer_id", transferId)
                                    result.put("status", savedStatus)
                                    try { result.put("saved_path", finalFile.absolutePath) } catch (_: Exception) { }
                                    try { result.put("saved_size", savedSize) } catch (_: Exception) { }
                                    connectionsClient?.sendPayload(endpointId, Payload.fromBytes(result.toString().toByteArray(Charsets.UTF_8)))
                                    Log.d(TAG, "Upload $transferId complete from $endpointId -> $savedStatus ($savedSize bytes)")
                                } else {
                                    // partial chunk received, send ack
                                    val ackJo = JSONObject()
                                    ackJo.put("type", "CHUNK_ACK")
                                    ackJo.put("transfer_id", transferId)
                                    ackJo.put("seq", seq)
                                    connectionsClient?.sendPayload(endpointId, Payload.fromBytes(ackJo.toString().toByteArray(Charsets.UTF_8)))
                                }
                                handledAsUpload = true
                            } catch (e: Exception) {
                                Log.e(TAG, "Failed writing upload chunk: ${e.message}")
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Upload handling check failed: ${e.message}")
            }

            if (!handledAsUpload) {
                val map = HashMap<String, Any?>()
                map["endpointId"] = endpointId
                map["bytes"] = fullBytes
                invokeFlutterCallback("onPayloadBytes", map)
                sendChunkAckIfNeeded(endpointId, headerBytes)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Decrypt failed: ${e.message}")
        }
    }

    private fun encryptFrame(frame: ByteArray, key: ByteArray): ByteArray {
        if (frame.size < 6) return frame
        val idLen = frame[0].toInt() and 0xff
        val headerLen = 1 + idLen + 4
        if (frame.size <= headerLen) return frame
        val header = frame.copyOfRange(0, headerLen)
        val payload = frame.copyOfRange(headerLen, frame.size)

        val nonce = ByteArray(12)
        random.nextBytes(nonce)

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val spec = GCMParameterSpec(128, nonce)
        val sk = SecretKeySpec(key, "AES")
        cipher.init(Cipher.ENCRYPT_MODE, sk, spec)
        val cipherText = cipher.doFinal(payload)

        val out = ByteArray(header.size + nonce.size + cipherText.size)
        System.arraycopy(header, 0, out, 0, header.size)
        System.arraycopy(nonce, 0, out, header.size, nonce.size)
        System.arraycopy(cipherText, 0, out, header.size + nonce.size, cipherText.size)
        return out
    }

    private fun sendChunkAckIfNeeded(endpointId: String, headerBytes: ByteArray) {
        try {
            if (headerBytes.size >= 5) {
                val idLen = headerBytes[0].toInt() and 0xff
                if (headerBytes.size >= 1 + idLen + 4) {
                    val idStart = 1
                    val idEnd = 1 + idLen
                    val idBytes = headerBytes.copyOfRange(idStart, idEnd)
                    val transferId = String(idBytes, Charsets.UTF_8)
                    val seqBytes = headerBytes.copyOfRange(idEnd, idEnd + 4)
                    val seq = java.nio.ByteBuffer.wrap(seqBytes).int
                    val ackJo = JSONObject()
                    ackJo.put("type", "CHUNK_ACK")
                    ackJo.put("transfer_id", transferId)
                    ackJo.put("seq", seq)
                    connectionsClient?.sendPayload(endpointId, Payload.fromBytes(ackJo.toString().toByteArray(Charsets.UTF_8)))
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "ACK send failed: ${e.message}")
        }
    }

    private val endpointDiscoveryCallback = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(endpointId: String, info: com.google.android.gms.nearby.connection.DiscoveredEndpointInfo) {
            Log.d(TAG, "[ENDPOINT_DEBUG] onEndpointFound: endpointId=$endpointId, name=${info.endpointName}")
            val existing = endpoints[endpointId]
            // Always update the cache and always notify Flutter so that:
            // (a) stale connected=true entries from prior sessions do not silently swallow re-discovery,
            // (b) the 30-second eviction timer in the Dart layer is reset on every scan cycle.
            endpoints[endpointId] = EndpointInfo(
                info.endpointName,
                System.currentTimeMillis(),
                existing?.connected ?: connectedEndpoints.contains(endpointId)
            )
            val map = HashMap<String, Any?>()
            map["endpointId"] = endpointId
            map["endpointName"] = info.endpointName
            Log.d(TAG, "[ENDPOINT_DEBUG] invoking Flutter onEndpointFound for $endpointId (wasKnown=${existing != null})")
            invokeFlutterCallback("onEndpointFound", map)
        }

        override fun onEndpointLost(endpointId: String) {
            Log.d(TAG, "onEndpointLost: $endpointId")
            val info = endpoints[endpointId]
            if (info?.connected == true) {
                Log.d(TAG, "Endpoint $endpointId lost from discovery but still connected; preserving connection state")
                info.lastSeenMs = System.currentTimeMillis()
                return
            }
            val endpointName = endpoints.remove(endpointId)?.endpointName
            pendingJoinRequests.remove(endpointId)
            cancelConnectionRetry(endpointId)
            cancelJoinTimeout(endpointId)
            val map = HashMap<String, Any?>()
            map["endpointId"] = endpointId
            map["endpointName"] = endpointName
            invokeFlutterCallback("onEndpointLost", map)
        }
    }
}
