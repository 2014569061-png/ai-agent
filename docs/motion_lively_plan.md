# 灵动动效大改（L 系列）— 方案 v1

> Baseline: `feat/harmony-motion` @ b51a48b. The 40 uncommitted files are in `stash@{0}` ("WIP before lively-motion redesign").
> Direction (user decisions 2026-09-28): **morph continuity + spring physics** as the main axis, with micro-interactions as accents. Decorative light effects stay but are toned down (default intensity 轻盈). Global scope, rolled out in phases.

## Diagnosis: why it doesn't feel lively
| Symptom | Evidence |
|---|---|
| Fixed durations + easing curves dominate | `curveStandard` ×26, `fast` ×22, `durationFast` ×15; springs used in only ~5 places |
| No velocity carry-over | A new animation that interrupts an old one restarts from 0; after a drag release the fling speed is lost |
| No spatial continuity | Sheets / dialogs / menus rise or fade out of nowhere; cards → pages are plain full-screen pushes (`Hero` in only 2 places) |
| Shape doesn't change | Input capsule, send ↔ stop, and tool-card expansion are cross-fades / jumps, with no continuous width, height or radius change |
| Energy is in the light, not the motion | Glow, particles and shimmer carry the "dynamic" feel, but the elements themselves hardly move |

## Design principles
1. **Everything interactive is a spring:** duration comes from the physics. Animations can be interrupted and keep their velocity; after a drag, the release velocity feeds the spring.
2. **Three spring grades** (token v2):
   - `snappy`: press / toggle, about 0.25s, ratio 0.85
   - `bouncy`: pops in / bounces back, about 0.4s, ratio 0.65, slight overshoot
   - `smooth`: morph / page / sheet, about 0.5s, ratio 0.9
   - plus the existing `follow` (tracks the finger)
3. **Morph over cross-fade:** where an element has somewhere to come from, it grows out of that place (anchor / origin rect); where it has somewhere to go, it shrinks back there.
4. **Squash on press, overshoot on release:** scale 0.96 and a slight brightness drop on press; on release, spring back to 1.0 with about 2% overshoot.
5. **Degradation:**

   | Condition | Behaviour |
   |---|---|
   | reduced | All springs become critically damped and shortened, no overshoot; morphs become 150ms fades |
   | off | Instant |
   | low tier | Motion kept, overshoot removed |

## Phases (one commit each, with format/analyze/test/build)
| # | Item | Content | Risk |
|---|---|---|---|
| **L0** | Motion base v2 | Spring tokens snappy/bouncy/smooth; `SpringController` (interruptible, keeps velocity); `SpringValueBuilder` (implicit spring for double / Offset / Size / radius); `SpringAnimatedSize`; reduce-motion / tier mapping; default intensity changed to 轻盈 and glow α toned down | Low |
| **L1** | Touch feel | `NexusPressable` gets spring squash-and-rebound and is rolled out to buttons, cards, list rows and icon buttons; icon-state morph (`MorphIcon`: send↔stop, mic↔send, copy→✓, expand arrow) using scale + rotate springs | Low |
| **L2** | Input capsule morph | Capsule height / radius / width change continuously with content and mode (single line → multi-line → attachment drawer → voice); the send button changes shape from circle to rounded square (stop); after sending, the new bubble **flies out of the input position** into the list | Medium (big file) |
| **L3** | Messages & streaming | Bubbles spring in (from the input side / from the left); streamed answer height grows with a spring rather than jumping; tool cards / plan panel expand as a morph (height + radius + content stagger); the thinking indicator becomes springy breathing dots | Low–medium |
| **L4** | Sheets / dialogs / menus | Sheets follow the finger when dragged, with rubber-band at the edges and velocity snap on release; dialogs and popup menus **grow from the tapped element** (anchor morph); approval sheet included | Medium |
| **L5** | Page transitions | **Container transform** from list cards to detail pages (history / tasks / providers / MCP); back swipe follows the finger and settles with a spring | ⚠ Route changes: needs confirmation |
| **L6** | Lists & controls | Segmented control / filter pills: the indicator slides and stretches between options (elastic stretch); switches / checkboxes spring; deleted list items collapse with a spring; overscroll stretch; lively pull-to-refresh | Low |
| **L7** | Micro-interactions + light-effect cleanup | Copy ✓, badge pop, success pulse, number rolls (token / count); light effects run at 轻盈 intensity, only on the empty and thinking states; overall rhythm pass | Low |
| **L8** | Acceptance & docs | Frame-time sampling (high / mid / low), reduce-motion walkthrough, `docs/motion_lively.md` | — |

## Performance and constraints
- No new dependencies: `flutter/physics.dart` (`SpringSimulation`) plus the existing `AnimationController.animateWith`.
- Springs only drive transform / opacity / clip (no layout thrash). Size changes go through `SpringAnimatedSize` with a single relayout.
- Morphs use snapshots or `RepaintBoundary` so large subtrees aren't redrawn every frame.
- Business logic, routing tables and state management are not touched. L5 must change how routes are built (a new `ContainerTransformRoute`), so it needs your confirmation.

## Acceptance (device)
- Rapid repeated taps / reversing mid-animation: no jumps, velocity carries through.
- Sheet fling: the stopping position follows the fling speed.
- With reduce-motion on, no overshoot or loops anywhere.
- 60fps (120 on high-end devices): check the frame-time histogram with the diagnostics card.

## Confirmed decisions (2026-09-28, round 2)
- Plan approved. L5 container transform pre-approved (new route type, routing table unchanged).
- Overshoot about 5% (bouncy ζ≈0.69). Brisk rhythm: settles in about 0.3s.
- Light haptic at key motion points: sheet snap, switch / segment change, drag past threshold (`selectionClick`).
- L2 uses the "bubble flies out of the input box" effect.
- Build a package only at L2 / L4 / L6. Merge `stash@{0}` back after the redesign is done.
