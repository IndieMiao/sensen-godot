// C3 Photo Picker（Android）：系统 Photo Picker（Android 13+，`ACTION_PICK_IMAGES`，不要相册权限）薄桥接；
// 老系统退回 `ACTION_OPEN_DOCUMENT`（同样免权限，只是界面是文档选择器）。选完在原生层解码、按 EXIF 摆正、
// 长边缩到 maxSide、转 JPEG 落到 cacheDir，只把路径交回 Godot。接口与 iOS 桥一致：
// isAvailable() / pickImages(maxCount, maxSide, quality) / 信号 picked(paths, error)。
package app.sensen.photopicker

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.exifinterface.media.ExifInterface
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import kotlin.math.max
import kotlin.math.min

class SensenPhotoPickerPlugin(godot: Godot) : GodotPlugin(godot) {
    companion object {
        const val REQUEST_CODE = 0x5E5E
        const val SIGNAL_PICKED = "picked"
    }

    @Volatile private var picking = false
    private var maxSide = 2048
    private var quality = 85

    override fun getPluginName() = "SensenPhotoPicker"

    override fun getPluginSignals() = setOf(SignalInfo(SIGNAL_PICKED, Array<String>::class.java, String::class.java))

    @UsedByGodot
    fun isAvailable(): Boolean = activity != null

    @UsedByGodot
    fun isPicking(): Boolean = picking

    /** 弹系统选图器；结果走 picked 信号（取消 = 空数组）。返回 false = 没弹出来。 */
    @UsedByGodot
    fun pickImages(maxCount: Int, maxSideArg: Int, jpegQuality: Float): Boolean {
        val act = activity ?: return false
        if (picking) return false
        picking = true
        maxSide = maxSideArg
        quality = (jpegQuality.coerceIn(0.1f, 1f) * 100).toInt()
        val count = max(1, maxCount)
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                type = "image/*"
                if (count > 1) putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, min(count, MediaStore.getPickImagesMaxLimit()))
            }
        } else {
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "image/*"
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, count > 1)
            }
        }
        return try {
            act.runOnUiThread { act.startActivityForResult(intent, REQUEST_CODE) }
            true
        } catch (e: Exception) {
            picking = false
            false
        }
    }

    override fun onMainActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST_CODE) return
        val act = activity
        val uris = ArrayList<Uri>()
        if (resultCode == Activity.RESULT_OK && data != null) {
            val clip = data.clipData
            if (clip != null) for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
            else data.data?.let { uris.add(it) }
        }
        if (act == null || uris.isEmpty()) { deliver(emptyList(), ""); return }
        // 解码 + 缩放在后台线程做；一张 12MP 的 JPEG 要几百毫秒。
        Thread {
            val dir = File(act.cacheDir, "sensen_picks").apply { mkdirs() }
            val paths = ArrayList<String>()
            for (uri in uris) {
                try {
                    val out = File(dir, UUID.randomUUID().toString() + ".jpg")
                    val bmp = loadScaled(act, uri) ?: continue
                    FileOutputStream(out).use { bmp.compress(Bitmap.CompressFormat.JPEG, quality, it) }
                    bmp.recycle()
                    paths.add(out.absolutePath)
                } catch (e: Exception) {
                    // 单张失败跳过，其余照常返回
                }
            }
            deliver(paths, "")
        }.start()
    }

    private fun deliver(paths: List<String>, error: String) {
        picking = false
        emitSignal(SIGNAL_PICKED, paths.toTypedArray(), error)
    }

    /** 先只读尺寸算 inSampleSize（省内存），再解码、按 EXIF 摆正、精确缩到长边 maxSide。 */
    private fun loadScaled(act: Activity, uri: Uri): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        act.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        if (maxSide > 0) while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxSide) sample *= 2
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        var bmp = act.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, opts) } ?: return null
        val orientation = act.contentResolver.openInputStream(uri)?.use {
            ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        } ?: ExifInterface.ORIENTATION_NORMAL
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.preScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.preScale(1f, -1f)
        }
        val longest = max(bmp.width, bmp.height)
        if (maxSide > 0 && longest > maxSide) {
            val f = maxSide.toFloat() / longest
            matrix.postScale(f, f)
        }
        if (!matrix.isIdentity) {
            val fixed = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, matrix, true)
            if (fixed !== bmp) bmp.recycle()
            bmp = fixed
        }
        return bmp
    }
}
