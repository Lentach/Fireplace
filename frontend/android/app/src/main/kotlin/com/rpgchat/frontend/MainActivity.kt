package com.fireplace.app

import android.content.pm.ApplicationInfo
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Screen security (Signal parity): FLAG_SECURE blocks screenshots,
        // screen recording, and — critically — the recents-screen thumbnail,
        // which otherwise persists decrypted chat content in the system's
        // snapshot cache outside our sealed store.
        // Gated on debuggable, NOT BuildConfig (buildConfig generation is off
        // by default under AGP 8): debug builds keep screenshots for emulator
        // work; every shippable build (release/profile) is protected.
        val debuggable = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (!debuggable) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
}
