package com.nexusagent.app

import android.service.voice.VoiceInteractionService
import android.service.voice.VoiceInteractionSession

/** Android owns this service's lifecycle. It does not start audio or an executor. */
class NexusVoiceInteractionService : VoiceInteractionService() {
    companion object {
        @Volatile var readyService: NexusVoiceInteractionService? = null
            private set
    }

    override fun onReady() {
        super.onReady()
        // Only an explicit session button may temporarily request page text.
        // Choosing an assistant role never requests a structure or screenshot.
        setDisabledShowContext(VoiceInteractionSession.SHOW_WITH_ASSIST or VoiceInteractionSession.SHOW_WITH_SCREENSHOT)
        readyService = this
    }

    override fun onShutdown() {
        AssistantContextHandoff.clear()
        if (readyService === this) readyService = null
        super.onShutdown()
    }

    override fun onDestroy() {
        AssistantContextHandoff.clear()
        if (readyService === this) readyService = null
        super.onDestroy()
    }
}
