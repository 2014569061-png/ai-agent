# NEXUS Agent — UI / Layout / Rendering / Transcript Evidence

Scope: layout, rendering, typography, transcript presentation. Everything below is NEXUS-as-it-is-today, with `path:line` evidence. No external agent research here (separate teammate).

Repo: `D:\AIIIIII\ai-agent\mobile_agent` · v0.9.0+95 · lib/ ≈141k lines.

Presentation-layer size (files / lines):

| dir | files | lines |
|---|---|---|
| markdown | 4 | 744 |
| chat | 43 | 16750 |
| theme | 8 | 1462 |
| motion | 16 | 2674 |
| projects | 7 | 1890 |
| workspace | 6 | 1620 |
| workbench | 1 | 346 |

---

## 1. Markdown / rich text rendering

**Stack**: `flutter_markdown_plus: ^1.0.12` (`pubspec.yaml:56`) + `flutter_math_fork` for math. Custom builders for `<pre>` and math.

| Capability | Status | Evidence |
|---|---|---|
| Markdown parse/render | Implemented | `lib/presentation/markdown/math_block.dart:28` (`MarkdownBody`), `lib/presentation/chat/widgets/streaming_markdown.dart:59` (`DeferredMarkdown`) |
| Fenced code blocks | Implemented | `lib/presentation/markdown/code_block.dart:148` `class CodeBlockBuilder extends MarkdownElementBuilder`, `:166` returns `CodeBlockWidget` |
| Syntax highlighting | Partially implemented — regex highlighter, not a grammar engine | `lib/presentation/markdown/code_block.dart:18` `class SimpleSyntaxHighlighter implements SyntaxHighlighter` |
| Language detection | Implemented | `lib/presentation/markdown/code_block.dart:169-179` `_extractLanguage` reads `class="language-xxx"` via `RegExp(r'language-([\w+#.-]+)')` |
| Tables | Implemented | `lib/presentation/chat/widgets/message_bubble.dart:287-310` (tableHead/tableBody/tableBorder/tableCellsPadding), duplicated for user vs assistant at `:392-414` |
| Math `$…$` / `$$…$$` / `\(…\)` / `\[…\]` | Implemented | `lib/presentation/markdown/math_block.dart:70-72` regex; `:58` `Math.tex(...)`; fallback to monospace on error `:62-63` |
| Streaming / incomplete markdown | Implemented — genuinely streaming-aware | see below |
| Inline code | Implemented via stylesheet (`codeblockDecoration: const BoxDecoration()` at `message_bubble.dart:234`, `:339`) | |
| Links | **Absent for in-app tap handling** — no `onTapLink` anywhere in lib/ | grep for `onTapLink` → 0 matches; `url_launcher` used only in `lib/presentation/feedback/feedback_page.dart:48` and `lib/presentation/navigation/desktop_preview_panel.dart:212` |
| Citations | Implemented as a chip strip, **not** as markdown `[1]`→anchor jump | `lib/presentation/navigation/desktop_workbench_panels.dart:669` `DesktopCitationStrip`; `:680-688` `InputChip` with `onDeleted` only (delete, no jump) |

### 1.1 Syntax highlighting depth

`SimpleSyntaxHighlighter` (`code_block.dart:18`) is a **single regex scan with 5 capture groups** (`code_block.dart:107-113`):

