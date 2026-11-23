package dev.riflay.riflay

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.RectF
import android.graphics.Shader
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.text.format.DateUtils
import android.util.Log
import android.view.KeyEvent
import android.view.View
import android.widget.RemoteViews
import com.ryanheise.audioservice.AudioServicePlugin
import com.ryanheise.audioservice.MediaButtonReceiver
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.lang.ref.WeakReference
import java.util.concurrent.Executors
import kotlin.math.PI
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sin

// The player on the home screen, made to look like the app's mini window: the cover large on the left, the title, the
// artist and the song's format, the line being sung in the song's accent with the next one under it, the elapsed
// time, a progress wave and the length, then shuffle, repeat, previous, play / pause on the scalloped accent button,
// next and like. One cell high it is the phone's mini player pill instead.
//
// Dart (lib/services/home_widget.dart) sends the song over riflay/home_widget when something shown changes; it is
// kept in preferences, so the widget can be drawn again (added, resized, the launcher restarted) without Dart. The
// lyric lines come on their own and are swapped in without drawing the rest; the elapsed time is a Chronometer, which
// counts by itself.
// Play / pause runs through the player controller's toggle, including when playback is still opening.
// Previous and next go through audio_service; like, shuffle and repeat are passed to Dart over the channel.
class PlayerWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = drawLater(context, ids)

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) =
        drawLater(context, intArrayOf(id))

    private fun drawLater(context: Context, ids: IntArray) {
        val done = goAsync()
        drawing.execute {
            try {
                draw(context.applicationContext, ids)
            } finally {
                done.finish()
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_KEY -> when (val key = intent.getIntExtra(EXTRA_KEY, KeyEvent.KEYCODE_UNKNOWN)) {
                // A launcher can keep the previous version's pending intents until it redraws the widget.
                KeyEvent.KEYCODE_MUTE, KeyEvent.KEYCODE_MEDIA_RECORD -> togglePlayback(context)
                else -> press(context, key)
            }
            ACTION_PLAYBACK -> togglePlayback(context)
            ACTION_LIKE -> toDart(context, "like")
            ACTION_SHUFFLE -> toDart(context, "shuffle")
            ACTION_REPEAT -> toDart(context, "repeat")
            else -> super.onReceive(context, intent)
        }
    }

    private fun togglePlayback(context: Context) {
        val app = context.applicationContext
        attach(app, AudioServicePlugin.getFlutterEngine(app))
        pendingPlaybackToggles++
        channel?.invokeMethod("playbackActionAvailable", null)
    }

    // Media keys as the notification sends them. When the app isn't running, its engine is started here, as the
    // playback service would start it, so that the widget is told what plays from the start.
    private fun press(context: Context, key: Int) {
        if (key == KeyEvent.KEYCODE_UNKNOWN) return
        attach(context.applicationContext, AudioServicePlugin.getFlutterEngine(context.applicationContext))
        val press = Intent(Intent.ACTION_MEDIA_BUTTON).setClass(context, MediaButtonReceiver::class.java)
            .putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, key))
        context.sendBroadcast(press)
    }

    // Like, shuffle and repeat act on the queue Dart holds: with no app running there is nothing to act on, so the
    // app is opened instead.
    private fun toDart(context: Context, method: String) {
        val engine = FlutterEngineCache.getInstance().get(AudioServicePlugin.getFlutterEngineId())
        if (engine == null) {
            context.startActivity(openApp(context).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return
        }
        attach(context.applicationContext, engine)
        channel?.invokeMethod(method, null)
    }

    companion object {
        private const val TAG = "PlayerWidget"
        private const val ACTION_KEY = "dev.riflay.riflay.widget.KEY"
        private const val ACTION_PLAYBACK = "dev.riflay.riflay.widget.PLAYBACK"
        private const val ACTION_LIKE = "dev.riflay.riflay.widget.LIKE"
        private const val ACTION_SHUFFLE = "dev.riflay.riflay.widget.SHUFFLE"
        private const val ACTION_REPEAT = "dev.riflay.riflay.widget.REPEAT"
        private const val EXTRA_KEY = "key"

        private const val PREFS = "player_widget"
        private const val STATE = "state"

        // Heights (dp) for what the two-row layout holds. Below PILL it is the one-row pill; it then needs about
        // 147 dp with the line being sung in the artist's place, 168 with its own row and 190 with the next line too.
        private const val PILL = 150
        private const val LYRIC_ROW = 170
        private const val NEXT_ROW = 192

        // The pill lets a little of the wallpaper through, as the Liquid glass mini player does; the card is the
        // mini window's, nearly solid.
        private const val PILL_ALPHA = 0xE0
        private const val CARD_ALPHA = 0xF5

        // Covers are decoded and pictures drawn off the main thread, one at a time, the newest state last.
        private val drawing = Executors.newSingleThreadExecutor()
        private val main = Handler(Looper.getMainLooper())

        private var attached = WeakReference<FlutterEngine>(null)
        private var channel: MethodChannel? = null
        // Dart may still be restoring its queue when a tap starts the engine.
        private var pendingPlaybackToggles = 0

        // Called for each activity, and from the widget's own buttons; one channel per engine.
        fun attach(context: Context, engine: FlutterEngine) {
            if (attached.get() === engine) return
            attached = WeakReference(engine)
            channel = MethodChannel(engine.dartExecutor.binaryMessenger, "riflay/home_widget").apply {
                setMethodCallHandler { call, result ->
                    if (call.method == "takePlaybackToggles") {
                        val count = pendingPlaybackToggles
                        pendingPlaybackToggles = 0
                        return@setMethodCallHandler result.success(count)
                    }
                    val args = (call.arguments as? Map<*, *>)?.let { JSONObject(it) }
                        ?: return@setMethodCallHandler result.error("args", "A map is expected", null)
                    val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    when (call.method) {
                        "update" -> {
                            // When the position was taken, on the clock the Chronometer counts from.
                            args.put("at", SystemClock.elapsedRealtime())
                            prefs.edit().putString(STATE, args.toString()).apply()
                            drawing.execute { draw(context, widgetIds(context)) }
                        }
                        // The lines being sung changed: kept with the rest, and swapped in without drawing it all.
                        "lyric" -> {
                            val state = prefs.getString(STATE, null)?.let { runCatching { JSONObject(it) }.getOrNull() }
                                ?: JSONObject()
                            for (key in listOf("lyric", "said", "next")) {
                                state.put(key, if (args.isNull(key)) JSONObject.NULL else args.opt(key))
                            }
                            prefs.edit().putString(STATE, state.toString()).apply()
                            drawing.execute { drawLyric(context, widgetIds(context), state) }
                        }
                        else -> return@setMethodCallHandler result.notImplemented()
                    }
                    result.success(null)
                }
            }
        }

        private fun widgetIds(context: Context) =
            AppWidgetManager.getInstance(context).getAppWidgetIds(ComponentName(context, PlayerWidget::class.java))

        private class Size(val widthDp: Int, val heightDp: Int) {
            val pill get() = heightDp < PILL
            val lyricRow get() = heightDp >= LYRIC_ROW
            val nextRow get() = heightDp >= NEXT_ROW
        }

        // Portrait sizes: the narrowest width and the tallest height the launcher gives it.
        private fun size(options: Bundle) = Size(
            widthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH).takeIf { it > 0 } ?: 300,
            heightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT).takeIf { it > 0 } ?: 200,
        )

        private fun layout(size: Size) = if (size.pill) R.layout.widget_player_small else R.layout.widget_player

        // The colours: the song's (a card tinted with its cover, from Dart) or else the widget's own, which on
        // Android 12 and later are the system's Material You colours (values-v31), light or dark.
        private class Look(
            val surface: Int, val onSurface: Int, val onSurfaceVariant: Int, val accent: Int, val onAccent: Int,
            val track: Int, val chip: Int, val round: Int,
        )

        private fun look(context: Context, state: JSONObject): Look {
            val colors = if (state.optBoolean("hasTrack")) state.optJSONObject("colors") else null
            if (colors != null) {
                return Look(
                    surface = colors.getLong("surface").toInt(),
                    onSurface = 0xFFFFFFFF.toInt(),
                    onSurfaceVariant = 0xB3FFFFFF.toInt(),
                    accent = colors.getLong("accent").toInt(),
                    onAccent = colors.getLong("onAccent").toInt(),
                    track = 0x33FFFFFF,
                    chip = R.drawable.widget_chip_on_dark,
                    round = R.drawable.widget_round_on_dark,
                )
            }
            return Look(
                surface = context.getColor(R.color.widget_surface),
                onSurface = context.getColor(R.color.widget_on_surface),
                onSurfaceVariant = context.getColor(R.color.widget_on_surface_variant),
                accent = context.getColor(R.color.widget_button),
                onAccent = context.getColor(R.color.widget_on_accent),
                track = context.getColor(R.color.widget_track),
                chip = R.drawable.widget_chip,
                round = R.drawable.widget_round,
            )
        }

        private fun artistOf(context: Context, state: JSONObject) =
            if (state.optBoolean("hasTrack")) state.text("artist").orEmpty()
            else state.optJSONObject("labels")?.text("open") ?: context.getString(R.string.widget_open_app)

        // The artist line and the lyric rows: the line being sung in the accent with the next one under it when
        // there is room; on a lower widget, and on the pill, in place of the artist, as the notification shows it.
        private fun lyricInto(views: RemoteViews, size: Size, state: JSONObject, artist: String, look: Look) {
            val hasTrack = state.optBoolean("hasTrack")
            val line = if (hasTrack) state.text("lyric") else null
            val under = if (size.lyricRow) artist else line ?: artist
            views.setTextViewText(R.id.widget_artist, under)
            views.setViewVisibility(R.id.widget_artist, if (under.isEmpty()) View.GONE else View.VISIBLE)
            if (size.pill) return
            // The rows stay while a song plays, holding their room: a faint ♪ between lines and without lyrics.
            views.setTextViewText(R.id.widget_lyric, line ?: "♪")
            views.setTextColor(R.id.widget_lyric, if (line != null) look.accent else look.onSurfaceVariant)
            views.setViewVisibility(R.id.widget_lyric, if (size.lyricRow && hasTrack) View.VISIBLE else View.GONE)
            // Under it: how it is read (Pronunciation on, a line in another script), else the line coming next.
            val under2 = if (hasTrack) state.text("said") ?: state.text("next") else null
            views.setTextViewText(R.id.widget_lyric_next, under2.orEmpty())
            views.setViewVisibility(R.id.widget_lyric_next, if (size.nextRow && hasTrack) View.VISIBLE else View.GONE)
        }

        private fun drawLyric(context: Context, ids: IntArray, state: JSONObject) {
            val manager = AppWidgetManager.getInstance(context)
            val artist = artistOf(context, state)
            val look = look(context, state)
            for (id in ids) {
                val size = size(manager.getAppWidgetOptions(id))
                val views = RemoteViews(context.packageName, layout(size))
                lyricInto(views, size, state, artist, look)
                main.post { runCatching { manager.partiallyUpdateAppWidget(id, views) } }
            }
        }

        private fun openApp(context: Context) = Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)

        private fun draw(context: Context, ids: IntArray) {
            val manager = AppWidgetManager.getInstance(context)
            val state = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(STATE, null)
                ?.let { runCatching { JSONObject(it) }.getOrNull() }
            for (id in ids) {
                try {
                    val views = build(context, state, manager.getAppWidgetOptions(id))
                    main.post { runCatching { manager.updateAppWidget(id, views) } }
                } catch (e: RuntimeException) {
                    Log.w(TAG, "Drawing widget $id: $e")
                }
            }
        }

        private fun build(context: Context, saved: JSONObject?, options: Bundle): RemoteViews {
            // Nothing sent yet (the app hasn't run since the widget was added): the widget's own text.
            val state = saved ?: JSONObject()
            val res = context.resources
            val dp = res.displayMetrics.density
            val size = size(options)
            val pill = size.pill
            val views = RemoteViews(context.packageName, layout(size))

            val hasTrack = state.optBoolean("hasTrack")
            val labels = state.optJSONObject("labels")
            fun label(key: String, fallback: Int) = labels?.text(key) ?: res.getString(fallback)
            val look = look(context, state)

            views.setInt(R.id.widget_card, "setColorFilter", look.surface)
            views.setInt(R.id.widget_card, "setImageAlpha", if (pill) PILL_ALPHA else CARD_ALPHA)

            views.setTextViewText(R.id.widget_title, state.text("title") ?: res.getString(R.string.widget_nothing_playing))
            views.setTextColor(R.id.widget_title, look.onSurface)
            views.setTextColor(R.id.widget_artist, look.onSurfaceVariant)
            lyricInto(views, size, state, artistOf(context, state), look)
            if (!pill) {
                views.setTextColor(R.id.widget_lyric_next, look.onSurfaceVariant)
                val quality = if (hasTrack) state.text("quality") else null
                views.setTextViewText(R.id.widget_quality, quality.orEmpty())
                views.setViewVisibility(R.id.widget_quality, if (quality == null) View.GONE else View.VISIBLE)
                views.setTextColor(R.id.widget_quality, look.onSurfaceVariant)
                views.setInt(R.id.widget_quality, "setBackgroundResource", look.chip)
            }

            // The cover: a round one on the pill, as the mini player's; a large rounded square on the card, as the
            // mini window's (drawn at the room it has, the ImageView keeping it square).
            val cover = if (hasTrack) state.text("cover") else null
            val coverPx = if (pill) (42 * dp).roundToInt() else ((size.heightDp - 102).coerceIn(48, 150) * dp).roundToInt()
            val picture = cover?.let { decode(it, coverPx * 2) }
            if (pill) {
                val thumb = picture?.let { rounded(it, coverPx, coverPx, coverPx / 2f) }
                if (thumb != null) {
                    views.setImageViewBitmap(R.id.widget_cover, thumb)
                    views.setInt(R.id.widget_cover, "setColorFilter", 0)
                    views.setInt(R.id.widget_cover, "setBackgroundResource", 0)
                } else {
                    views.setImageViewResource(R.id.widget_cover, R.drawable.ic_widget_note)
                    views.setInt(R.id.widget_cover, "setColorFilter", look.onSurfaceVariant)
                    views.setInt(R.id.widget_cover, "setBackgroundResource", look.round)
                }
            } else {
                val radius = coverPx * 0.13f
                val art = picture?.let { rounded(it, coverPx, coverPx, radius) }
                    ?: placeholder(context, coverPx, radius, look)
                views.setImageViewBitmap(R.id.widget_cover, art)
            }
            picture?.recycle()

            // Time: elapsed counts by itself while playing; the wave is drawn at what was known when last sent
            // (each song change, play, pause, seek and every 15 s).
            val playing = state.optBoolean("playing")
            val duration = state.optLong("duration")
            val sentAt = state.optLong("at", SystemClock.elapsedRealtime())
            val position = state.optLong("position").let {
                if (playing) it + (SystemClock.elapsedRealtime() - sentAt) else it
            }.coerceIn(0, if (duration > 0) duration else Long.MAX_VALUE)
            if (pill) {
                val permille = if (duration > 0) (position * 1000 / duration).toInt() else 0
                views.setProgressBar(R.id.widget_progress, 1000, permille, false)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    views.setColorStateList(R.id.widget_progress, "setProgressTintList", ColorStateList.valueOf(look.accent))
                    views.setColorStateList(R.id.widget_progress, "setProgressBackgroundTintList",
                        ColorStateList.valueOf(look.track))
                }
            } else {
                views.setChronometer(R.id.widget_elapsed, SystemClock.elapsedRealtime() - position, null,
                    playing && hasTrack)
                // Stopped, it would count from whenever the launcher draws it again: the time is written out.
                if (!playing || !hasTrack) views.setTextViewText(R.id.widget_elapsed, clock(position))
                views.setTextColor(R.id.widget_elapsed, look.onSurfaceVariant)
                views.setTextViewText(R.id.widget_duration, if (duration > 0) clock(duration) else "")
                views.setTextColor(R.id.widget_duration, look.onSurfaceVariant)
                val waveWidthDp = (size.widthDp - 26 - 2 * 34 - 16).coerceAtLeast(40)
                val fraction = if (duration > 0) position.toFloat() / duration else 0f
                views.setImageViewBitmap(R.id.widget_wave, wave(waveWidthDp, dp, fraction, look))
            }

            fun button(id: Int, enabled: Boolean, description: String, intent: PendingIntent, tint: Int = look.onSurface) {
                views.setInt(id, "setColorFilter", tint)
                views.setInt(id, "setImageAlpha", if (enabled) 255 else 97)
                views.setContentDescription(id, description)
                views.setOnClickPendingIntent(id, intent)
            }
            // The glyph follows the latest state, while clicks toggle the current player state.
            views.setImageViewResource(R.id.widget_play_icon, if (playing) R.drawable.ic_widget_pause else R.drawable.ic_widget_play)
            views.setInt(R.id.widget_play_icon, "setColorFilter", look.onAccent)
            views.setInt(R.id.widget_play_disc, "setColorFilter", look.accent)
            views.setContentDescription(R.id.widget_play,
                if (playing) label("pause", R.string.widget_pause) else label("play", R.string.widget_play))
            views.setOnClickPendingIntent(R.id.widget_play, broadcast(context, ACTION_PLAYBACK))
            button(R.id.widget_previous, state.optBoolean("hasQueue"), label("previous", R.string.widget_previous),
                key(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS))
            button(R.id.widget_next, state.optBoolean("hasNext"), label("next", R.string.widget_next),
                key(context, KeyEvent.KEYCODE_MEDIA_NEXT))
            // On, shuffle and repeat are drawn in the accent, as in the app; off, faded as an unused button is.
            val shuffle = state.optBoolean("shuffle")
            button(R.id.widget_shuffle, hasTrack && shuffle, label("shuffle", R.string.widget_shuffle),
                broadcast(context, ACTION_SHUFFLE), if (shuffle) look.accent else look.onSurfaceVariant)
            if (!pill) {
                val loop = state.text("loop") ?: "off"
                views.setImageViewResource(R.id.widget_repeat,
                    if (loop == "one") R.drawable.ic_widget_repeat_one else R.drawable.ic_widget_repeat)
                button(R.id.widget_repeat, hasTrack && loop != "off", label("repeat", R.string.widget_repeat),
                    broadcast(context, ACTION_REPEAT), if (loop != "off") look.accent else look.onSurfaceVariant)
            }
            // Always there, in either size. Null where the song can't be liked here (not signed in to YouTube Music,
            // or a song from elsewhere): faded, and it opens the app, where signing in is.
            val liked = if (hasTrack && !state.isNull("liked")) state.optBoolean("liked") else null
            views.setImageViewResource(R.id.widget_like,
                if (liked == true) R.drawable.ic_widget_favorite else R.drawable.ic_widget_favorite_border)
            button(R.id.widget_like, liked != null,
                if (liked == true) label("unlike", R.string.widget_unlike) else label("like", R.string.widget_like),
                if (liked == null) openAppIntent(context) else broadcast(context, ACTION_LIKE),
                if (liked == true) look.accent else look.onSurface)

            views.setContentDescription(R.id.widget_body, label("open", R.string.widget_open_app))
            views.setOnClickPendingIntent(R.id.widget_body, openAppIntent(context))
            return views
        }

        private fun clock(ms: Long): String = DateUtils.formatElapsedTime(ms / 1000)

        // A text field, or null when it is missing, empty or null (which optString would turn into "null").
        private fun JSONObject.text(key: String): String? = if (isNull(key)) null else optString(key).ifEmpty { null }

        private fun openAppIntent(context: Context) = PendingIntent.getActivity(context, 0, openApp(context),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        private fun key(context: Context, key: Int) = PendingIntent.getBroadcast(context, key,
            Intent(context, PlayerWidget::class.java).setAction(ACTION_KEY).putExtra(EXTRA_KEY, key),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        private fun broadcast(context: Context, action: String) = PendingIntent.getBroadcast(context, action.hashCode(),
            Intent(context, PlayerWidget::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        // The progress as the app draws it: a wave in the accent up to where the song is, a round thumb there, and a
        // straight faint line for the rest.
        private fun wave(widthDp: Int, dp: Float, fraction: Float, look: Look): Bitmap {
            val w = (widthDp * dp).roundToInt()
            val h = (14 * dp).roundToInt()
            val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(out)
            val mid = h / 2f
            val thumb = 5 * dp
            val x = (thumb + (w - 2 * thumb) * fraction.coerceIn(0f, 1f))
            val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = 3 * dp
                strokeCap = Paint.Cap.ROUND
            }
            stroke.color = look.track
            canvas.drawLine(x, mid, w - stroke.strokeWidth / 2, mid, stroke)
            stroke.color = look.accent
            val path = Path().apply {
                val amplitude = 2.6f * dp
                val length = 11 * dp
                moveTo(stroke.strokeWidth / 2, mid)
                var px = stroke.strokeWidth / 2
                while (px < x) {
                    lineTo(px, mid + amplitude * sin(2 * PI * px / length).toFloat())
                    px += dp / 2
                }
            }
            canvas.drawPath(path, stroke)
            canvas.drawCircle(x, mid, thumb, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = look.accent })
            return out
        }

        // A song without a cover: its place in the card's chip colour with a note, as the app shows one.
        private fun placeholder(context: Context, size: Int, radius: Float, look: Look): Bitmap {
            val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(out)
            val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0x26FFFFFF }
            canvas.drawRoundRect(RectF(0f, 0f, size.toFloat(), size.toFloat()), radius, radius, fill)
            context.getDrawable(R.drawable.ic_widget_note)?.let { note ->
                val inset = size * 0.32f
                note.setBounds(inset.toInt(), inset.toInt(), (size - inset).toInt(), (size - inset).toInt())
                note.colorFilter = PorterDuffColorFilter(look.onSurfaceVariant, PorterDuff.Mode.SRC_IN)
                note.draw(canvas)
            }
            return out
        }

        // The cover decoded at about [size] px across: a widget's pictures travel to the launcher whole, and Android
        // turns down a widget whose pictures outgrow the screen.
        private fun decode(path: String, size: Int): Bitmap? = try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            var sample = 1
            while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= size) sample *= 2
            BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
        } catch (e: OutOfMemoryError) {
            null
        }

        // [source] filling a [w] × [h] rounded picture, cropped to it and centred.
        private fun rounded(source: Bitmap, w: Int, h: Int, radius: Float): Bitmap? = try {
            val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val shader = BitmapShader(source, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
            val fill = max(w.toFloat() / source.width, h.toFloat() / source.height)
            shader.setLocalMatrix(Matrix().apply {
                setScale(fill, fill)
                postTranslate((w - source.width * fill) / 2, (h - source.height * fill) / 2)
            })
            val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply { this.shader = shader }
            Canvas(out).drawRoundRect(RectF(0f, 0f, w.toFloat(), h.toFloat()), radius, radius, paint)
            out
        } catch (e: OutOfMemoryError) {
            null
        }
    }
}
