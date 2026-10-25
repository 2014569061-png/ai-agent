// Isolated native component/performance harness. Never uses user accounts.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FramePhase;
import 'frame_timing_window.dart';
import 'desktop_frame_pump.dart';
import 'desktop_cpu_profile.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_agent/presentation/chat/widgets/streaming_markdown.dart';
import 'package:flutter/material.dart';
import 'package:mobile_agent/presentation/chat/widgets/message_bubble.dart';
import 'package:mobile_agent/presentation/motion/spring_follow_height.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:mobile_agent/application/desktop_pty_terminal.dart';
import 'package:mobile_agent/application/bounded_log_buffer.dart';
import 'package:mobile_agent/application/desktop_host_service.dart';
import 'package:mobile_agent/domain/models.dart';
import 'package:mobile_agent/presentation/chat/widgets/chat_message_list.dart';
import 'package:mobile_agent/presentation/theme/desktop_theme.dart';
import 'package:mobile_agent/presentation/navigation/desktop_review_panel.dart';
import 'package:mobile_agent/application/desktop_diff.dart';

final _boot = Stopwatch();
String _acceptanceShell = 'powershell';
final _perfVariant = Platform.environment['MOBILE_AGENT_P2_VARIANT'] ?? 'chat';
void main(List<String> args) {
  if (args.contains('--shell=cmd')) _acceptanceShell = 'cmd';
  _boot.start();
  WidgetsFlutterBinding.ensureInitialized();
  const MethodChannel('nexus/desktop_lifecycle')
      .setMethodCallHandler((call) async {
    if (call.method == 'prepareClose') return true;
    throw MissingPluginException();
  });
  runApp(MaterialApp(
      theme: DesktopTheme.apply(ThemeData.light()), home: const Acceptance()));
}

class Acceptance extends StatefulWidget {
  const Acceptance({super.key});
  @override
  State<Acceptance> createState() => _AcceptanceState();
}

