package com.vicolo.chrono

import android.accessibilityservice.AccessibilityService
import android.content.ComponentName
import android.content.Context
import android.provider.Settings
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import java.io.File

/**
 * Opt-in "prevent power off while ringing". While an alarm is ringing, closes
 * the system power menu (long-press power / quick-settings power button) as
 * soon as it opens, so the phone can't be switched off to silence the alarm.
 *
 * Only window-state changes are observed (no window content is read). The
 * hardware force-restart combo can't be intercepted, so this adds friction
 * rather than making the phone impossible to turn off.
 *
 * "Ringing" is signalled by the alarm isolate, which runs in a background
 * FlutterEngine that can't reach MainActivity's channels. It writes an expiry
 * timestamp (epoch ms) to a file instead; see lib/system/logic/power_guard.dart.
 * The expiry bounds a missed disarm (e.g. the isolate killed mid-ring).
 */
class PowerGuardService : AccessibilityService() {

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val className = event.className?.toString() ?: return
        val isPowerMenu = looksLikePowerMenu(className)
        val isSystemUi = event.packageName?.toString() == "com.android.systemui"
        if (!isPowerMenu && !isSystemUi) return
        if (!isArmed(this)) return

        if (isPowerMenu) {
            Log.i(TAG, "Alarm ringing: closing power menu ($className)")
            performGlobalAction(GLOBAL_ACTION_BACK)
        } else {
            // Helps identify OEM power menus that don't match on-device
            // (adb logcat -s ChronoPowerGuard).
            Log.d(TAG, "Alarm ringing: ignoring system UI window $className")
        }
    }

    override fun onInterrupt() {}

    companion object {
        private const val TAG = "ChronoPowerGuard"

        // Must match the Dart side: <getApplicationDocumentsDirectory()>/Clock/
        // power_guard_until.txt. path_provider's documents dir on Android is
        // Context.getDir("flutter", MODE_PRIVATE).
        private const val ARM_FILE = "Clock/power_guard_until.txt"

        // AOSP: GlobalActionsDialog(Lite); Samsung/MIUI variants keep
        // "GlobalActions" or use a shutdown/power-off dialog name.
        private val POWER_MENU_MARKERS = listOf("globalactions", "shutdown", "poweroff")

        fun looksLikePowerMenu(className: String): Boolean {
            val name = className.lowercase()
            return POWER_MENU_MARKERS.any { name.contains(it) }
        }

        fun isArmed(context: Context): Boolean {
            return try {
                val file = File(context.getDir("flutter", Context.MODE_PRIVATE), ARM_FILE)
                if (!file.exists()) return false
                val until = file.readText().trim().toLongOrNull() ?: return false
                System.currentTimeMillis() < until
            } catch (e: Exception) {
                Log.w(TAG, "Could not read power guard state", e)
                false
            }
        }

        fun isEnabled(context: Context): Boolean {
            val expected = ComponentName(context, PowerGuardService::class.java)
            val enabled = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: return false
            return enabled.split(':').any {
                ComponentName.unflattenFromString(it) == expected
            }
        }
    }
}
