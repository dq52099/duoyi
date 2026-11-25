package com.duoyi.duoyi

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DuoyiWidgetReadableColorsTest {
    @Test fun plainTextPassesAcrossItsActualSurfacesWithoutChangingFills() {
        for (glass in listOf(false, true)) {
            val theme = palette(glass)
            for (background in intArrayOf(theme.background, theme.surface, theme.navBackground)) {
                assertTrue(DuoyiWidgetReadableColors.contrast(theme.readablePrimary, background) >= 4.5)
                assertTrue(DuoyiWidgetReadableColors.contrast(theme.readableMutedText, background) >= 4.5)
            }
            assertTrue(DuoyiWidgetReadableColors.contrast(theme.readableOnPrimary, theme.primary) >= 4.5)
            assertEquals(if (glass) 0xFF0A6CDB.toInt() else 0xFF0066D6.toInt(), theme.primary)
            assertEquals(theme.primary, theme.readablePrimary)
            assertEquals(theme.onPrimary, theme.readableOnPrimary)
        }
    }

    @Test fun paperCardPassesAcrossItsActualSurfacesWithoutChangingFills() {
        for (glass in listOf(false, true)) {
            val theme = paperPalette(glass)
            for (background in intArrayOf(theme.background, theme.surface, theme.navBackground)) {
                assertTrue(DuoyiWidgetReadableColors.contrast(theme.readablePrimary, background) >= 4.5)
                assertTrue(DuoyiWidgetReadableColors.contrast(theme.readableMutedText, background) >= 4.5)
            }
            assertTrue(DuoyiWidgetReadableColors.contrast(theme.readableOnPrimary, theme.primary) >= 4.5)
            assertEquals(if (glass) 0xFF0A6CDB.toInt() else 0xFF0066D6.toInt(), theme.primary)
            // On paper_card's actual surfaces, defaultBrand primary #0066D6 hits 4.58:1 (>= 4.5)
            // on navBackground #E6EDF0 and retains its color; liquidGlass primary #0A6CDB hits
            // 4.35:1 on #EDEFEE and 4.08:1 on #E0E9EE (< 4.5), so readablePrimary falls back to
            // black. White onPrimary retains >= 5.02:1 against both primaries.
            assertEquals(if (glass) 0xFF000000.toInt() else theme.primary, theme.readablePrimary)
            assertEquals(theme.onPrimary, theme.readableOnPrimary)
        }
    }

    @Test fun skinsImagesOtherBrandsAndTransparentSurfacesRetainTheirOwnColors() {
        val base = palette(false)
        for (theme in listOf(
            base.copy(cardSkinId = "unsupported_card"),
            base.copy(backgroundAssetKey = "re0"),
            base.copy(brandId = "re0"),
            base.copy(background = 0x80F6F7F9.toInt()),
        )) {
            assertEquals(theme.primary, theme.readablePrimary)
            assertEquals(theme.mutedText, theme.readableMutedText)
            assertEquals(theme.onPrimary, theme.readableOnPrimary)
        }
    }

    @Test fun alphaIsMeasuredAfterCompositingAndReadablePreferredColorIsRetained() {
        val transparentButton = palette(false).copy(primary = 0x00000000)
        assertEquals(transparentButton.onPrimary, transparentButton.readableOnPrimary)
        assertEquals(21.0, DuoyiWidgetReadableColors.contrast(0xFF000000.toInt(), 0xFFFFFFFF.toInt()), 0.001)
        assertEquals(1.0, DuoyiWidgetReadableColors.contrast(0x00000000, 0xFFFFFFFF.toInt()), 0.001)
        assertEquals(0xFF000000.toInt(), DuoyiWidgetReadableColors.foreground(
            0x40000000, intArrayOf(0xFFFFFFFF.toInt()),
        ))
    }

    private fun palette(glass: Boolean) = DuoyiWidgetThemePalette(
        brandId = if (glass) "liquidGlass" else "defaultBrand", cardSkinId = "plain_card", dark = false,
        primary = if (glass) 0xFF0A6CDB.toInt() else 0xFF0066D6.toInt(),
        background = if (glass) 0xFFF3F6FA.toInt() else 0xFFF6F7F9.toInt(),
        surface = if (glass) 0xFFF9FAFC.toInt() else 0xFFFFFFFF.toInt(),
        navBackground = if (glass) 0xFFEFF3F9.toInt() else 0xFFF1F3F6.toInt(),
        border = 0, text = 0xFF1F2933.toInt(),
        mutedText = if (glass) 0xFF17233B.toInt() else 0xFF667085.toInt(),
        onPrimary = 0xFFFFFFFF.toInt(), accentStart = 0, accentEnd = 0,
        backgroundAssetKey = "", cornerRadiusDp = 16, controlRadiusDp = 12,
        borderWidthDp = if (glass) 1 else 0,
    )

    private fun paperPalette(glass: Boolean) = DuoyiWidgetThemePalette(
        brandId = if (glass) "liquidGlass" else "defaultBrand", cardSkinId = "paper_card", dark = false,
        primary = if (glass) 0xFF0A6CDB.toInt() else 0xFF0066D6.toInt(),
        background = if (glass) 0xFFEDEFEE.toInt() else 0xFFF8F6F1.toInt(),
        surface = if (glass) 0xFFF8F7F0.toInt() else 0xFFFFFCF3.toInt(),
        navBackground = if (glass) 0xFFE0E9EE.toInt() else 0xFFE6EDF0.toInt(),
        border = 0xFF57544D.toInt(),
        text = if (glass) 0xFF17233B.toInt() else 0xFF1F2933.toInt(),
        mutedText = if (glass) 0xFF17233B.toInt() else 0xFF1F2933.toInt(),
        onPrimary = 0xFFFFFFFF.toInt(), accentStart = 0xFFFFF8E1.toInt(), accentEnd = 0xFFFFECB3.toInt(),
        backgroundAssetKey = "", cornerRadiusDp = 14, controlRadiusDp = 8,
        borderWidthDp = 1,
    )
}
