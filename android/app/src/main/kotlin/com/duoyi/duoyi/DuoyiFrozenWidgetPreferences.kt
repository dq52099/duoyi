package com.duoyi.duoyi

import android.content.SharedPreferences

/** All reads use the same defensive copy; renderers have no editor or live listener. */
class DuoyiFrozenWidgetPreferences(values: Map<String, *>) : SharedPreferences {
    private val values = DuoyiWidgetFrameCore.immutableValues(values)

    override fun getAll(): Map<String, *> = values
    override fun contains(key: String?): Boolean = values.containsKey(key)
    override fun getString(key: String?, defValue: String?): String? =
        (values[key] as String?) ?: defValue

    @Suppress("UNCHECKED_CAST")
    override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? =
        (values[key] as MutableSet<String>?) ?: defValues?.toMutableSet()

    override fun getInt(key: String?, defValue: Int): Int = (values[key] as Int?) ?: defValue
    override fun getLong(key: String?, defValue: Long): Long = (values[key] as Long?) ?: defValue
    override fun getFloat(key: String?, defValue: Float): Float = (values[key] as Float?) ?: defValue
    override fun getBoolean(key: String?, defValue: Boolean): Boolean = (values[key] as Boolean?) ?: defValue
    override fun edit(): SharedPreferences.Editor =
        throw UnsupportedOperationException("Widget rendering preferences are read-only")

    override fun registerOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) {
        throw UnsupportedOperationException("Widget rendering preferences do not support listeners")
    }

    override fun unregisterOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) {
        // No listener can be registered with this immutable view.
    }
}
