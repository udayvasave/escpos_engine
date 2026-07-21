package com.escpos.escpos_engine

import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.math.min

/** Android ESC/POS transport: classic Bluetooth RFCOMM + BLE GATT. */
class EscposEnginePlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware {
    private lateinit var channel: MethodChannel
    private var applicationContext: Context? = null
    private var activity: Activity? = null

    private val bleScanResults = ConcurrentHashMap<String, MutableMap<String, Any?>>()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "escpos_engine")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        applicationContext = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> {
                result.success("Android ${Build.VERSION.RELEASE}")
            }
            "listPrinters", "listSerialPorts" -> {
                result.success(emptyList<String>())
            }
            "listBluetoothDevices" -> {
                runCatching {
                    ensureBluetoothPermissions()
                    result.success(listBondedDevices())
                }.onFailure { result.error("bluetooth_error", it.message, null) }
            }
            "writeBluetooth", "writeSerial" -> {
                runCatching {
                    ensureBluetoothPermissions()
                    val address = call.argument<String>("address")
                        ?: call.argument<String>("portName")
                    val data = call.argument<ByteArray>("data")
                    if (address.isNullOrBlank() || data == null || data.isEmpty()) {
                        result.error("invalid_args", "address/portName and data required", null)
                        return
                    }
                    if (looksLikeComPort(address)) {
                        result.error(
                            "unsupported",
                            "COM ports are not available on Android. Use listBluetoothDevices().",
                            null,
                        )
                        return
                    }
                    writeClassicBluetooth(address, data)
                    result.success(true)
                }.onFailure { result.error("print_failed", it.message, null) }
            }
            "scanBleDevices" -> {
                runCatching {
                    ensureBluetoothPermissions(requireScan = true)
                    val timeoutMs = call.argument<Int>("timeoutMs") ?: 5000
                    result.success(scanBleDevices(timeoutMs))
                }.onFailure { result.error("bluetooth_error", it.message, null) }
            }
            "writeBle" -> {
                runCatching {
                    ensureBluetoothPermissions()
                    val address = call.argument<String>("address")
                    val data = call.argument<ByteArray>("data")
                    val serviceUuid = call.argument<String>("serviceUuid")
                    val characteristicUuid = call.argument<String>("characteristicUuid")
                    if (address.isNullOrBlank() || data == null || data.isEmpty()) {
                        result.error("invalid_args", "address and data required", null)
                        return
                    }
                    writeBle(address, data, serviceUuid, characteristicUuid)
                    result.success(true)
                }.onFailure { result.error("print_failed", it.message, null) }
            }
            "isBleReady" -> {
                runCatching {
                    ensureBluetoothPermissions()
                    val address = call.argument<String>("address")
                    if (address.isNullOrBlank()) {
                        result.success(false)
                        return
                    }
                    result.success(isBleReachable(address))
                }.onFailure { result.success(false) }
            }
            "printRaw", "isPrinterReady" -> {
                result.error("unsupported", "USB spooler not supported on Android", null)
            }
            else -> result.notImplemented()
        }
    }

    private fun bluetoothAdapter(): BluetoothAdapter {
        val context = applicationContext
            ?: throw IllegalStateException("Plugin not attached")
        val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        return manager.adapter ?: throw IllegalStateException("Bluetooth not available")
    }

    private fun ensureBluetoothPermissions(requireScan: Boolean = false) {
        val context = applicationContext
            ?: throw IllegalStateException("Plugin not attached")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val needed = mutableListOf<String>()
            if (ContextCompat.checkSelfPermission(
                    context,
                    android.Manifest.permission.BLUETOOTH_CONNECT,
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                needed.add(android.Manifest.permission.BLUETOOTH_CONNECT)
            }
            if (requireScan &&
                ContextCompat.checkSelfPermission(
                    context,
                    android.Manifest.permission.BLUETOOTH_SCAN,
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                needed.add(android.Manifest.permission.BLUETOOTH_SCAN)
            }
            if (needed.isNotEmpty()) {
                val act = activity
                if (act != null) {
                    ActivityCompat.requestPermissions(act, needed.toTypedArray(), 9001)
                }
                throw IllegalStateException(
                    "Bluetooth permission required: ${needed.joinToString()}. Grant in app settings.",
                )
            }
        } else {
            if (ContextCompat.checkSelfPermission(
                    context,
                    android.Manifest.permission.ACCESS_FINE_LOCATION,
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                val act = activity
                if (act != null) {
                    ActivityCompat.requestPermissions(
                        act,
                        arrayOf(android.Manifest.permission.ACCESS_FINE_LOCATION),
                        9002,
                    )
                }
                throw IllegalStateException(
                    "Location permission required for Bluetooth scan on this Android version.",
                )
            }
        }
    }

    private fun listBondedDevices(): List<Map<String, Any?>> {
        val adapter = bluetoothAdapter()
        if (!adapter.isEnabled) {
            throw IllegalStateException("Bluetooth is turned off")
        }
        return adapter.bondedDevices.map { device ->
            mapOf(
                "address" to device.address,
                "name" to (device.name ?: device.address),
            )
        }
    }

    private fun writeClassicBluetooth(address: String, data: ByteArray) {
        val adapter = bluetoothAdapter()
        if (!adapter.isEnabled) {
            throw IllegalStateException("Bluetooth is turned off")
        }
        val device = adapter.getRemoteDevice(address)
        val socket = device.createRfcommSocketToServiceRecord(SPP_UUID)
        adapter.cancelDiscovery()
        socket.use {
            it.connect()
            val stream = it.outputStream
            var offset = 0
            while (offset < data.size) {
                val chunk = min(CHUNK_SIZE, data.size - offset)
                stream.write(data, offset, chunk)
                offset += chunk
            }
            stream.flush()
        }
    }

    private fun scanBleDevices(timeoutMs: Int): List<Map<String, Any?>> {
        val adapter = bluetoothAdapter()
        if (!adapter.isEnabled) {
            throw IllegalStateException("Bluetooth is turned off")
        }
        val scanner = adapter.bluetoothLeScanner
            ?: throw IllegalStateException("BLE scanner not available")

        bleScanResults.clear()
        val latch = CountDownLatch(1)
        val callback =
            object : ScanCallback() {
                override fun onScanResult(callbackType: Int, result: ScanResult) {
                    val device = result.device ?: return
                    val name = device.name ?: device.address
                    bleScanResults[device.address] =
                        mutableMapOf(
                            "address" to device.address,
                            "name" to name,
                            "rssi" to result.rssi,
                        )
                }

                override fun onScanFailed(errorCode: Int) {
                    latch.countDown()
                }
            }

        scanner.startScan(callback)
        Handler(Looper.getMainLooper()).postDelayed({
            scanner.stopScan(callback)
            latch.countDown()
        }, timeoutMs.toLong().coerceIn(1000, 30000))
        latch.await(timeoutMs.toLong() + 2000, TimeUnit.MILLISECONDS)

        return bleScanResults.values.map { HashMap(it) }
    }

    private fun isBleReachable(address: String): Boolean {
        val context = applicationContext ?: return false
        val adapter = bluetoothAdapter()
        if (!adapter.isEnabled) return false

        var gatt: BluetoothGatt? = null
        val latch = CountDownLatch(1)
        var success = false

        val callback =
            object : BluetoothGattCallback() {
                override fun onConnectionStateChange(
                    g: BluetoothGatt,
                    status: Int,
                    newState: Int,
                ) {
                    if (newState == BluetoothProfile.STATE_CONNECTED) {
                        success = true
                        g.discoverServices()
                    } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                        latch.countDown()
                    }
                }

                override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
                    latch.countDown()
                }
            }

        return try {
            val device = adapter.getRemoteDevice(address)
            gatt = device.connectGatt(context, false, callback)
            latch.await(8, TimeUnit.SECONDS)
            success
        } finally {
            gatt?.close()
        }
    }

    private fun writeBle(
        address: String,
        data: ByteArray,
        serviceUuidText: String?,
        characteristicUuidText: String?,
    ) {
        val context = applicationContext
            ?: throw IllegalStateException("Plugin not attached")
        val adapter = bluetoothAdapter()
        if (!adapter.isEnabled) {
            throw IllegalStateException("Bluetooth is turned off")
        }

        var gatt: BluetoothGatt? = null
        val connectLatch = CountDownLatch(1)
        var writeLatch = CountDownLatch(1)
        var writeCharacteristic: BluetoothGattCharacteristic? = null
        var writeError: String? = null

        val callback =
            object : BluetoothGattCallback() {
                override fun onConnectionStateChange(
                    g: BluetoothGatt,
                    status: Int,
                    newState: Int,
                ) {
                    if (newState == BluetoothProfile.STATE_CONNECTED) {
                        g.discoverServices()
                    } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                        connectLatch.countDown()
                        writeLatch.countDown()
                    }
                }

                override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
                    if (status != BluetoothGatt.GATT_SUCCESS) {
                        writeError = "GATT service discovery failed ($status)"
                        connectLatch.countDown()
                        writeLatch.countDown()
                        return
                    }
                    writeCharacteristic =
                        findWriteCharacteristic(
                            g.services,
                            serviceUuidText,
                            characteristicUuidText,
                        )
                    if (writeCharacteristic == null) {
                        writeError = "No writable BLE characteristic found"
                    }
                    connectLatch.countDown()
                }

                override fun onCharacteristicWrite(
                    g: BluetoothGatt,
                    characteristic: BluetoothGattCharacteristic,
                    status: Int,
                ) {
                    if (status != BluetoothGatt.GATT_SUCCESS) {
                        writeError = "GATT write failed ($status)"
                    }
                    writeLatch.countDown()
                }
            }

        val device = adapter.getRemoteDevice(address)
        gatt = device.connectGatt(context, false, callback)
        if (!connectLatch.await(15, TimeUnit.SECONDS)) {
            gatt.close()
            throw IllegalStateException("BLE connect timed out")
        }
        val characteristic = writeCharacteristic
        if (characteristic == null) {
            gatt.close()
            throw IllegalStateException(writeError ?: "No writable BLE characteristic")
        }

        gatt.requestMtu(512)
        Thread.sleep(200)

        val useNoResponse =
            characteristic.properties and
                BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0
        characteristic.writeType =
            if (useNoResponse) {
                BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            } else {
                BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            }

        var offset = 0
        while (offset < data.size) {
            val chunk = min(BLE_CHUNK_SIZE, data.size - offset)
            characteristic.value = data.copyOfRange(offset, offset + chunk)
            if (useNoResponse) {
                writeLatch = CountDownLatch(0) // unused
            } else {
                writeLatch = CountDownLatch(1)
            }
            if (!gatt.writeCharacteristic(characteristic)) {
                gatt.close()
                throw IllegalStateException("Failed to queue BLE write")
            }
            if (!useNoResponse) {
                writeLatch.await(5, TimeUnit.SECONDS)
                if (writeError != null) {
                    gatt.close()
                    throw IllegalStateException(writeError)
                }
            } else {
                Thread.sleep(25)
            }
            offset += chunk
        }

        Thread.sleep(100)
        gatt.close()
    }

    private fun findWriteCharacteristic(
        services: List<BluetoothGattService>,
        serviceUuidText: String?,
        characteristicUuidText: String?,
    ): BluetoothGattCharacteristic? {
        val serviceFilter = serviceUuidText?.let { UUID.fromString(it) }
        val charFilter = characteristicUuidText?.let { UUID.fromString(it) }

        fun tryPair(serviceUuid: UUID, charUuid: UUID): BluetoothGattCharacteristic? {
            val service = services.find { it.uuid == serviceUuid } ?: return null
            val characteristic = service.getCharacteristic(charUuid) ?: return null
            return if (isWritable(characteristic)) characteristic else null
        }

        if (serviceFilter != null && charFilter != null) {
            tryPair(serviceFilter, charFilter)?.let { return it }
        }
        tryPair(NUS_SERVICE_UUID, NUS_TX_UUID)?.let { return it }
        tryPair(ALT_SERVICE_UUID, ALT_WRITE_UUID)?.let { return it }

        for (service in services) {
            for (characteristic in service.characteristics) {
                if (isWritable(characteristic)) {
                    return characteristic
                }
            }
        }
        return null
    }

    private fun isWritable(characteristic: BluetoothGattCharacteristic): Boolean {
        val props = characteristic.properties
        return props and BluetoothGattCharacteristic.PROPERTY_WRITE != 0 ||
            props and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0
    }

    private fun looksLikeComPort(value: String): Boolean {
        return value.uppercase().startsWith("COM")
    }

    companion object {
        private val SPP_UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
        private val NUS_SERVICE_UUID =
            UUID.fromString("6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
        private val NUS_TX_UUID = UUID.fromString("6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
        private val ALT_SERVICE_UUID = UUID.fromString("0000FFF0-0000-1000-8000-00805F9B34FB")
        private val ALT_WRITE_UUID = UUID.fromString("0000FFF1-0000-1000-8000-00805F9B34FB")
        private const val CHUNK_SIZE = 4096
        private const val BLE_CHUNK_SIZE = 180
    }
}
