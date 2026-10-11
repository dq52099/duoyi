package com.duoyi.duoyi

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DuoyiWidgetLaunchQueueTest {
    @Test
    fun repeatedActionTapsHaveDistinctDeliveryIdsAndKeepReceiveOrder() {
        var sequence = 0
        val queue = DuoyiWidgetLaunchQueue { "tap-${++sequence}" }
        val first = queue.receive { "duoyi://action/checkin_habit?id=habit&widget_delivery=$it" }!!
        val second = queue.receive { "duoyi://action/checkin_habit?id=habit&widget_delivery=$it" }!!
        assertNotEquals(first.id, second.id)
        assertEquals(listOf(first, second), queue.snapshot())
    }

    @Test
    fun drainingDoesNotRemoveAnUnacknowledgedColdTap() {
        val queue = DuoyiWidgetLaunchQueue { "cold-tap" }
        val delivery = queue.receive { "duoyi://todo/task?widget_delivery=$it" }!!
        assertEquals(listOf(delivery), queue.snapshot())
        assertEquals(listOf(delivery), queue.snapshot())
        assertEquals(mapOf("id" to delivery.id, "uri" to delivery.uri), delivery.payload())
    }

    @Test
    fun acknowledgementsAreIdempotentAndDoNotClearOtherTaps() {
        var sequence = 0
        val queue = DuoyiWidgetLaunchQueue { "tap-${++sequence}" }
        val first = queue.receive { "duoyi://habit/habit?widget_delivery=$it" }!!
        val second = queue.receive { "duoyi://habit/habit?widget_delivery=$it" }!!
        queue.acknowledge("unknown")
        queue.acknowledge(first.id)
        queue.acknowledge(first.id)
        assertEquals(listOf(second), queue.snapshot())
        queue.acknowledge(second.id)
        assertTrue(queue.snapshot().isEmpty())
    }

    @Test
    fun overflowRejectsNewestAndAckMakesRoomWithoutEvictingOlderTaps() {
        var sequence = 0
        val queue = DuoyiWidgetLaunchQueue(maxPending = 2) { "tap-${++sequence}" }
        val first = queue.receive { "duoyi://habit/habit?widget_delivery=$it" }!!
        val second = queue.receive { "duoyi://habit/habit?widget_delivery=$it" }!!
        assertEquals(null, queue.receive { "duoyi://habit/habit?widget_delivery=$it" })
        assertEquals(listOf(first, second), queue.snapshot())
        queue.acknowledge(first.id)
        val third = queue.receive { "duoyi://habit/habit?widget_delivery=$it" }!!
        assertEquals(listOf(second, third), queue.snapshot())
    }

    @Test
    fun earlyLaunchBurstIsNotCollapsedIntoTheLatestIntent() {
        var sequence = 0
        val queue = DuoyiWidgetLaunchQueue { "tap-${++sequence}" }
        repeat(40) { queue.receive { "duoyi://action/checkin_habit?id=habit&widget_delivery=$it" } }
        assertEquals(40, queue.snapshot().size)
        assertEquals(40, queue.snapshot().map { it.id }.toSet().size)
        assertEquals("tap-1", queue.snapshot().first().id)
        assertEquals("tap-40", queue.snapshot().last().id)
    }
}
