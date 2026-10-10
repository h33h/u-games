package dev.ugames

import android.content.Context
import android.graphics.Color
import android.graphics.RectF
import android.graphics.drawable.GradientDrawable
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.widget.ImageButton
import androidx.core.view.WindowInsetsCompat
import kotlin.math.hypot

/** Only the button consumes touches; no transparent overlay covers the game. */
class FloatingMenuButton(context: Context) : ImageButton(context) {
    private val preferences = context.getSharedPreferences("gameMenu", Context.MODE_PRIVATE)
    private var fractionX = preferences.getFloat("x", 1f)
    private var fractionY = preferences.getFloat("y", 0.2f)
    private val margin = 8 * resources.displayMetrics.density
    private val slop = ViewConfiguration.get(context).scaledTouchSlop
    private var downX = 0f
    private var downY = 0f
    private var originX = 0f
    private var originY = 0f
    private var dragging = false

    init {
        contentDescription = "Меню"
        setImageResource(android.R.drawable.ic_menu_more)
        setColorFilter(Color.WHITE)
        background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.argb(166, 0, 0, 0))
        }
        val padding = (12 * resources.displayMetrics.density).toInt()
        setPadding(padding, padding, padding, padding)
    }

    private fun movementArea(): RectF? {
        val container = parent as? ViewGroup ?: return null
        val gestures = container.rootWindowInsets?.let {
            WindowInsetsCompat.toWindowInsetsCompat(it, container)
                .getInsets(WindowInsetsCompat.Type.systemGestures())
        }
        val left = maxOf(container.paddingLeft, gestures?.left ?: 0) + margin
        val top = maxOf(container.paddingTop, gestures?.top ?: 0) + margin
        val right = container.width - maxOf(container.paddingRight, gestures?.right ?: 0)
        val bottom = container.height - maxOf(container.paddingBottom, gestures?.bottom ?: 0)
        return RectF(
            left,
            top,
            (right - width - margin).coerceAtLeast(left),
            (bottom - height - margin).coerceAtLeast(top)
        )
    }

    fun place() {
        val area = movementArea() ?: return
        x = area.left + area.width() * fractionX.coerceIn(0f, 1f)
        y = area.top + area.height() * fractionY.coerceIn(0f, 1f)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.rawX
                downY = event.rawY
                originX = x
                originY = y
                dragging = false
                isPressed = true
                parent.requestDisallowInterceptTouchEvent(true)
            }

            MotionEvent.ACTION_MOVE -> {
                val dx = event.rawX - downX
                val dy = event.rawY - downY
                if (!dragging && hypot(dx, dy) > slop) {
                    dragging = true
                    isPressed = false
                }
                if (dragging) moveTo(originX + dx, originY + dy)
            }

            MotionEvent.ACTION_UP -> {
                isPressed = false
                parent.requestDisallowInterceptTouchEvent(false)
                if (dragging) savePosition() else performClick()
            }

            MotionEvent.ACTION_CANCEL -> {
                isPressed = false
                parent.requestDisallowInterceptTouchEvent(false)
                if (dragging) savePosition()
            }
        }
        return true
    }

    override fun performClick(): Boolean = super.performClick()

    private fun moveTo(targetX: Float, targetY: Float) {
        val area = movementArea() ?: return
        fractionX = if (area.width() > 0) {
            ((targetX - area.left) / area.width()).coerceIn(0f, 1f)
        } else {
            0f
        }
        fractionY = if (area.height() > 0) {
            ((targetY - area.top) / area.height()).coerceIn(0f, 1f)
        } else {
            0f
        }
        place()
    }

    private fun savePosition() {
        preferences.edit().putFloat("x", fractionX).putFloat("y", fractionY).apply()
    }
}