```
(//[^\n]*|#[^\n]*)                 // line comment
|(/\*[\s\S]*?\*/)                  // block comment
|("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`)  // strings
|(\b\d+(?:\.\d+)?\b)               // numbers
|(\b[A-Za-z_][A-Za-z0-9_]*\b)      // identifiers
```

- **No per-language grammar.** One shared keyword set (`code_block.dart:31-104`, ~70 identifiers mixing Dart/JS/TS/Java/Kotlin/Python keywords: `abstract`, `async`, `await`, `class`, `const`, `func`, `function`, `late`, `mixin`, `sealed`, `typedef`, …). Dart types like `String`, `Future`, `Stream` are treated as keywords (`:91-102`).
- Consequence: JS `->`, Python `def`/`self`, Rust lifetimes, TS generics/types get no distinct coloring; a keyword-looking identifier in any language colors the same.
- No highlight library is imported: grep for `flutter_highlight|highlight` imports → 0 matches.
- Highlighting is **deferred until visible**: `code_block.dart:241-269` `_watchViewport`/`_highlightIfVisible`, `:267` `setState(() => _highlighted = true)`, `:259-266` skips if `bottom < -200 || topLeft.dy > viewportHeight + 200`.
- Long code falls back to unhighlighted: `_maxHighlightChars` gate at `code_block.dart:243`, `:297` `final longFallback = widget.code.length > _maxHighlightChars`, `:504`/`:508` plain `SelectableText`.
- Highlighted span is cached: `code_block.dart:522-524` `if (_highlightedSpan == null) ... _highlightedSpan = highlighter.format(code)`.
- Diff-aware code blocks: `code_block.dart:302-304` detects `diff` language or `@@`/`+`/`-` content and routes to `_buildDiffView` (`:437`).

### 1.2 Streaming-aware partial markdown — the strongest finding in this section

This is a real, non-trivial implementation.

- `StreamingMarkdownScanner` (`lib/presentation/markdown/markdown_render_policy.dart:29`) is a **stateful line scanner**. It tracks `_fence` / `_fenceLength` (`:35-36`) and only advances `_stableEnd` on a blank line while outside a fence:
  - fence open: `:56-60`; fence close requires same char and `fence.length >= _fenceLength` and empty suffix: `:61-65`
  - `code_block`-safe boundary: `:67-69` `if (_fence == null && _lineStart > 0 && line.trim().isEmpty) _stableEnd = newline + 1;`
  - prefix-rewrite protection: `:41-46` if `!data.startsWith(_previous)` it resets state and increments `resets`.
  - O(delta) scanning: `:48` `scannedCharacters += data.length - _offset;` then `:73` `_offset = data.length`.
- Only the delta is ever parsed to rich text: `lib/presentation/chat/widgets/streaming_markdown.dart:56-67` appends a new `RepaintBoundary(DeferredMarkdown(data: delta))` for the newly stable part; the growing tail stays **plain `Text`** (`:69`, `:76-77`).
- Coupled-content escape hatch: `streaming_markdown.dart:46-48` detects `^ {0,3}(?:\[[^\]]+\]:|[-*+] |[0-9]+[.)] |> |\$\$)` in the stable prefix and **discards and re-renders all cached stable children** (`:49-55`), because link-reference definitions and list renumbering can retroactively change earlier blocks.
- Signature invalidation covers theme + text scale: `:37-43` (textColor, tailStyle, styleSheet, `Theme.of(context)`, `MediaQuery.textScalerOf(context)`).

**Caveat / real gap**: the tail is rendered as plain `Text(segments.tail, style: widget.tailStyle)` — so during streaming, a fenced code block's content is plain text with **no syntax highlighting and no language header** until the fence closes and a blank line follows. Same for a table: it renders as raw pipe text until the paragraph terminates. This is a deliberate performance trade (comment at `markdown_render_policy.dart:21-22`), but it is visible to the user.

### 1.3 Long-content deferral

- `MarkdownRenderPolicy.shouldDefer` (`markdown_render_policy.dart:8`) defers rich parsing for long text, with width-dependent thresholds: `:11-15` → `3000` chars if viewport < 380, `5000` if ≥ 600, else `baseThreshold = 4000` (`:7`).
- While deferred, one frame renders plain text: `streaming_markdown.dart:139-150` (placeholder uses `AppTokens.fontSizeBody`, `height: 1.6`), then `addPostFrameCallback` → `setState(_ready = true)` (`:128-134`).
- Render time is measured: `streaming_markdown.dart:152-161` → `MarkdownRenderMetrics.instance.recordMarkdown(...)` (`lib/presentation/markdown/markdown_render_metrics.dart`).

---

## 2. Transcript virtualization + streaming rebuild granularity

**Verdict: implemented, and more sophisticated than a naive `ListView.builder` + full rebuild.** Rebuild granularity is explicitly 3-tiered.

### 2.1 Virtualization

- `ListView.builder` — `lib/presentation/chat/widgets/chat_message_list.dart:279`, `itemCount: totalCount` (`:282`).
- Pre-render window: `chat_message_list.dart:285` `scrollCacheExtent: const ScrollCacheExtent.pixels(400)`.
- Keep-alive off: `chat_message_list.dart:286` `addAutomaticKeepAlives: false` (comment `:283-284` explains it saves invisible-subtree cost).
- Windowed from a retained full list: `_start` offset (`:277`, `:291`), class doc `chat_message_list.dart:15` "长会话消息列表：完整消息仍由上层持有，列表只按窗口构建可见消息".

### 2.2 Streaming append — rebuild granularity

Three distinct tiers, all at `path:line`:

1. **Page does not rebuild.** High-frequency streaming text is subscribed in a *leaf* `Consumer` only: `lib/presentation/chat/chat_page.dart:1111-1116` — comment at `:1113-1114` says only this subtree rebuilds with `liveReply`. `liveReplyProvider` is defined at `lib/application/chat_controller.dart:3087`; its doc (`:3080`) states streaming refreshes `liveReply` at **≤70 ms cadence**, deliberately not the whole controller state.
2. **Historical bubbles are frozen.** `_StableHistoryBubble` (`chat_message_list.dart:404`) keeps `_child` and only swaps when a composite signature changes: `:417-438`, signature built at `:353-373` (message identity, sessionKey, index, isLast, selecting, running, runProgress, callback non-nullness, theme, textScaler). Comment `:402-403` and `:354-356`: identity covers attachments/tool args/usage without rescanning historical Markdown each frame.
3. **Only the live message re-renders richly.** `chat_message_list.dart:349-351` — `final child = liveIndex == index ? bubble : _StableHistoryBubble(...)`. For the live message a synthetic `ChatMessage` is constructed per frame from `live.text` / `live.reasoning` (`:293-307`).

Supporting mechanisms:
- Raster isolation for the streaming subtree: `chat_page.dart:1124-1127` `RepaintBoundary` before `GlassScrollEdge` → `ChatMessageList`; comment `:1125-1126` "Streaming tokens rebuild this subtree frequently. Isolate its raster work from the backdrop and glass controls."
- Height does not jump line-by-line: `chat_message_list.dart:394` `SpringFollowHeight(enabled: liveIndex == index, child: child)` (comment `:391`).
- Stable paragraph widgets are individually `RepaintBoundary`-wrapped: `streaming_markdown.dart:58`.
- First-token fade-in plays once: `NexusMotion.answerReveal` = `AppTokens.durationAnswerReveal` = 180 ms (`app_tokens.dart:169-170`), consumed by `_AnswerReveal` (`lib/presentation/chat/widgets/message_bubble.dart:979`).
- Scroll-follow coordinator reads live position only: `lib/presentation/chat/chat_scroll_coordinator.dart:154` `if ((target - controller.position.pixels).abs() < 2)`.
- Pagination preserves viewport anchor: `chat_message_list.dart:255-267` recomputes `delta = maxScrollExtent - oldExtent` then `jumpTo(oldPixels + delta)`.

**Gap**: there is no per-token diffing *inside* the live message — the whole live bubble widget subtree is rebuilt at ≤70 ms cadence. That is bounded and deliberate, but it means steady-state COGS scales with live-message size, mitigated only by `StreamingMarkdown` not re-parsing the stable prefix.

---

## 3. Message-level UI affordances

### 3.1 Per-message actions

Single entry point: long-press / right-click → action sheet or context menu, `lib/presentation/chat/chat_message_actions.dart:5`.

| Action | Value | Applies to | Evidence |
|---|---|---|---|
| Speak / stop speaking (TTS) | `speak` | assistant only, and only if `tts.isAvailable` | `chat_message_actions.dart:13`, `:23-28`; label switch `:26` |
| Edit & resend | `edit` | user only | `chat_message_actions.dart:29-35` (subtitle "替换此消息，并重新生成其后的回复") |
| New branch / fork | `fork` | all | `chat_message_actions.dart:36-41`; handler `:95-107` → `_chat.forkFromMessage(...)` `:97` |
| Quote into composer | `quote` | all | `chat_message_actions.dart:42-43`; handler `:88-90` builds `> ` blockquote |
| Regenerate | `regenerate` | assistant, only when `!snapshot.running` | `chat_message_actions.dart:44-46` |
| Copy full text | `copy` | all | `chat_message_actions.dart:47-51` |
| Select text mode | `select` | non-tool messages | `chat_message_actions.dart:52-58` |
| Share | — (exists) | assistant | `lib/presentation/chat/widgets/message_bubble.dart:781-783` `CopyFeedbackButton`; `share_plus` imported `message_bubble.dart:11` |
| Delete / pin / thumbs feedback | **Absent** | — | not present in the action list |

Rendering of the menu: desktop-style `showMenu` with `RelativeRect.fromLTRB(position.dx, position.dy, ...)` at `chat_message_actions.dart:60-77`; mobile `showNexusActionSheet` at `:78-82` with `scrollable: true`.

Per-message footer row: `message_bubble.dart:741` `class _ReplyActionRow extends StatelessWidget`; elapsed time formatting `message_bubble.dart:730-734` (`'${(elapsed.inMilliseconds / 1000).toStringAsFixed(1)}s'`); buttons at `:763`, `:781`, `:800`.

Selection-mode trade-off is documented in code: `message_bubble.dart:77-80` — `selectable` default must be `false` because `SelectableText` swallows long-press, which is the only entry to the message menu. Also `:156-158`: `MarkdownBody(selectable: true)` was measured not to produce `SelectableText` on flutter_markdown 0.7.7+1.

### 3.2 Tool-call rendering

- `lib/presentation/chat/widgets/tool_activity_section.dart:93` `NexusSurface(level: SurfaceLevel.thin, ...)` — an inline **card**, not a modal.
- Collapse policy: `tool_activity_section.dart:51` `_collapsedThreshold = 8`; `:71` `_collapsible => widget.activities.length > _collapsedThreshold`; default expanded state `:88-92` (`_expandedOverride ?? (!collapsible || widget.running)`).
- Expanded body is height-capped and internally scrollable: `:54` `_expandedMaxHeight = 280`; `:107-119` `ConstrainedBox(maxHeight: 280)` + `SingleChildScrollView` + `Column` (**not** a builder — all activities are built when expanded).
- Compact mode: `:59` `_compactVisibleCount = 3`; `:75-83` `_compactRows` shows last 3 plus any row with `status == '等待确认'`; overflow affordance at `:139-152` ("查看全部 N 条", `ValueKey('tool-activity-show-all')`).
- Full list sheet: `:157-191` `_showAllSheet`, snapshot-on-open (`:160`, comment `:159` — "抽屉是独立路由，不随 Dock 实时刷新").
- "Terminal" style detail panel: `:430-443` a `Container` with `AppPalette.terminalBg/terminalSurface` + `terminalBorder`; header text literal `'[Terminal Execution: ${a.call.name}]'` at `:448`.
- Args + name shown: `:457-464` `'工具: ${a.call.name}\n参数: $args'`.
- Result shown, **truncated by line count, not by bytes**: `:465-480` `maxLines: 8` + `TextOverflow.ellipsis`. Note `if (!a.compressed && ...)` gate at `:465`.
- Compressed results expose the original, also truncated: `:481-506` — labeled `'原始结果'` (`:486`), `maxLines: 12` (`:497`).
- Status line: `:529-537` `'Status: ${running ? "Running" : (done ? "Success" : (failed ? "Failed" : "Pending"))}'`.
- **stdout / stderr are not rendered separately**; **exit code is not surfaced as a field**; **tool output is not live-streamed** (whole `a.result` string, ellipsized). Effect uncertainty is surfaced as `ToolEffect.unknown` with text `'结果无法确认，请先检查目标状态再重试。'` (`:422-429`).
- Desktop equivalent uses `ExpansionTile` per activity: `lib/presentation/navigation/desktop_workbench_panels.dart:637-651`, keys `ValueKey('desktop-execution-${activity.call.id}')` (`:650`).

### 3.3 Reasoning / thinking display

- `lib/presentation/chat/widgets/reasoning_block.dart:22` `class ReasoningCompactBlock extends StatefulWidget` — a dedicated collapsible thinking card.
- Card chrome: `:198-208` — margin 6/6 (or 3/10 when condensed, `:200-203`), background `Colors.white.withValues(alpha: 0.05)` dark / `Colors.black.withValues(alpha: 0.035)` light (`:186-188`), **no border** (comment `:206` "去描边只留浅底"), radius `_cardRadius`.
- Whole row is the toggle: `:215-218` `InkWell(onTap: hasReasoning ? _toggleReasoning : null)`, comment `:216` "整行可点展开/收起思考过程，不再单独放「思考过程」按钮".
- Accessibility: `:213-214` `Semantics(label: '处理进度：$_label')`.
- Live state indicator: `:234-243` pulsing 6×6 dot while `thinking`; progress tag literal `'进度'` at `:244-260`.
- Shimmer while thinking, **stops if stalled**: `:263-264` `ShimmerText(enabled: thinking && !_isStalled, ...)` (comment `:262` "响应变慢时停止，避免「假装在忙」").
- Responsive compaction: `:224` `final compact = constraints.maxWidth < 320;`.
- Reasoning content comes from the live stream: `chat_message_list.dart:304` `reasoning: live.reasoning`.

---

## 4. Diff rendering

Multiple independent diff renderers exist. **All are unified (single-column). No side-by-side viewer and no intra-line word-level highlighting anywhere** — grep for `sideBySide`/`intraLine`/`wordLevel` → 0 matches.

| Renderer | Style | Highlighting | Evidence |
|---|---|---|---|
| Desktop review panel | Unified, line-numbered, hunk-collapsible | `SimpleSyntaxHighlighter` per line | `lib/presentation/navigation/desktop_review_panel.dart:318` `class DesktopDiffView`; `:374` `ListView.builder`; `:451-453` `SimpleSyntaxHighlighter().format(line.text)` |
| Desktop changes panel | Unified, plain colored text | none | `lib/presentation/navigation/desktop_workbench_panels.dart:582` `class _DesktopDiff`; `:598-612` `SelectableText.rich` with color-only spans |
| Markdown code block (diff fence) | Unified, 1-based line numbers | none inside diff | `lib/presentation/markdown/code_block.dart:437` `_buildDiffView`; `:446-462` add/remove/header classification |
| Task details | Unified | none | `lib/presentation/tasks/task_details_page.dart:1477` `class _CodeDiffCard extends StatelessWidget` |
| Tool-approval sheet | Unified | none | `lib/presentation/chat/widgets/tool_approval_sheet.dart:529`, `:594-600` |

Details on the most complete one (`DesktopDiffView`):
- Model: `lib/application/desktop_diff.dart:1` `DesktopDiffLine`, `:9` `DesktopDiffHunk`, `:15` `DesktopDiff`; parse at `:24`, hunk handling `:49-56`.
- Line rows: dual gutters, 38 px each — `desktop_review_panel.dart:436-449` (`'${line.oldLine ?? ''}'` and `'' ${line.newLine ?? ''}`), monospace size 12.
- Row tinting by first char: `:425-430` `+` → `added.withValues(alpha: .09)`, `-` → `removed.withValues(alpha: .09)`.
- Per-line text color: `:457-461` added / removed / default.
- Hunk header row with collapse toggle: `:386-422` — `_collapsed` `Set<int>` (`:337`), `setState` at `:393-397`, caret icon `:398-402`.
- Hunk-level actions (Git-style staging): **implemented** — 暂存此块 / 取消暂存此块 (`:407-414`) and 恢复此块 (`:415-421`), wired to `onStageHunk` / `onRevertHunk` (`:322-323`).
- Whole-diff is virtualized (`ListView.builder` `:374`) and selectable (`SelectionArea` `:373`).
- Truncation: `desktop_workbench_panels.dart:592` `file.diff.length > 65536 ? file.diff.substring(0, 65536) : file.diff` with a notice at `:596-597`.
- Palette: `lib/presentation/theme/app_palette.dart:68-69` `diffAddedBg = Color(0x1F10B981)`, `diffAddedText = Color(0xFF34D399)` (+ `diffRemovedBg`/`diffRemovedText`).
- Backing diff engine: `lib/infrastructure/observability/unified_diff.dart:5-6` `class UnifiedDiffResult` — "A line-oriented unified diff with accurate hunk ranges and change counts", builder at `:59`, applier at `:96`.

**Missing**: intra-line/word-level change emphasis; side-by-side mode; whitespace-change toggle; syntax highlighting in 4 of the 5 diff surfaces.

---

## 5. Typography + theming system

### 5.1 Type scale — dual-track and partially bypassed

- Token scale exists: `lib/presentation/theme/app_tokens.dart:37-54`, 17 named sizes labeled "双轨制：Display 轨 + Content 轨":
  `fontSizeDisplay1=34, Display2=28, Headline=22, Title=17, Heading=18, Section=19, Metric=20, BodyLarge=16, Body=15, Subhead=14, BodySmall=13.5, Caption=13, Meta=12.5, Footnote=12, Subcaption=11.5, Badge=11, MetricSmall=10.5`.
- Material `TextTheme` is fully populated: `lib/presentation/theme/app_theme.dart:90` `_baseTextTheme(...)`, mapping `displayLarge…labelSmall` at `:99-228`.
- Desktop has its **own independent** type scale, not the tokens: `lib/presentation/theme/desktop_theme.dart:212-228` `TextTheme(displayLarge: style(24, ...), …, labelSmall: style(10, muted: true))`.

**KEY COUNT — ad-hoc numeric `fontSize:` literals vs named tokens (whole `lib/`):**

| Metric | Count |
|---|---|
| Raw numeric `fontSize: <number>` | **224** occurrences across **66** files |
| Named `fontSize: AppTokens.<name>` | **327** occurrences across 34 files |
| Raw fontSize inside `lib/presentation/` | 223 (i.e. only **1** raw numeric fontSize outside presentation) |
| `fontSize` in the theme files themselves | 21 (`app_theme.dart`) |

Distinct raw numeric values and their frequency:

| value | count | | value | count |
|---|---|---|---|---|
| 12 | 51 | | 15.5 | 1 |
| 13 | 49 | | 14.5 | 2 |
| 11 | 37 | | 13.5 | 2 |
| 15 | 29 | | 12.5 | 6 |
| 14 | 12 | | 11.5 | 3 |
| 10.5 | 7 | | 16.5 | 1 |
| 10 | 6 | | 9 | 1 |
| 17 | 9 | | 16 | 4 |
| 18 | 2 | | 22 | 2 |

Interpretation: the app is **mid-migration**, not ad-hoc. ~59% of fontSize uses are tokenized, but 224 literals remain, and several literals (16.5, 15.5, 14.5, 12.5, 13.5) do **not exist in the token scale at all** — those are genuinely outside the design system. Note `app_theme.dart` alone holds 21 literals (e.g. `:129`, `:137` both `fontSize: 22`, `:146/:154/:162` all `17`), i.e. the type scale's own definition is partly hardcoded rather than token-derived.

Top offenders by raw fontSize count: `app_theme.dart` 21, `chat/widgets/capsule_top_bar.dart` 9, `tasks/development_tasks_page.dart` 8, `diagnostics/run_analysis_page.dart` 8, `dashboard/widgets/token_trend_card.dart` 8, `settings/appearance_theme_page.dart` 7.

### 5.2 Design-token layer

Exists and is substantive (spacing, radius, size, duration, curve, breakpoints):
- Spacing 4px grid: `app_tokens.dart:6-14` (`sp1..sp16` = 4/8/12/16/24/32/48/64), with `@Deprecated` aliases `:17-26`.
- Radius: `:29-35` (`radiusControl=8`, `radiusCard=12`, `radiusModal=16`, `radiusPill=999`, `radiusComposer=20`); deprecated aliases `:74-87`.
- Heights: `:90-95` (`kTopBarHeight=56`, `kListRowHeight=52`, `kControlHeight=44`, `kMinTouchTarget=48`, `kChipHeight=32`, `kSearchBoxHeight=36`).
- Shadows: `:66-67`. Breakpoints: `:60-63`.
- **No `Color` token layer in `AppTokens`** — colors live in `lib/presentation/theme/app_palette.dart`, separate from geometry tokens.

### 5.3 Monospace font

- Canonical mobile token: `app_tokens.dart:57` `static const fontFamilyMono = 'monospace';` — comment `:56` says it exists to eliminate bare `'monospace'` and unshipped `'JetBrains Mono'`.
- Desktop has a **different, hardcoded** monospace stack: `desktop_theme.dart:61-83` `monospaceStyle(...)` with `fontFamily: 'Consolas'` (`:70`) and fallbacks `Menlo, Monaco, Courier New, Microsoft YaHei, monospace` (`:71-77`).
- **Token discipline is not holding**: 51 literal `fontFamily: 'monospace'` occurrences still exist despite the token; e.g. `tool_activity_section.dart:450`, `:460`, `:474`, `:488`, `:500`, `:532`; `code_block.dart:475`, `:487`; `math_block.dart:63`. Plus 17 `fontFamily: 'Inter'` and 4 `fontFamily: 'Consolas'` literals.
- No bundled/JetBrains Mono asset — the code font is whatever the platform maps `'monospace'` to (comment `app_tokens.dart:56`).

### 5.4 Dark / light

- Mobile: `lib/presentation/theme/app_theme.dart:230-231` `static ThemeData light() => _build(Brightness.light);` / `dark()`; single `_build` at `:233` with `final isDark = brightness == Brightness.dark;` (`:234`), base from `ThemeData.dark()/light()` (`:267`).
- Palettes are literal constant pairs, e.g. `lib/presentation/theme/app_palette.dart:68-69`; branch pattern `isDark ? AppPalette.darkX : AppPalette.lightX` appears throughout (e.g. `reasoning_block.dart:184-191`, `code_block.dart:288-295`).
- Desktop: constant pairs `desktop_theme.dart:85-95` (`light`), `:96-106` (`dark`), `:108+` (`highContrastLight`); applied via `DesktopTheme.apply(Theme.of(context), highContrast: MediaQuery.highContrastOf(context))` (`app_shell.dart:701-702`).
- Controller: `lib/presentation/theme/app_theme_controller.dart`; appearance prefs screen `lib/presentation/settings/appearance_theme_page.dart`.
- **Dark/light is not a token indirection** — it is per-call-site ternary selection over two constant palettes, so adding a theme means touching every call site.

### 5.5 Responsive / adaptive layout

**Partially implemented — two competing, inconsistent breakpoint systems.**

System A — named tokens (`app_tokens.dart:60-63`): `bpCompact = 320`, `bpMedium = 420`, `bpWide = 700`, `kContentMaxWidth = 700`. But grep shows `bpWide`/`bpMedium`/`bpCompact` are **never used at a call site** — only 2 hits outside the definition (`chat_page.dart:1011` `constraints.maxWidth > 700`, `chat/widgets/capsule_top_bar.dart:121` `> 550`, `:158` `> 500`), i.e. the tokens are declared and then ignored in favor of magic numbers.

System B — magic literals scattered across the app:

| Value | Site | Evidence |
|---|---|---|
| **900** | desktop-shell threshold | `lib/presentation/navigation/app_shell.dart:100` `static const minWidth = 900.0;` (named), consumed `:699` `if (constraints.maxWidth < DesktopShell.minWidth) return _pageFor(_index);` |
| 1280 | preferred desktop width (declared) | `app_shell.dart:101` `static const preferredWidth = 1280.0;` |
| 640 | desktop min height | `app_shell.dart:102` `static const minHeight = 640.0;` |
| 1200 | inline side pane enabled | `app_shell.dart:705` `final inlineSide = _sideOpen && constraints.maxWidth >= 1200;` |
| 1040 | navigator visible | `app_shell.dart:712` `final navigatorVisible = constraints.maxWidth >= 1040 \|\| MediaQuery.textScalerOf(context).scale(12) <= 18;` |
| 900 | desktop-detection in chat | `lib/presentation/chat/chat_page.dart:153` `MediaQuery.sizeOf(context).width >= 900;` |
| 700 | bubble width branch | `chat_page.dart:1011` `final wide = constraints.maxWidth > 700;` |
| 800 | settings 2-pane | `lib/presentation/settings/settings_page.dart:345` `MediaQuery.sizeOf(context).width >= 800` |
| 360 | settings compact | `settings_page.dart:806` `MediaQuery.sizeOf(context).width <= 360` |
| 320 | reasoning compaction | `chat/widgets/reasoning_block.dart:224` `constraints.maxWidth < 320` |
| 310 | text-scale fallback | `settings/appearance_theme_page.dart:147` `if (textScale > 1.15 \|\| constraints.maxWidth < 310)` |
| 280 | metrics summary | `chat/widgets/session_metrics_summary.dart:90` `constraints.maxWidth < 280` |
| 1200 | app-shell side rail | `app_shell.dart:345` `if (MediaQuery.sizeOf(context).width >= 1200) return;` |

Notably `app_shell.dart:345`, `:705` and `:712` use **1200/1040**, while `app_tokens.dart:62` declares `bpWide = 700`; there is no token for the 900/1040/1200 tier. The desktop layout is a distinct widget tree (`DesktopShell`, `app_shell.dart:97`) selected by one `LayoutBuilder` gate at `:699`, so phone and ≥900px desktop are genuinely different surfaces — but the intermediate band and the padding/clamp constants are magic (`app_shell.dart:706-711`: `sideWidth.clamp(340.0, max(340.0, maxWidth - 700.0))`, `terminalHeight.clamp(160.0, maxHeight*.34)`).

There is **no** dedicated 1280×800 preset or test breakpoint; `preferredWidth = 1280.0` (`app_shell.dart:101`) is declared but is not read at any layout decision site found by grep.

---

## 6. Layout persistence

**Verdict: PARTIAL. Split ratios + pane visibility persist, but they are GLOBAL device preferences, not per-session surface state. Scroll position and expanded-section state do not persist at all.**

| State | Persisted? | Scope | Evidence |
|---|---|---|---|
| Desktop side width / terminal height / side open / terminal open / side tab | Yes | **Global** (single key set, device-wide) | `lib/application/desktop_workbench_service.dart:107` `class DesktopLayoutSettings`; `:122` `load()`, `:131-138` reads `desktop.side.width`, `desktop.terminal.height`, `desktop.side.open`, `desktop.terminal.open`, `desktop.side.tab`; `:141-149` `save()` (also `desktop.layout.version = 2`) |
| Layout versioning / migration | Yes | Global | `desktop_workbench_service.dart:126-130` — if `desktop.layout.version != 2` it resets to defaults once |
| Layout restored into shell | Yes | Global | `app_shell.dart:171-185` `_loadLayout()`, `:187-199` `_saveLayout()` with `_layoutEdited` race guard at `:114`/`:174`/`:188` |
| Bubble max-width factor | Yes | **Global**, not per-conversation | `lib/presentation/chat/chat_layout_controller.dart:10-15` `widthFactor` + `chat.bubble_width` key; `:18-23` `setWidthFactor`; clamped `.45–.95` (`:7-8`, `:32`) |
| Composer draft text + attachments + references | Yes | **Per conversation or per project** — this is the one genuinely per-session-ish surface state | `lib/application/draft_service.dart:69-77` `keyFor()` → `'conversation:$id'` / `'project:$id'` / `'global'`; `:79-94` `load`, `:113-132` `save` (writes `body`, `attachmentsJson`, `referencesJson`, `updatedAt`); stall detection `:96-111` (missing files become `status: 'missing'`) |
| Preview panel URL | Yes | **Per workspace root** | `lib/presentation/navigation/desktop_preview_panel.dart:98` `preferences.getString('desktop.preview.url.$root')`; `:120-122` `setString('desktop.preview.url.$root', '$url')` |
| **Chat scroll position** | **Absent** | — | grep for `scroll_offset|scrollOffset|saveScroll|restoreScroll|_lastScroll` in lib/ → **0 matches**. `chat_scroll_coordinator.dart:154` only reads live pixels |
| **Expanded/collapsed section state** | **Absent** | — | `_collapsed` in `DesktopDiffView` is in-memory and **cleared on every content change**: `desktop_review_panel.dart:337` `final Set<int> _collapsed = {};`, `:349` `_collapsed.clear();` |
| Tool activity expansion | **Absent** (in-memory, reset per run) | — | `tool_activity_section.dart:63` `bool? _expandedOverride;`, `:68` `if (widget.running && !oldWidget.running) _expandedOverride = null;` |
| Reasoning block expansion | **Absent** (in-memory) | — | `reasoning_block.dart` `_toggleReasoning` |
| Selected activity-rail index | **Absent** | — | `app_shell.dart:114` `int _index` state only |

Consequence for the comparison: NEXUS has **no "per-session surface state" concept**. Restarting the app restores the desktop split and the composer draft, but a conversation reopens at scroll position 0 (or the anchor computed by `chat_message_list.dart:255-267` for pagination only), with every thinking block, hunk collapse and tool-card expansion reset.

---

## 7. Animation / motion system

**Verdict: implemented and genuinely centralized.** This is the most disciplined subsystem in the audit.

- Single source of truth: `lib/presentation/motion/nexus_motion.dart:7` `abstract final class NexusMotion` — every duration re-exports an `AppTokens` constant rather than declaring its own (`:10`, `:13`, `:16`, `:19`, `:22`, `:25`, `:28-30`, `:33-35`, `:38-40`, `:43`, `:46-48`, `:51-52`, `:55-57`).
- Duration tokens are named and semantically layered, not one global duration: `lib/presentation/theme/app_tokens.dart:99-123` defines 24 dedicated ms constants (`_durationInstantMs = 100`, `_durationPageMs = 250`, `_durationSheetMs = 300`, `_durationEntranceMs = 260`, `_listStaggerMs = 30`, `_entranceStaggerMs = 40`, `_shimmerSweepMs = 1600`, `_ambientGlowPeriodMs = 12000`, …), each with a rationale comment citing the HarmonyOS motion guidance band (150 ms short / 200–250 ms local layout / ≤350 ms full-screen) at `:99-101`.
- Curves centralized: `app_tokens.dart:198-200` `curveStandard = Cubic(0.4, 0.0, 0.2, 1.0)`, `curveDecelerate = Cubic(0,0,0.2,1)`, `curveAccelerate = Cubic(0,0,0,1)`; plus `NexusMotion.curveSheetEnter = Cubic(0.16, 1.0, 0.3, 1.0)` (`nexus_motion.dart:102`) and `curveResponsive = Cubic(0.2, 0.0, 0.2, 1.0)` (`:105`).
- Spring physics rather than fixed curves where interruption matters: `nexus_motion.dart:119-128` — `springFollow (stiffness 1754.6, damping 72.05)`, `springRelease (130.5, 18.85)`, `springLively (128, 12)`; formula recorded at `:114`. `spring(...)` builder at `:131-143`.
- `NexusSpringCurve` (`nexus_motion.dart:223-256`) converts a spring into a fixed-duration `Curve` by numerically finding settle time to ±0.5% tolerance (`:247-255`), with overshoot clamping for properties that must not exceed range (`:244`).
- Reduced-motion is threaded through every helper: `nexus_motion.dart:146-159` `durationInstant/Fast/Base/Expand/Exit(BuildContext)` → `MotionPreferences.adjustDuration`; `:169-171`, `:184-186`, `:206-208` short-circuit the transition wrappers entirely. Desktop equivalent: `desktop_theme.dart:58-59` `motionDuration(...) => reduceMotion(context) ? Duration.zero : duration`.
- Generic builders: `fadeTransition` (`:163`), `slideFadeTransition` (`:177`, default `Offset(0, 0.05)`), `sizeTransition` (`:199`).
- Scroll physics is tokenized with a deliberate exception: `nexus_motion.dart:70-71` `listPhysics = BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics())`, comment `:69` — non-chat lists bounce, chat keeps platform default.
- Diagnostics surface exists: `lib/presentation/settings/motion_diagnostics.dart:14` `class MotionDiagnosticsCard`.
- 16 files / 2674 lines under `lib/presentation/motion/` implement the system (springs, entrance, stagger, press squash, morph icon, send flight, spring-follow height, page route factory).
- Minor leak: two durations are **not** in `AppTokens` — `nexus_motion.dart:80` `scrollToTarget = Duration(milliseconds: 260)` and `:83` `tailFollow = Duration(milliseconds: 180)`, declared inline in the motion class.

---

## 真实短板（UI/排版向）

Ranked by user impact. Each with `path:line`.

1. **链接完全不可点。** Markdown 正文里的 URL / `[text](url)` 没有任何点击处理：全仓库 `onTapLink` 命中 0 次；`url_launcher` 只在 `lib/presentation/feedback/feedback_page.dart:48` 和 `lib/presentation/navigation/desktop_preview_panel.dart:212` 使用。编码智能体回复里链接是刚需（PR、issue、文档、日志地址），用户只能手动复制。证据：`lib/presentation/chat/widgets/message_bubble.dart:220` 调用 `StreamingMarkdown`，其 styleSheet（`:224-330`）未设 link 回调。

2. **流式期间代码块 / 表格降级为纯文本，无高亮无语言头。** `lib/presentation/markdown/markdown_render_policy.dart:67-69` 只在「围栏外 + 空行」推进 `_stableEnd`，因此正在写入的代码块整体停留在 tail；`lib/presentation/chat/widgets/streaming_markdown.dart:69` 与 `:76-77` 把 tail 直接渲染为 `Text(segments.tail, style: widget.tailStyle)`。长时间代码生成的观感是「先掉一段灰字，闭合后才变彩色」，且表格在段落结束前是原始竖线文本。这是有意的性能取舍（`markdown_render_policy.dart:21-22` 注释），但代价落在用户最盯着的区域。

3. **没有 per-session surface state：滚动位置、折叠状态全部不恢复。** grep `scroll_offset|scrollOffset|saveScroll|restoreScroll` 在 lib/ 下 0 命中；`lib/presentation/navigation/desktop_review_panel.dart:337` `final Set<int> _collapsed = {};` 且 `:349` `_collapsed.clear();` 每次 diff 变化即清空；`lib/presentation/chat/widgets/tool_activity_section.dart:63`/`:68` 的展开状态每轮运行重置。持久化的只有设备级分栏（`lib/application/desktop_workbench_service.dart:131-138` 的 `desktop.side.width` 等固定键）与每会话草稿（`lib/application/draft_service.dart:69-77`）。切换会话回来，阅读位置与展开上下文全部丢失——长会话里这是每天都在付的成本。

4. **316 个字号决定里 224 个是裸数字，且 5 个字号不在设计系统内。** 实测：`fontSize: <数字>` 224 处 / 66 文件 vs `fontSize: AppTokens.*` 327 处 / 34 文件；其中 `16.5 / 15.5 / 14.5 / 13.5 / 12.5` 在 `lib/presentation/theme/app_tokens.dart:37-54` 的字号阶中**不存在**。连类型阶自身的定义文件都在硬编码：`lib/presentation/theme/app_theme.dart` 占 21 处裸数字（`:129`、`:137` 同为 22；`:146`、`:154`、`:162` 同为 17）。桌面端还另起一套独立字号（`lib/presentation/theme/desktop_theme.dart:212-228` 用 `style(24/22/20/…)`），与移动 token 阶不对齐。后果：全局调字号或做一致性审计必须改 66 个文件。

5. **断点体系存在但没有被使用：token 声明了却全用魔法数字。** `lib/presentation/theme/app_tokens.dart:60-62` 声明 `bpCompact=320 / bpMedium=420 / bpWide=700`，但三个 token 在任何调用点都没有被引用；实际布局用的是散落的 900 / 1040 / 1200 / 800 / 700 / 550 / 500 / 360 / 320 / 310 / 280：`lib/presentation/navigation/app_shell.dart:705`（1200）、`:712`（1040）、`lib/presentation/chat/chat_page.dart:153`（900）、`:1011`（700）、`lib/presentation/settings/settings_page.dart:345`（800）。`app_shell.dart:101` 的 `preferredWidth = 1280.0` 声明后没有任何读取点。手机/桌面是两棵真正不同的树（`app_shell.dart:699` 单一闸门），但中间带宽与内边距全靠 clamp 魔法数（`:706-711`）。

6. **Diff 只有统一视图，无逐词 intra-line 高亮，且 5 个 diff 渲染面里有 4 个不做语法高亮。** grep `sideBySide|intraLine|wordLevel` 在 lib/ 下 0 命中。高亮仅存在于 `lib/presentation/navigation/desktop_review_panel.dart:451-453`（`SimpleSyntaxHighlighter().format(line.text)`）；`lib/presentation/navigation/desktop_workbench_panels.dart:598-612`、`lib/presentation/markdown/code_block.dart:437-489`、`lib/presentation/tasks/task_details_page.dart:1477`、`lib/presentation/chat/widgets/tool_approval_sheet.dart:529` 均只做整行着色。改一行中变一个标识符时，用户必须逐字比对。另外 `desktop_workbench_panels.dart:592` 在 65536 字符处静默截断。

7. **语法高亮是单套正则关键词表，没有语言区分。** `lib/presentation/markdown/code_block.dart:18` 的 `SimpleSyntaxHighlighter` 用 5 组正则（`:107-113`）+ 一张跨语言关键词表（`:31-104`，约 70 个词把 Dart/JS/TS/Java/Kotlin/Python 混在一起，`String/Future/Stream/List/Map` 被当作关键字）。无高亮库依赖（grep `flutter_highlight|highlight` import 0 命中）。Python 的 `def/self`、Rust 生命周期、TS 泛型都不会被着色；超过 `_maxHighlightChars`（`:243`、`:297`）直接退回纯文本。

8. **工具调用的输出呈现粗粒度：stdout/stderr 不分离、无退出码、不流式、按行截断。** `lib/presentation/chat/widgets/tool_activity_section.dart:465-480` 只用 `maxLines: 8` + `TextOverflow.ellipsis` 显示 `a.result!`；`lib/presentation/chat/widgets/tool_activity_section.dart:481-506` 原始结果 `maxLines: 12`；状态只有 `Success/Failed/Pending/Running` 字符串（`:529-537`）。展开态用 `Column` 一次性构建全部条目而非 builder，高度上限 280（`:54`、`:107-119`）。

9. **深色/浅色是调用点三元选择，不是 token 间接层。** `lib/presentation/theme/app_palette.dart` 提供常量对，但每个使用点都要写 `isDark ? AppPalette.darkX : AppPalette.lightX`：`lib/presentation/chat/widgets/reasoning_block.dart:184-191`、`lib/presentation/markdown/code_block.dart:288-295`、`lib/presentation/chat/widgets/tool_activity_section.dart:512-526`（五层嵌套三元）等。新增主题（如高对比）意味着遍历全部调用点；桌面侧靠 `lib/presentation/navigation/app_shell.dart:701-702` 包一层 `DesktopTheme.apply` 缓解，仅覆盖桌面树。

10. **等宽字体纪律破了：token 存在但仍有 51 处裸写。** `lib/presentation/theme/app_tokens.dart:57` 定义 `fontFamilyMono = 'monospace'`，但裸 `fontFamily: 'monospace'` 仍有 51 处（`lib/presentation/chat/widgets/tool_activity_section.dart:450,460,474,488,500,532`、`lib/presentation/markdown/code_block.dart:475,487`、`lib/presentation/markdown/math_block.dart:63` 等）。桌面端另用硬编码 `Consolas`（`lib/presentation/theme/desktop_theme.dart:70`，4 处裸写）。且没有打包任何等宽字体资产，代码字体完全取决于平台 `'monospace'` 映射，跨平台度量不一致。

11. **思考块的 tail 与正文一样退化，且无「已折叠多少内容」的提示。** `lib/presentation/chat/widgets/reasoning_block.dart:263-264` 的 `ShimmerText(enabled: thinking && !_isStalled)` 会在响应变慢时静默停止流光，用户无从判断是「卡住」还是「慢」；折叠态只显示 `_label`（`reasoning_block.dart:266-268`，`maxLines: 1`），不显示 token 数或时长。

12. **动效系统基本干净，仅 2 处漏出 token。** `lib/presentation/motion/nexus_motion.dart:80` `scrollToTarget = Duration(milliseconds: 260)`、`:83` `tailFollow = Duration(milliseconds: 180)` 未走 `AppTokens`，是该子系统唯一的例外（其余全部为 `AppTokens.*` 再导出，见 `:10-57`）。
