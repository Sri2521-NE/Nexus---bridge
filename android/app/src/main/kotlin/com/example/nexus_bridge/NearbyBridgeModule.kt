package com.example.nexus_bridge

import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class NearbyBridgeModule(private val context: Context, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel: MethodChannel = MethodChannel(messenger, "com.nexusbridge/nearby")

    companion object {
        var channelStatic: MethodChannel? = null
    }

    init {
        channel.setMethodCallHandler(this)
        channelStatic = channel
    }

    fun cleanup() {
        channel.setMethodCallHandler(null)
        channelStatic = null
    }

    private fun startNearbyService(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ContextCompat.startForegroundService(context, intent)
        } else {
            context.startService(intent)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startAdvertising" -> {
                val communityId = call.argument<String>("communityId")
                val name = call.argument<String>("name")
                val intent = Intent(context, NearbyBridgeService::class.java).apply {
                    putExtra("action", "startAdvertising")
                    putExtra("communityId", communityId)
                    putExtra("name", name)
                }
                startNearbyService(intent)
                result.success(null)
            }
            "stopAdvertising" -> {
                val intent = Intent(context, NearbyBridgeService::class.java).apply {
                    putExtra("action", "stopAdvertising")
                }
                startNearbyService(intent)
                result.success(null)
            }
            "startDiscovery" -> {
                val intent = Intent(context, NearbyBridgeService::class.java).apply {
                    putExtra("action", "startDiscovery")
                }
                startNearbyService(intent)
                result.success(null)
            }
            "stopDiscovery" -> {
                val intent = Intent(context, NearbyBridgeService::class.java).apply {
                    putExtra("action", "stopDiscovery")
                }
                startNearbyService(intent)
                result.success(null)
            }
            "requestJoin" -> {
                val hostDevice = call.argument<String>("hostDevice")
                val payload = call.argument<Map<String, Any>>("payload")
                val intent = Intent(context, NearbyBridgeService::class.java).apply {
                    putExtra("action", "sendJoinRequest")
                    putExtra("hostDevice", hostDevice)
                    if (payload != null) putExtra("payload", HashMap(payload))
                }
                startNearbyService(intent)
                result.success(null)
            }
            "respondJoin" -> {
                val targetDevice = call.argument<String>("targetDevice")
                val response = call.argument<Map<String, Any>>("response")
                val intent = Intent(context, NearbyBridgeService::class.java).apply {
                    putExtra("action", "respondJoin")
                    putExtra("targetDevice", targetDevice)
                    if (response != null) putExtra("response", HashMap(response))
                }
                startNearbyService(intent)
                result.success(null)
            }
            "sendControl" -> {
                val control = call.argument<Map<String, Any>>("control")
                val target = call.argument<String>("target")
                val intent = Intent(context, NearbyBridgeService::class.java).apply {
                    putExtra("action", "sendControl")
                    putExtra("target", target)
                    if (control != null) putExtra("control", HashMap(control))
                }
                startNearbyService(intent)
                result.success(null)
            }
            "sendPayload" -> {
                val bytesArg = call.argument<Any>("bytes")
                val bytes = when (bytesArg) {
                    is ByteArray -> bytesArg
                    is ArrayList<*> -> {
                        val list = bytesArg.filterIsInstance<Int>()
                        ByteArray(list.size) { index -> list[index].toByte() }
                    }
                    else -> null
                }
                val target = call.argument<String>("target")
                val intent = Intent(context, NearbyBridgeService::class.java).apply {
                    putExtra("action", "sendPayload")
                    putExtra("target", target)
                    if (bytes != null) putExtra("bytes", bytes)
                }
                startNearbyService(intent)
                result.success(null)
            }
            "openBluetoothSettings" -> {
                val intent = Intent(Settings.ACTION_BLUETOOTH_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}
