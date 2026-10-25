package com.nexusagent.app

import android.app.Activity
import android.os.Bundle
import android.text.InputType
import android.view.WindowManager
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView

/** Literal, account-free source for real Android assist-data checks. Debug only. */
class AssistantContextFixtureActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent.getBooleanExtra("secure", false)) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        setContentView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 64, 32, 32)
            addView(TextView(this@AssistantContextFixtureActivity).apply {
                text = "nexus_context_fixture_public\n明天2026年10月20日，编号123。"
                textSize = 20f
            })
            addView(EditText(this@AssistantContextFixtureActivity).apply {
                inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
                setText("NEXUS_PASSWORD_MUST_NOT_BE_CAPTURED")
            })
            // TextView trims a single very long paragraph before Assist gets
            // it. Many small, rendered literal nodes exercise our own cap.
            if (intent.getBooleanExtra("large", false)) repeat(75) {
                addView(TextView(this@AssistantContextFixtureActivity).apply {
                    text = "可读取的测试文字".repeat(30)
                    textSize = 1f
                })
            }
        })
    }
}
