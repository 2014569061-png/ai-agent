# Phase 4 — Android accessibility observation (2026-10-20)

## Delivered vertical slice

- Added an Android `AccessibilityService`, registered behind Android's normal
  user-controlled Accessibility settings. The app never enables it
  programmatically.
- Added a control in the in-app browser page to open system settings or start /
  stop an observation session for that page's conversation.
- The agent capability is registered only on Android and only while that same
  conversation owns an active session.
- Each read is a **dangerous, sensitive, read-only tool call** and prompts for
  fresh approval. Approval is bound to the current short-lived session and a
  one-time ticket.
- The native service reads the active window on demand. Accessibility events
  only increment an in-memory revision; event text/source is not collected,
  cached, or logged.
- The first version is deliberately limited to the NEXUS app's own foreground
  window. It skips editable/password subtrees and returns at most 120 labels,
  3,000 visited nodes, and 12,000 characters. It does not return coordinates,
  screenshots, editable values, or perform taps, typing, or scrolling.
- The session expires after five minutes, is bound to a conversation, and is
  revoked on app pause, owner change, route disposal, or explicit stop. It is
  never restored automatically.
- Tool arguments and results are covered by `SensitiveToolPolicy` so screen
  text is redacted from persisted history, exports, and diagnostics.

## Explicit limitations / next design gate

This first slice is **not** cross-app automation: it only observes NEXUS's own
foreground window. Extending it to third-party apps would require a separate
foreground-user-consent and approval-delivery design; do not broaden the
service's event scope or add accessibility actions as an incidental follow-up.
The next step should first test the opt-in/expiry/background-revocation flow on
Android, then review a separate design for one-shot cross-app observation.

## Verification

| Check | Result |
| --- | --- |
| `flutter analyze --no-pub` | No issues found |
| Accessibility tool, registry, persistence policy, and BrowserPage tests | 25 passed |
| Android debug build | Succeeded; service appears in the merged debug package manifest |
| Emulator UI | Browser page shows the opt-in state; Android Accessibility settings list the service and its disclosure |
| Permission state | Left disabled; a real native observation was not run because granting Accessibility permission was not part of this task |

The UI screenshot and hierarchy are in
`local/temp/eta-browser-20261020/a11y-browser-page.png` and
`local/temp/eta-browser-20261020/a11y-ui-hierarchy.xml`.
