package com.duoyi.duoyi

import android.appwidget.AppWidgetManager
import android.os.Build
import android.os.Bundle
import android.util.SizeF

data class DuoyiWidgetPinStyle(
    val id: String,
    val minWidth: Int,
    val minHeight: Int,
    val maxWidth: Int,
    val maxHeight: Int,
    val targetCellWidth: Int,
    val targetCellHeight: Int,
) {
    fun toOptions(): Bundle {
        return Bundle().apply {
            putString("duoyi_widget_style", id)
            putInt("duoyi_widget_target_cell_width", targetCellWidth)
            putInt("duoyi_widget_target_cell_height", targetCellHeight)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, minWidth)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, minHeight)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, maxWidth)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, maxHeight)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                putParcelableArrayList(
                    AppWidgetManager.OPTION_APPWIDGET_SIZES,
                    arrayListOf(
                        SizeF(minWidth.toFloat(), minHeight.toFloat()),
                        SizeF(maxWidth.toFloat(), maxHeight.toFloat()),
                    ),
                )
            }
        }
    }

    fun toDisplayModeOptions(): Bundle {
        return Bundle().apply {
            putString("duoyi_widget_style", id)
            putInt("duoyi_widget_target_cell_width", targetCellWidth)
            putInt("duoyi_widget_target_cell_height", targetCellHeight)
        }
    }

    companion object {
        fun fromId(id: String?): DuoyiWidgetPinStyle {
            return when (id) {
                "compact" -> compact
                "detailed" -> detailed
                else -> standard
            }
        }

        fun fromWidgetOptions(options: Bundle): DuoyiWidgetPinStyle? {
            when (options.getString("duoyi_widget_style")) {
                "compact" -> return compact
                "standard" -> return standard
                "detailed" -> return detailed
            }

            val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, -1)
            val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, -1)
            if (minWidth > 0 && minHeight > 0) {
                return when {
                    minWidth >= detailed.minWidth || minHeight >= detailed.minHeight -> detailed
                    minWidth <= compact.maxWidth && minHeight <= compact.maxHeight -> compact
                    else -> standard
                }
            }

            val targetCellWidth = options.getInt("duoyi_widget_target_cell_width", -1)
            val targetCellHeight = options.getInt("duoyi_widget_target_cell_height", -1)
            if (targetCellWidth > 0 && targetCellHeight > 0) {
                return when {
                    targetCellWidth >= detailed.targetCellWidth ||
                        targetCellHeight >= detailed.targetCellHeight -> detailed
                    targetCellWidth <= compact.targetCellWidth &&
                        targetCellHeight <= compact.targetCellHeight -> compact
                    else -> standard
                }
            }
            return null
        }

        private val compact = DuoyiWidgetPinStyle(
            id = "compact",
            minWidth = 110,
            minHeight = 110,
            maxWidth = 110,
            maxHeight = 110,
            targetCellWidth = 2,
            targetCellHeight = 2,
        )

        private val standard = DuoyiWidgetPinStyle(
            id = "standard",
            minWidth = 180,
            minHeight = 110,
            maxWidth = 180,
            maxHeight = 110,
            targetCellWidth = 3,
            targetCellHeight = 2,
        )

        private val detailed = DuoyiWidgetPinStyle(
            id = "detailed",
            minWidth = 250,
            minHeight = 180,
            maxWidth = 250,
            maxHeight = 180,
            targetCellWidth = 4,
            targetCellHeight = 3,
        )
    }
}
