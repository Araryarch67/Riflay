package dev.riflay.riflay

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

// Only Riflay's own checked cache files can reach the system installer.
@Suppress("DEPRECATION")
class AppUpdater(private val activity: Activity, messenger: BinaryMessenger) {
    private var pending: MethodChannel.Result? = null
    private var pendingFile: File? = null

    init {
        MethodChannel(messenger, "riflay/updates").setMethodCallHandler { call, result ->
            when (call.method) {
                "info" -> result.success(mapOf(
                    "version" to installed().versionName,
                    "abis" to Build.SUPPORTED_ABIS.toList(),
                ))
                "install" -> install(call.arguments as? String, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun installed(): PackageInfo = activity.packageManager.getPackageInfo(activity.packageName, flags())
    private fun flags() = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
    private fun version(info: PackageInfo) = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
    private fun signers(info: PackageInfo): Set<String> =
        (if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures)
            ?.map { it.toCharsString() }?.toSet() ?: emptySet()

    private fun checkedFile(path: String?): File {
        require(path != null) { "Missing APK" }
        val file = File(path).canonicalFile
        val folder = File(activity.cacheDir, "app-updates").canonicalFile
        require(file.parentFile == folder && file.extension == "apk" && file.isFile) { "APK outside update cache" }
        val archive = activity.packageManager.getPackageArchiveInfo(file.path, flags())
            ?: throw IllegalArgumentException("Invalid APK")
        require(archive.packageName == activity.packageName) { "Wrong application" }
        val current = installed()
        require(version(archive) > version(current)) { "Update must have a newer version code" }
        val expected = signers(current)
        if (expected.isEmpty() || signers(archive) != expected) throw SignatureMismatch()
        return file
    }

    private fun install(path: String?, result: MethodChannel.Result) {
        if (pending != null) return result.error("busy", "An install request is already pending", null)
        try {
            val file = checkedFile(path)
            if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
                pending = result
                pendingFile = file
                activity.startActivityForResult(
                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")),
                    REQUEST_INSTALL_PERMISSION,
                )
            } else {
                openInstaller(file)
                result.success(true)
            }
        } catch (error: Exception) {
            pending = null
            pendingFile = null
            result.error(if (error is SignatureMismatch) "signature" else "install", error.message, null)
        }
    }

    private fun openInstaller(file: File) {
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", file)
        activity.startActivity(Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        })
    }

    fun onActivityResult(requestCode: Int) {
        if (requestCode != REQUEST_INSTALL_PERMISSION) return
        val result = pending ?: return
        val file = pendingFile
        pending = null
        pendingFile = null
        if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
            result.success(false)
            return
        }
        install(file?.path, result)
    }

    fun dispose() {
        pending?.success(false)
        pending = null
        pendingFile = null
    }

    private companion object {
        const val REQUEST_INSTALL_PERMISSION = 7302
    }

    private class SignatureMismatch : Exception("Different signing key")
}
