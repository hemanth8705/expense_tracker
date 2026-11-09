package com.fersonal.expense_tracker

import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts a tiny SMS channel. SMS are only read when Dart explicitly asks
 * (a manual refresh). The app never listens for incoming messages.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "expense_tracker/sms"
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "readInbox" -> {
                        val since = (call.argument<Number>("since") ?: 0).toLong()
                        // Large inboxes can be slow to query: keep it off the UI thread.
                        Thread {
                            try {
                                val rows = readInbox(since)
                                main.post { result.success(rows) }
                            } catch (e: SecurityException) {
                                main.post { result.error("PERMISSION", "READ_SMS not granted", null) }
                            } catch (e: Exception) {
                                main.post { result.error("READ_FAILED", e.message, null) }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun readInbox(since: Long): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        val cursor = contentResolver.query(
            Uri.parse("content://sms/inbox"),
            arrayOf("_id", "address", "body", "date"),
            "date >= ?",
            arrayOf(since.toString()),
            "date ASC"
        ) ?: return out
        cursor.use {
            val iId = it.getColumnIndexOrThrow("_id")
            val iAddr = it.getColumnIndexOrThrow("address")
            val iBody = it.getColumnIndexOrThrow("body")
            val iDate = it.getColumnIndexOrThrow("date")
            while (it.moveToNext()) {
                out.add(
                    mapOf(
                        "id" to it.getLong(iId),
                        "address" to (it.getString(iAddr) ?: ""),
                        "body" to (it.getString(iBody) ?: ""),
                        "date" to it.getLong(iDate)
                    )
                )
            }
        }
        return out
    }
}
