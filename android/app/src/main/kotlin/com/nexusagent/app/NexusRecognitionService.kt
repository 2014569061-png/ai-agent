package com.nexusagent.app

import android.content.Intent
import android.speech.RecognitionService
import android.speech.SpeechRecognizer

/**
 * Metadata compatibility endpoint for Android's assistant selection. It is NOT
 * an external ASR engine. Audio is captured only by the explicit foreground
 * SpeechCaptureSheet/ForegroundSpeechBridge consent flow. Never delegate to the
 * system default recognizer here: it may point straight back to this service.
 */
class NexusRecognitionService : RecognitionService() {
    override fun onStartListening(recognizerIntent: Intent?, listener: Callback) {
        listener.error(SpeechRecognizer.ERROR_CLIENT)
    }
    override fun onStopListening(listener: Callback) {}
    override fun onCancel(listener: Callback) {}
}
