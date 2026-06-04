package com.daniewatch.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Handles APK installation via Android's PackageInstaller.
 *
 * Uses FileProvider to create a content:// URI for the APK file,
 * then fires Intent.ACTION_VIEW to trigger the system installer.
 * Also handles the "Install from unknown sources" permission check.
 */
class InstallApkHandler(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "InstallApkHandler"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "installApk" -> {
                val apkPath = call.argument<String>("apkPath")
                if (apkPath == null) {
                    result.error("INVALID_ARGS", "apkPath is required", null)
                    return
                }
                installApk(apkPath, result)
            }
            else -> result.notImplemented()
        }
    }

    private fun installApk(apkPath: String, result: MethodChannel.Result) {
        try {
            Log.d(TAG, "installApk called with path: $apkPath")

            val file = File(apkPath)
            if (!file.exists()) {
                Log.e(TAG, "APK file not found at: $apkPath")
                result.error("FILE_NOT_FOUND", "APK file not found at: $apkPath", null)
                return
            }

            Log.d(TAG, "APK file exists, size: ${file.length()} bytes")

            // Check "Install from unknown sources" permission (Android 8.0+)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val canInstall = activity.packageManager.canRequestPackageInstalls()
                Log.d(TAG, "canRequestPackageInstalls: $canInstall")

                if (!canInstall) {
                    Log.d(TAG, "Opening unknown app sources settings")
                    val settingsIntent = Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:${activity.packageName}")
                    ).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    activity.startActivity(settingsIntent)
                    result.success("needs_permission")
                    return
                }
            }

            // Create content:// URI via FileProvider
            Log.d(TAG, "Creating FileProvider URI for: ${file.absolutePath}")
            val contentUri = FileProvider.getUriForFile(
                activity,
                "${activity.packageName}.fileprovider",
                file
            )
            Log.d(TAG, "FileProvider URI created: $contentUri")

            // Launch the system package installer
            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(contentUri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }

            Log.d(TAG, "Starting install intent...")
            activity.startActivity(installIntent)
            Log.d(TAG, "Install intent started successfully")
            result.success("success")

        } catch (e: Exception) {
            Log.e(TAG, "Failed to install APK", e)
            result.error("INSTALL_ERROR", "Failed to install APK: ${e.message}", e.stackTraceToString())
        }
    }
}
