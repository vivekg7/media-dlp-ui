package com.crylo.media_dl

import android.content.Intent
import android.os.Handler
import android.os.Looper
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import com.yausername.ffmpeg.FFmpeg
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class MainActivity : FlutterActivity() {
    private val shareChannelName = "com.crylo.media_dl/share"
    private val ytdlpChannelName = "com.crylo.media_dl/ytdlp"

    private val mainHandler = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val activeSinks = mutableMapOf<String, EventChannel.EventSink?>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Share intent channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "getSharedUrl") {
                    result.success(handleIntent(intent))
                } else {
                    result.notImplemented()
                }
            }

        // yt-dlp channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ytdlpChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "init" -> handleInit(result)
                    "execute" -> {
                        val processId = call.argument<String>("processId")!!
                        val arguments = call.argument<List<String>>("arguments")!!
                        handleExecute(flutterEngine, processId, arguments, result)
                    }
                    "executeSync" -> {
                        val arguments = call.argument<List<String>>("arguments")!!
                        handleExecuteSync(arguments, result)
                    }
                    "destroy" -> {
                        val processId = call.argument<String>("processId")!!
                        YoutubeDL.getInstance().destroyProcessById(processId)
                        result.success(null)
                    }
                    "version" -> handleVersion(result)
                    "updateYtDlp" -> handleUpdate(result)
                    "ffmpegVersion" -> handleFfmpegVersion(result)
                    "libraryVersion" -> result.success("0.18.1")
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val url = handleIntent(intent) ?: return
        flutterEngine?.dartExecutor?.binaryMessenger?.let {
            MethodChannel(it, shareChannelName).invokeMethod("sharedUrl", url)
        }
    }

    private fun handleIntent(intent: Intent): String? {
        if (intent.action == Intent.ACTION_SEND && intent.type == "text/plain") {
            return intent.getStringExtra(Intent.EXTRA_TEXT)
        }
        return null
    }

    // -----------------------------------------------------------------------
    // yt-dlp handlers
    // -----------------------------------------------------------------------

    private fun handleInit(result: MethodChannel.Result) {
        scope.launch(Dispatchers.IO) {
            try {
                YoutubeDL.getInstance().init(applicationContext)
                FFmpeg.getInstance().init(applicationContext)
                withContext(Dispatchers.Main) { result.success(true) }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("INIT_FAILED", e.message, null)
                }
            }
        }
    }

    private fun handleExecute(
        flutterEngine: FlutterEngine,
        processId: String,
        arguments: List<String>,
        result: MethodChannel.Result
    ) {
        // Register EventChannel for this process before returning
        val eventChannelName = "com.crylo.media_dl/ytdlp_output/$processId"
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    activeSinks[processId] = events
                }
                override fun onCancel(arguments: Any?) {
                    activeSinks.remove(processId)
                }
            })

        // Return immediately — Dart will listen to the EventChannel
        result.success(null)

        // Run blocking execute on IO thread
        scope.launch(Dispatchers.IO) {
            try {
                val request = YoutubeDLRequest(arguments)
                YoutubeDL.getInstance().execute(
                    request, processId
                ) { _, _, line ->
                    mainHandler.post {
                        activeSinks[processId]?.success(
                            mapOf("type" to "stdout", "data" to line)
                        )
                    }
                }

                // Send exit event
                mainHandler.post {
                    activeSinks[processId]?.success(
                        mapOf("type" to "exit", "code" to 0)
                    )
                    activeSinks[processId]?.endOfStream()
                    activeSinks.remove(processId)
                }
            } catch (e: Exception) {
                mainHandler.post {
                    val isCancelled = e is YoutubeDL.CanceledException
                    if (!isCancelled) {
                        activeSinks[processId]?.success(
                            mapOf("type" to "stderr", "data" to (e.message ?: "Unknown error"))
                        )
                    }
                    activeSinks[processId]?.success(
                        mapOf("type" to "exit", "code" to if (isCancelled) -1 else 1)
                    )
                    activeSinks[processId]?.endOfStream()
                    activeSinks.remove(processId)
                }
            }
        }
    }

    private fun handleExecuteSync(
        arguments: List<String>,
        result: MethodChannel.Result
    ) {
        scope.launch(Dispatchers.IO) {
            try {
                val request = YoutubeDLRequest(arguments)
                val response = YoutubeDL.getInstance().execute(request)
                withContext(Dispatchers.Main) {
                    result.success(mapOf(
                        "stdout" to response.out,
                        "stderr" to response.err,
                        "exitCode" to response.exitCode
                    ))
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("EXEC_FAILED", e.message, null)
                }
            }
        }
    }

    private fun handleVersion(result: MethodChannel.Result) {
        scope.launch(Dispatchers.IO) {
            try {
                val version = YoutubeDL.getInstance().version(applicationContext)
                withContext(Dispatchers.Main) { result.success(version) }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("VERSION_FAILED", e.message, null)
                }
            }
        }
    }

    private fun handleFfmpegVersion(result: MethodChannel.Result) {
        scope.launch(Dispatchers.IO) {
            try {
                val version = FFmpeg.getInstance().version(applicationContext)
                withContext(Dispatchers.Main) { result.success(version) }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) { result.success(null) }
            }
        }
    }

    private fun handleUpdate(result: MethodChannel.Result) {
        scope.launch(Dispatchers.IO) {
            try {
                val status = YoutubeDL.getInstance().updateYoutubeDL(
                    applicationContext,
                    YoutubeDL.UpdateChannel.STABLE
                )
                withContext(Dispatchers.Main) { result.success(status?.name) }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("UPDATE_FAILED", e.message, null)
                }
            }
        }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
