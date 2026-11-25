package com.duoyi.duoyi

import android.graphics.Paint
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.util.DisplayMetrics
import android.util.TypedValue
import kotlin.math.ceil
import kotlin.math.roundToInt

/** Measure the same system-scaled fonts used by RemoteViews; all results are dp. */
class DuoyiWidgetTextMetrics(private val metrics: DisplayMetrics) {
    private val density = metrics.density.takeIf { it > 0f } ?: 1f

    private fun paint(sp: Float) = TextPaint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
        typeface = Typeface.DEFAULT
        textSize = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, sp, metrics)
    }

    private fun buildLayout(
        text: String,
        paint: TextPaint,
        widthPx: Int,
    ): StaticLayout {
        val builder = StaticLayout.Builder.obtain(text, 0, text.length, paint, widthPx.coerceAtLeast(1))
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setIncludePad(true)
            .setLineSpacing(0f, 1f)
            .setBreakStrategy(Layout.BREAK_STRATEGY_SIMPLE)
            .setHyphenationFrequency(Layout.HYPHENATION_FREQUENCY_NONE)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
            builder.setUseLineSpacingFromFallbacks(true)
        }
        return builder.build()
    }

    fun width(text: String, sp: Float): Int =
        ceil(paint(sp).measureText(text).toDouble() / density).toInt()

    fun line(sp: Float, includePadding: Boolean = true): Int {
        val fm = paint(sp).fontMetricsInt
        val pixels = if (includePadding) fm.bottom - fm.top else fm.descent - fm.ascent
        return ceil(pixels.toDouble() / density).toInt()
    }

    data class WrappedMeasurement(
        val fits: Boolean,
        val width: Int,
        val height: Int,
        val textHeight: Int,
        val lineCount: Int,
    )

    fun wrapped(text: String, sp: Float, width: Int): Int {
        if (width <= 0 || text.isEmpty()) return 0
        val widthPx = (width * density).toInt()
        if (widthPx <= 0) return 0
        val layout = buildLayout(text, paint(sp), widthPx)
        return ceil(layout.height.toDouble() / density).toInt()
    }

    fun measureWrappedAction(
        text: String,
        sp: Float,
        availableWidthDp: Int,
        minWidthDp: Int = 44,
        minHeightDp: Int = 34,
        horizontalPaddingDp: Int = 16,
        verticalPaddingDp: Int = 0,
    ): WrappedMeasurement {
        if (availableWidthDp <= 0) {
            return WrappedMeasurement(
                fits = false,
                width = minWidthDp,
                height = minHeightDp,
                textHeight = 0,
                lineCount = 0,
            )
        }
        val leftPadPx = if (horizontalPaddingDp > 0) (horizontalPaddingDp / 2f * density).roundToInt() else 0
        val rightPadPx = if (horizontalPaddingDp > 0) (horizontalPaddingDp / 2f * density).roundToInt() else 0
        val horizontalPadPx = leftPadPx + rightPadPx
        val totalWidthPx = (availableWidthDp * density).toInt()
        val innerWidthPx = totalWidthPx - horizontalPadPx
        if (innerWidthPx <= 0) {
            return WrappedMeasurement(
                fits = false,
                width = minWidthDp,
                height = minHeightDp,
                textHeight = 0,
                lineCount = 0,
            )
        }
        val p = paint(sp)
        val layout = buildLayout(text, p, innerWidthPx)
        val lineCount = layout.lineCount
        val textHeightDp = ceil(layout.height.toDouble() / density).toInt()
        var linesFit = lineCount > 0 && layout.getLineEnd(lineCount - 1) == text.length
        var maxLineWidthPx = 0f
        for (i in 0 until lineCount) {
            if (layout.getEllipsisCount(i) != 0) {
                linesFit = false
            }
            val lineLeft = layout.getLineLeft(i)
            val lineRight = layout.getLineRight(i)
            val lineWidth = layout.getLineWidth(i)
            if (lineLeft < 0f || lineRight > innerWidthPx.toFloat() || lineWidth > innerWidthPx.toFloat()) {
                linesFit = false
            }
            val span = lineRight - lineLeft
            if (span > maxLineWidthPx) {
                maxLineWidthPx = span
            }
            if (lineWidth > maxLineWidthPx) {
                maxLineWidthPx = lineWidth
            }
        }
        val measuredContentWidthDp = ceil(maxLineWidthPx.toDouble() / density).toInt()
        val frameWidthDp = maxOf(minWidthDp, measuredContentWidthDp + horizontalPaddingDp)
        val frameHeightDp = maxOf(minHeightDp, textHeightDp + verticalPaddingDp)
        val fits = linesFit && frameWidthDp <= availableWidthDp
        return WrappedMeasurement(
            fits = fits,
            width = frameWidthDp,
            height = frameHeightDp,
            textHeight = textHeightDp,
            lineCount = lineCount,
        )
    }

    fun measureWrapped(
        text: String,
        sp: Float,
        availableWidthDp: Int,
    ): WrappedMeasurement {
        if (availableWidthDp <= 0 || text.isEmpty()) {
            return WrappedMeasurement(
                fits = text.isEmpty() && availableWidthDp >= 0,
                width = 0,
                height = 0,
                textHeight = 0,
                lineCount = 0,
            )
        }
        val widthPx = (availableWidthDp * density).toInt()
        if (widthPx <= 0) {
            return WrappedMeasurement(
                fits = false,
                width = 0,
                height = 0,
                textHeight = 0,
                lineCount = 0,
            )
        }
        val p = paint(sp)
        val layout = buildLayout(text, p, widthPx)
        val lineCount = layout.lineCount
        val textHeightDp = ceil(layout.height.toDouble() / density).toInt()
        val maxWidthPx = widthPx.toFloat()
        var linesFit = lineCount > 0 && layout.getLineEnd(lineCount - 1) == text.length
        var maxLineWidthPx = 0f
        for (i in 0 until lineCount) {
            val lineStart = layout.getLineStart(i)
            val lineEnd = layout.getLineEnd(i)
            val lineVisibleEnd = layout.getLineVisibleEnd(i)
            val lineLeft = layout.getLineLeft(i)
            val lineRight = layout.getLineRight(i)
            val lineMax = layout.getLineMax(i)
            val lineWidth = layout.getLineWidth(i)

            val validRanges = lineStart >= 0 &&
                lineStart <= lineVisibleEnd &&
                lineVisibleEnd <= lineEnd &&
                lineEnd <= text.length
            val finiteNonNegative = lineLeft.isFinite() &&
                lineRight.isFinite() &&
                lineMax.isFinite() &&
                lineWidth.isFinite() &&
                lineLeft >= 0f &&
                lineRight >= 0f &&
                lineMax >= 0f &&
                lineWidth >= 0f
            val visibleBoundsFit = finiteNonNegative &&
                lineLeft <= lineRight &&
                lineLeft <= maxWidthPx &&
                lineRight <= maxWidthPx &&
                lineMax <= maxWidthPx
            val unconditionalBoundsOk = layout.getEllipsisCount(i) == 0 &&
                validRanges &&
                visibleBoundsFit

            var eligibleTrailingSpaceException = false
            if (unconditionalBoundsOk && lineWidth > maxWidthPx && i < lineCount - 1 && lineVisibleEnd < lineEnd) {
                var asciiSpaceSuffix = true
                for (offset in lineVisibleEnd until lineEnd) {
                    if (text[offset] != '\u0020') {
                        asciiSpaceSuffix = false
                        break
                    }
                }
                if (asciiSpaceSuffix && layout.getParagraphDirection(i) == Layout.DIR_LEFT_TO_RIGHT) {
                    var hasRtlRun = false
                    for (offset in lineStart until lineEnd) {
                        if (layout.isRtlCharAt(offset)) {
                            hasRtlRun = true
                            break
                        }
                    }
                    eligibleTrailingSpaceException = !hasRtlRun
                }
            }

            if (!unconditionalBoundsOk || (lineWidth > maxWidthPx && !eligibleTrailingSpaceException)) {
                linesFit = false
            }

            val span = lineRight - lineLeft
            if (span > maxLineWidthPx) {
                maxLineWidthPx = span
            }
            val advancePx = if (eligibleTrailingSpaceException) lineMax else lineWidth
            if (advancePx > maxLineWidthPx) {
                maxLineWidthPx = advancePx
            }
        }
        val measuredWidthDp = ceil(maxLineWidthPx.toDouble() / density).toInt()
        return WrappedMeasurement(
            fits = linesFit && measuredWidthDp <= availableWidthDp,
            width = measuredWidthDp,
            height = textHeightDp,
            textHeight = textHeightDp,
            lineCount = lineCount,
        )
    }

    fun hasLineSeparators(text: String): Boolean =
        text.contains('\n') || text.contains('\r') || text.contains('\u0085') ||
            text.contains('\u2028') || text.contains('\u2029')

    data class SingleLineMeasurement(
        val fits: Boolean,
        val width: Int,
        val height: Int,
    )

    fun measureSingleLine(
        text: String,
        sp: Float,
        availableWidthDp: Int,
        minWidthDp: Int = 0,
        minHeightDp: Int = 0,
        horizontalPaddingDp: Int = 0,
        verticalPaddingDp: Int = 0,
    ): SingleLineMeasurement {
        val baseLineHeight = maxOf(minHeightDp, line(sp, includePadding = true) + verticalPaddingDp)
        if (text.isEmpty()) {
            return SingleLineMeasurement(
                fits = availableWidthDp >= minWidthDp,
                width = minWidthDp,
                height = baseLineHeight,
            )
        }
        if (hasLineSeparators(text) || availableWidthDp <= 0) {
            val textWidth = ceil(paint(sp).measureText(text).toDouble() / density).toInt()
            return SingleLineMeasurement(
                fits = false,
                width = maxOf(minWidthDp, textWidth + horizontalPaddingDp),
                height = baseLineHeight,
            )
        }
        val leftPadPx = if (horizontalPaddingDp > 0) (horizontalPaddingDp / 2f * density).roundToInt() else 0
        val rightPadPx = if (horizontalPaddingDp > 0) (horizontalPaddingDp / 2f * density).roundToInt() else 0
        val horizontalPadPx = leftPadPx + rightPadPx
        val totalWidthPx = (availableWidthDp * density).toInt()
        val innerWidthPx = totalWidthPx - horizontalPadPx
        if (innerWidthPx <= 0) {
            val textWidth = ceil(paint(sp).measureText(text).toDouble() / density).toInt()
            return SingleLineMeasurement(
                fits = false,
                width = maxOf(minWidthDp, textWidth + horizontalPaddingDp),
                height = baseLineHeight,
            )
        }
        val p = paint(sp)
        val layout = buildLayout(text, p, innerWidthPx)
        val layoutHeightDp = ceil(layout.height.toDouble() / density).toInt()
        val frameHeightDp = maxOf(minHeightDp, maxOf(baseLineHeight, layoutHeightDp + verticalPaddingDp))
        val measuredAdvancePx = p.measureText(text)

        var linesFit = layout.lineCount == 1 &&
            layout.getLineEnd(0) == text.length &&
            layout.getEllipsisCount(0) == 0
        val lineLeft = layout.getLineLeft(0)
        val lineRight = layout.getLineRight(0)
        val lineWidth = layout.getLineWidth(0)
        if (lineLeft < 0f || lineRight > innerWidthPx.toFloat() || lineWidth > innerWidthPx.toFloat() || measuredAdvancePx > innerWidthPx.toFloat()) {
            linesFit = false
        }
        val measuredContentWidthDp = ceil(maxOf(lineRight - lineLeft, lineWidth).toDouble() / density).toInt()
        val frameWidthDp = maxOf(minWidthDp, measuredContentWidthDp + horizontalPaddingDp)
        val fits = linesFit && frameWidthDp <= availableWidthDp
        return SingleLineMeasurement(
            fits = fits,
            width = frameWidthDp,
            height = frameHeightDp,
        )
    }

    fun fitsSingleLine(text: String, sp: Float, widthDp: Int): Boolean =
        measureSingleLine(text, sp, widthDp).fits
}