class _AcceptanceState extends State<Acceptance> {
  final _scroll = ScrollController(), _input = TextEditingController();
  List<ChatMessage> _messages = [];
  final List<FrameTiming> _frames = [];
  DesktopCpuProfile? _cpuProfile;
  final _timingEvents = StreamController<void>.broadcast(sync: true);
  final Map<String, dynamic> _report = {
    'mode': kReleaseMode
        ? 'release native isolated harness'
        : 'profile native diagnostic harness',
    'shell': _acceptanceShell,
    'modelRequests': 0,
    'streamingVariant': _perfVariant,
    'diagnosticOnly': !kReleaseMode ||
        _perfVariant != 'chat' ||
        Platform.environment['MOBILE_AGENT_P2_CPU_PROFILE'] == '1',
    'semanticsEnabled':
        WidgetsBinding.instance.platformDispatcher.semanticsEnabled
  };
  String _session = 'initial';
  bool _running = false, _diff = false;
  LiveReply? _live;
  String _diffText = '';
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_record);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _report['firstHarnessFrameMs'] = _boot.elapsedMilliseconds;
      unawaited(_verify());
    });
  }

  void _record(List<FrameTiming> timings) {
    _frames.addAll(timings);
    _timingEvents.add(null);
  }

  Future<DesktopFrameBoundary> _frame() => nextRenderedFrame();

  int _percentile(List<int> values, double p) {
    return samplePercentile(values, p);
  }

  Future<Map<String, Object>> _metricsBetween(
      DesktopFrameBoundary after, DesktopFrameBoundary through,
      {required int minimumSamples}) async {
    final refreshRate = View.of(context).display.refreshRate;
    // The engine reports timings in batches. Neutral drain frames flush the
    // final batch; their frame IDs fall outside this completed scene window.
    final drain = Timer.periodic(const Duration(milliseconds: 50), (_) {
      SchedulerBinding.instance.scheduleFrame();
    });
    try {
      final deadline = Stopwatch()..start();
      while (!_frames.any((f) => f.frameNumber >= through.frameNumber)) {
        if (deadline.elapsed > const Duration(seconds: 4)) {
          throw StateError(
              'Timing delivery did not reach frame ${through.frameNumber}');
        }
        await _timingEvents.stream.first.timeout(const Duration(seconds: 4));
      }
      return summarizeFrameWindow(
          _frames.map((f) => DesktopFrameSample(
                frameNumber: f.frameNumber,
                vsyncStartUs: f.timestampInMicroseconds(FramePhase.vsyncStart),
                buildUs: f.buildDuration.inMicroseconds,
                rasterUs: f.rasterDuration.inMicroseconds,
                vsyncOverheadUs: f.vsyncOverhead.inMicroseconds,
                totalSpanUs: f.totalSpan.inMicroseconds,
              )),
          afterFrame: after.frameNumber,
          throughFrame: through.frameNumber,
          minimumSamples: minimumSamples,
          refreshHz: refreshRate);
    } finally {
      drain.cancel();
    }
  }

  Future<void> _pty() async {
    final root = await Directory.systemTemp.createTemp('nexus-native-pty-');
    final channel = DesktopHostService.channel;
    final cmd = _acceptanceShell == 'cmd';
    if (cmd) {
      await File('${root.path}/native-output.txt')
          .writeAsString('NATIVE_中文\r\n');
    }
    int? id;
    final emulator = DesktopPtyTerminal();
    final input = StreamController<List<int>>();
    final output = StringBuffer();
    final responses = <String>[];
    final decoded = input.stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((text) {
      output.write(text);
      emulator.write(text);
    });
    emulator.onOutput = (text) {
      responses.add(text);
      if (id != null) {
        unawaited(channel
            .invokeMethod<void>('writeTerminal', {'id': id, 'text': text}));
      }
    };
    try {
      id = await channel.invokeMethod<int>('openTerminal', {
        'cwd': root.path,
        'cols': 100,
        'rows': 30,
        'shell': _acceptanceShell
      });
      emulator.resize(100, 30);
      Future<String> waitFor(String expected,
          {int attempts = 160, int after = 0}) async {
        for (var i = 0; i < attempts; i++) {
          final data = await channel
              .invokeMapMethod<String, dynamic>('readTerminal', {'id': id});
          _report['conptyTransport'] = {
            'exitCode': data?['exitCode'],
            'writtenBytes': data?['writtenBytes'],
            'writeError': data?['writeError'],
            'responses': responses,
          };
          input.add((data!['bytes'] as List).cast<int>());
          await Future<void>.delayed(Duration.zero);
          final text = output.toString();
          if (text.substring(after).contains(expected)) return text;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        _report['conptyOutputTail'] = output.toString();
        throw StateError('ConPTY did not emit $expected');
      }

      // ConPTY/PSReadLine negotiate cursor/device reports before accepting
      // keyboard input. Pump the emulator to a prompt before submitting work.
      await waitFor(cmd ? '>' : 'PS ', attempts: 900);
      emulator.resize(120, 40);
      await channel.invokeMethod<void>(
          'resizeTerminal', {'id': id, 'cols': 120, 'rows': 40});
      await channel.invokeMethod<void>('writeTerminal', {
        'id': id,
        'text': cmd
            ? "set nexusAcceptance=41& set nexusInterrupted=INTERRUPT& set nexusSleep=ENTERED& type native-output.txt\r"
            : "\$global:nexusAcceptance=41; Write-Output ('NATIVE_' + [char]0x4e2d + [char]0x6587)\r"
      });
      await waitFor('NATIVE_中文');
      await channel.invokeMethod<void>('writeTerminal', {
        'id': id,
        'text': cmd
            ? "set /a nexusAcceptance+=1\r"
            : "\$global:nexusAcceptance++; Write-Output ('PERSIST_' + \$global:nexusAcceptance)\r"
      });
      if (cmd) {
        await channel.invokeMethod<void>('writeTerminal',
            {'id': id, 'text': 'echo PERSIST_%nexusAcceptance%\r'});
      }
      await waitFor('PERSIST_42');
      final sleepStart = output.length;
      await channel.invokeMethod<void>('writeTerminal', {
        'id': id,
        'text': cmd
            ? "echo SLEEP_%nexusSleep%& ping -n 30 127.0.0.1 >nul\r"
            : "Write-Output ('SLEEP_' + 'ENTERED'); Start-Sleep -Seconds 30\r"
      });
      await waitFor('SLEEP_ENTERED', after: sleepStart);
      // Ctrl+C clears pending PSReadLine input. Do not append the next command
      // to the same write; wait for a fresh prompt after the long job is stopped.
      final interruptStart = output.length;
      final interrupt = Stopwatch()..start();
      await channel
          .invokeMethod<void>('writeTerminal', {'id': id, 'text': "\x03"});
      await waitFor(cmd ? '>' : 'PS ', after: interruptStart);
      final resumedStart = output.length;
      await channel.invokeMethod<void>('writeTerminal', {
        'id': id,
        'text': cmd
            ? "echo AFTER_%nexusInterrupted%\r"
            : "Write-Output ('AFTER_' + 'INTERRUPT')\r"
      });
      await waitFor('AFTER_INTERRUPT', after: resumedStart);
      interrupt.stop();
      _report['conpty'] = {
        'utf8': true,
        'persistentShell': true,
        'resize': true,
        'interrupt': true,
        'interruptToOutputMs': interrupt.elapsedMilliseconds
      };
    } catch (error, stack) {
      _report['conptyFailure'] = {'error': '$error', 'stack': '$stack'};
      rethrow;
    } finally {
      emulator.onOutput = null;
      await input.close();
      await decoded.cancel();
      Object? cleanupError;
      try {
        if (id != null) {
          await channel.invokeMethod<void>(
              'closeTerminal', {'id': id}).timeout(const Duration(seconds: 15));
        }
      } catch (error) {
        cleanupError = error;
        _report['conptyCloseFailure'] = '$error';
      }
      for (var attempt = 0; attempt < 50; attempt++) {
        try {
          await root.delete(recursive: true);
          _report['conptyDirectoryReleased'] = true;
          break;
        } on FileSystemException catch (error) {
          if (attempt == 49) {
            cleanupError ??= error;
            _report['conptyCleanupFailure'] = '$error';
          } else {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }
      }
      if (cleanupError != null && !_report.containsKey('conptyFailure')) {
        throw cleanupError;
      }
    }
  }

  Future<void> _verify() async {
    try {
      _report['environment'] = {
        'os': Platform.operatingSystemVersion,
        'dart': Platform.version,
        'processors': Platform.numberOfProcessors,
        'dpr': View.of(context).devicePixelRatio,
        'refreshHz': View.of(context).display.refreshRate
      };
      await _pty();
      _report['functionalPassed'] = true;
      _report['samplingSchema'] = 2;
      // Control case distinguishes streaming work from general frame pacing.
      for (var i = 0; i < 5; i++) {
        await _frame();
      }
      final idleStart = await _frame();
      var idleEnd = idleStart;
      final idleTimes = <int>[];
      for (var i = 0; i < 25; i++) {
        final timer = Stopwatch()..start();
        _input.text = 'control input $i';
        idleEnd = await _frame();
        idleTimes.add(timer.elapsedMicroseconds);
      }
      _report['inputOnly'] = {
        'controlledInputToFrameP95Us': _percentile(idleTimes, .95),
        ...await _metricsBetween(idleStart, idleEnd, minimumSamples: 25),
      };
      _cpuProfile = await DesktopCpuProfile.startIfRequested();
      final cases = <Map<String, dynamic>>[];
      _report['history'] = cases;
      for (final count in [100, 1000, 5000]) {
        final cpuStart = _cpuProfile?.begin();
        final messages = List.generate(
            count,
            (i) => ChatMessage(
                id: 'm$i',
                role: i.isEven ? MessageRole.user : MessageRole.assistant,
                parts: [MessagePart.text('隔离测试消息 $i\n\n用于测量长会话窗口与本地滚动。')]));
        final after = await _frame();
        final switching = Stopwatch()..start();
        setState(() {
          _messages = messages;
          _session = '$count';
        });
        await _frame();
        switching.stop();
        var through = after;
        for (var i = 0; i < 35; i++) {
          if (_scroll.hasClients) {
            _scroll.jumpTo((_scroll.position.maxScrollExtent * ((i % 10) / 10))
                .clamp(0, _scroll.position.maxScrollExtent));
          }
          through = await _frame();
        }
        cases.add({
          'messages': count,
          'switchToFirstFrameUs': switching.elapsedMicroseconds,
          ...await _metricsBetween(after, through, minimumSamples: 36),
          if (cpuStart != null)
            'cpuProfile': await _cpuProfile!.capture('$count', cpuStart)
        });
      }
      _report['history'] = cases;
      final inputTimes = <int>[];
      final streamStart = await _frame();
      var streamEnd = streamStart;
      final updateWork = <int>[];
      setState(() {
        _running = true;
        _messages = [
          ChatMessage(
              role: MessageRole.assistant, parts: const [MessagePart.text('')])
        ];
        _session = 'stream';
      });
      final text = ('段落 **内容** 与流式刷新。\n\n' * 4000).substring(0, 50000);
      for (var i = 500; i <= text.length; i += 500) {
        final timer = Stopwatch()..start();
        _input.text = '输入延迟测量 $i';
        setState(() =>
            _live = LiveReply(messageIndex: 0, text: text.substring(0, i)));
        updateWork.add(timer.elapsedMicroseconds);
        streamEnd = await _frame();
        inputTimes.add(timer.elapsedMicroseconds);
      }
      _report['streaming50k'] = <String, Object>{
        'controlledInputToFrameP95Us': _percentile(inputTimes, .95),
        'synchronousUpdateP95Us': _percentile(updateWork, .95),
      };
      _report['streaming50k'].addAll(
          await _metricsBetween(streamStart, streamEnd, minimumSamples: 100));
      var blocks = 0, characters = 0;
      void visit(Element element) {
        final child = element.widget;
        if (child is DeferredMarkdown) {
          blocks++;
          characters += child.data.length;
        }
        element.visitChildElements(visit);
      }

      if (!mounted) throw StateError('Harness disposed during measurement');
      context.visitChildElements(visit);
      _report['streaming50k']['retainedMarkdownBlocks'] = blocks;
      _report['streaming50k']['retainedMarkdownCharacters'] = characters;
      setState(() {
        _running = false;
        _live = null;
      });
      final log = BoundedLogBuffer();
      final memoryBefore = ProcessInfo.currentRss;
      final logTimer = Stopwatch()..start();
      for (var i = 0; i < 100000; i += 1000) {
        log.append(List.generate(1000, (j) => '日志 ${i + j}: 数据输出\n').join());
      }
      logTimer.stop();
      _report['log100k'] = {
        'boundedCharacters': log.text.length,
        'boundedLines': log.lines.length,
        'appendUs': logTimer.elapsedMicroseconds,
        'rssBefore': memoryBefore,
        'rssAfter': ProcessInfo.currentRss,
        'bounded': log.text.length <= log.maxCharacters &&
            log.lines.length <= log.maxLines
      };
      final largeDiff =
          '--- a/main.dart\n+++ b/main.dart\n@@ -1,50000 +1,50000 @@\n${List.generate(50000, (i) => ' const number$i = $i;').join('\n')}\n';
      if (DesktopDiff.parse(largeDiff).hunks.single.lines.length != 50000) {
        throw StateError('Diff parser lost lines');
      }
      setState(() {
        _diff = true;
        _diffText = largeDiff;
      });
      await _frame();
      for (var i = 0; i < 30; i++) {
        setState(() => _diff = !_diff);
        await _frame();
      }
      _report['componentSwitch30'] = {
        'rss': ProcessInfo.currentRss,
        'passed': true
      };
      _report['performanceLimits'] = {
        'controlledInputP95Us': 50000,
        'reference60HzUiRasterP95Us': 16667,
        'switchFirstFrameUs': 300000
      };
      _report['performancePassed'] = _report['diagnosticOnly'] == false &&
          cases.every((c) =>
              c['reference60HzPassed'] == true &&
              c['switchToFirstFrameUs'] <= 300000) &&
          _report['inputOnly']['controlledInputToFrameP95Us'] <= 50000 &&
          _report['streaming50k']['controlledInputToFrameP95Us'] <= 50000 &&
          _report['streaming50k']['reference60HzPassed'] == true;
      _report['passed'] = _report['functionalPassed'] == true &&
          _report['log100k']['bounded'] == true &&
          _report['performancePassed'] == true;
    } catch (error, stack) {
      _report['passed'] = false;
      _report['error'] = '$error';
      _report['stack'] = '$stack';
    }
    await _cpuProfile?.close();
    final output = File('artifacts/desktop/native-acceptance-2026-10-15.json');
    await output.parent.create(recursive: true);
    await output
        .writeAsString(const JsonEncoder.withIndent('  ').convert(_report));
    if (mounted) setState(() {});
    debugPrint('Desktop acceptance report: ${output.absolute.path}');
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_record);
    unawaited(_timingEvents.close());
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  Widget _messageView(BuildContext context) {
    final list = ChatMessageList(
      messages: _messages,
      controller: _scroll,
      running: _running,
      liveReply: _live,
      sessionKey: _session,
      onLongPress: (_) {},
      onRegenerate: () {},
    );
    if (_session != 'stream' || _perfVariant == 'chat') return list;
    if (_perfVariant == 'chat-no-motion') {
      return MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: list);
    }
    final text = _live?.text ?? '';
    if (_perfVariant.startsWith('bubble') || _perfVariant == 'spring') {
      final bubble = MessageBubble(
        message: ChatMessage(
            role: MessageRole.assistant, parts: [MessagePart.text(text)]),
        isLast: true,
        running: _running,
        onLongPress: null,
        onRegenerate: () {},
      );
      Widget child = bubble;
      if (_perfVariant == 'bubble-no-semantics') {
        child = ExcludeSemantics(child: child);
      }
      if (_perfVariant == 'bubble-no-desktop') {
        child = Theme(
            data: Theme.of(context).copyWith(extensions: const []),
            child: child);
      }
      return SingleChildScrollView(
          child: _perfVariant == 'spring'
              ? SpringFollowHeight(child: child)
              : child);
    }
    final content = SingleChildScrollView(
        child: _perfVariant == 'plain'
            ? Text(text)
            : StreamingMarkdown(
                data: text,
                textColor: Colors.black,
                tailStyle: const TextStyle(fontSize: 14),
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))));
    return _perfVariant == 'markdown-selection'
        ? SelectionArea(child: content)
        : content;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('NEXUS 隔离原生验收')),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(controller: _input)),
        Expanded(
            child: _diff
                ? DesktopDiffView(text: _diffText)
                : _messageView(context)),
        Text('验收状态：${_report['passed'] ?? '执行中'}'),
      ]));
}
