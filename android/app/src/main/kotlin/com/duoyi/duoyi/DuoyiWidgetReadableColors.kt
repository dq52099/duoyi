package com.duoyi.duoyi

import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/** Foreground resolution for known opaque widget surfaces, never image pixels. */
internal object DuoyiWidgetReadableColors {
    fun foreground(preferred: Int, backgrounds: IntArray): Int {
        if (backgrounds.isEmpty()) return preferred
        fun minimumContrast(color: Int) = backgrounds.minOf { contrast(color, it) }
        if (minimumContrast(preferred) >= 4.5) return preferred
        val black = 0xFF000000.toInt()
        val white = 0xFFFFFFFF.toInt()
        return if (minimumContrast(black) >= minimumContrast(white)) black else white
    }

    fun contrast(foreground: Int, background: Int): Double {
        val alpha = (foreground ushr 24) / 255.0
        fun luminance(color: Int, blendAlpha: Double): Double {
            fun linear(shift: Int): Double {
                val channel = (((color ushr shift) and 255) * blendAlpha +
                    ((background ushr shift) and 255) * (1 - blendAlpha)) / 255.0
                return if (channel <= 0.04045) channel / 12.92
                    else ((channel + 0.055) / 1.055).pow(2.4)
            }
            return 0.2126 * linear(16) + 0.7152 * linear(8) + 0.0722 * linear(0)
        }
        val front = luminance(foreground, alpha)
        val back = luminance(background, 1.0)
        return (max(front, back) + 0.05) / (min(front, back) + 0.05)
    }
}
