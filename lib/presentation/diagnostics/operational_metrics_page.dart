import '../theme/desktop_theme.dart';
import '../widgets/nexus_disclosure.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/nexus_page_layout.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../application/operational_metrics.dart';
import '../../application/run_event_tracker.dart';
import '../../infrastructure/database/app_database.dart';

class OperationalMetricsPage extends StatefulWidget {
  const OperationalMetricsPage(
      {super.key,
      required this.database,
      this.initialEnvironment = RunEventTracker.runtimeEnvironment});
  final Future<AppDatabase> Function() database;
  final String initialEnvironment;
  @override
  State<OperationalMetricsPage> createState() => _OperationalMetricsPageState();
}

class _OperationalMetricsPageState extends State<OperationalMetricsPage> {
  late String _environment;
  int _days = 7, _generation = 0;
  ReferenceSlo? _target;
  final _latency = TextEditingController(text: '30000'),
      _rate = TextEditingController(text: '99'),
      _samples = TextEditingController(text: '20');
  Map<String, dynamic>? _report;
  String? _targetError;
  bool _loading = true, _error = false;
  static const environments = {
    'debug': '调试 debug',
    'profile': '性能 profile',
    'release': '发布 release',
    'fixture': '合成 fixture'
  };
  @override
  void initState() {
    super.initState();
    _environment = widget.initialEnvironment;
    _load();
  }

  @override
  void dispose() {
    _latency.dispose();
    _rate.dispose();
    _samples.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final ticket = ++_generation,
        environment = _environment,
        days = _days,
        target = _target;
    setState(() {
      _loading = true;
      _error = false;
      _report = null;
    });
    try {
      final db = await widget.database();
      final until = DateTime.now();
      final report = await OperationalMetrics.load(db,
          environment: environment,
          since: until.subtract(Duration(days: days)),
          until: until,
          target: target);
      if (!mounted || ticket != _generation) return;
      setState(() {
        _report = report;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || ticket != _generation) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  void _applyTarget() {
    final latency = int.tryParse(_latency.text),
        rate = double.tryParse(_rate.text),
        samples = int.tryParse(_samples.text);
    if (latency == null ||
        latency < 1 ||
        rate == null ||
        !rate.isFinite ||
        rate < 0 ||
        rate > 100 ||
        samples == null ||
        samples < 20) {
      setState(() => _targetError = '请输入正整数耗时、0–100% 占比，最少样本不得低于20。');
      return;
    }
    setState(() {
      _target = ReferenceSlo(
          p95Ms: latency, successRate: rate / 100, minSamples: samples);
      _targetError = null;
    });
    _load();
  }

  static String _ms(dynamic value) => value == null ? '未知/无样本' : '$value ms';
  static const labels = {
    'model_inference': '模型推理尝试',
    'model_summary': '模型摘要尝试',
    'model_other': '其他模型尝试',
    'tool_end_to_end': '工具端到端（含审批等待）'
  };
  static const assessments = {
    'fixture_only': '合成数据：不可签收',
    'target_not_configured': '未配置参考目标',
    'data_quality_degraded': '数据不完整：不能判达标',
    'insufficient_samples': '样本不足：不能判达标',
    'meets_reference_target': '仅满足本环境参考目标',
    'breach': '未满足本页参考目标'
  };
  Widget _group(String name, Map<String, dynamic> data) {
    final rate = data['successRate'];
    return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(labels[name]!,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(assessments[data['assessment']] ?? '未知状态'),
              if (DesktopTheme.maybeOf(context) == null)
                NexusDisclosure(
                    title: const Text('样本与计时明细'),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '观测 ${data['total']} · 成功 ${data['success']} · 失败 ${data['failed']} · 取消 ${data['cancelled']} · 未完成/未知 ${data['unknown']}'),
                          Text(
                              '尝试成功占比：${rate == null ? '未知/无样本' : '${((rate as num) * 100).toStringAsFixed(1)}%'}（取消与未知计入分母，非业务完成率）'),
                          Text(
                              '耗时样本 ${data['durationSamples']} · P50 ${_ms(data['p50Ms'])} · P95 ${_ms(data['p95Ms'])}'),
                          if (name != 'tool_end_to_end') ...[
                            Text(
                                '首个文本或推理事件 P95：${_ms(data['firstTokenP95Ms'])} · 样本 ${data['firstTokenSamples']}'),
                            Text(
                                '首个文本事件 P95：${_ms(data['firstTextP95Ms'])} · 样本 ${data['firstTextSamples']}'),
                          ],
                          Text('缺失/无效计时：${data['invalidOrMissingTiming']}'),
                          Text('失败分类：${jsonEncode(data['failureCategories'])}'),
                        ])),
              if (DesktopTheme.maybeOf(context) != null) ...[
                Text(
                    '观测 ${data['total']} · 成功 ${data['success']} · 失败 ${data['failed']} · 取消 ${data['cancelled']} · 未完成/未知 ${data['unknown']}'),
                Text(
                    '尝试成功占比：${rate == null ? '未知/无样本' : '${((rate as num) * 100).toStringAsFixed(1)}%'}（取消与未知计入分母，非业务完成率）'),
                Text(
                    '耗时样本 ${data['durationSamples']} · P50 ${_ms(data['p50Ms'])} · P95 ${_ms(data['p95Ms'])}'),
                if (name != 'tool_end_to_end') ...[
                  Text(
                      '首个文本或推理事件 P95：${_ms(data['firstTokenP95Ms'])} · 样本 ${data['firstTokenSamples']}'),
                  Text(
                      '首个文本事件 P95：${_ms(data['firstTextP95Ms'])} · 样本 ${data['firstTextSamples']}'),
                ],
                Text('缺失/无效计时：${data['invalidOrMissingTiming']}'),
                Text('失败分类：${jsonEncode(data['failureCategories'])}'),
              ],
            ])));
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
        appBar: NexusPageHeader(title: '链路指标与参考SLO', actions: [
          IconButton(
              tooltip: '刷新指标',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh)),
          IconButton(
              tooltip: '复制本机指标报告',
              onPressed: report == null
                  ? null
                  : () async {
                      await Clipboard.setData(ClipboardData(
                          text: const JsonEncoder.withIndent('  ')
                              .convert(report)));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('已复制汇总与本机链路标识；不含提示词或工具正文。')));
                    },
              icon: const Icon(Icons.copy)),
        ]),
        body: NexusPageLayout(
            child: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('本地观测，不是发布验收',
              style: TextStyle(fontWeight: FontWeight.w500)),
          const NexusDisclosure(
            title: Text('统计范围与计时说明'),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  '仅统计已持久化运行；不含未落运行记录的后台调用与草稿。环境标签只表示构建模式，不证明真机、APK或网络条件。无外部遥测。'),
              Text(
                  '耗时使用单调时钟；模型为流订阅至结束（含背压/本地处理），工具包含审批与等待。首事件不是网络首字节。缺失值不按0计算。'),
            ]),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
              initialValue: _environment,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '独立环境（不合并统计）'),
              items: [
                for (final e in environments.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value))
              ],
              onChanged: (v) {
                if (v != null) {
                  setState(() => _environment = v);
                  _load();
                }
              }),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
              initialValue: _days,
              decoration: const InputDecoration(labelText: '观测时间窗口'),
              items: const [
                DropdownMenuItem(value: 1, child: Text('最近24小时')),
                DropdownMenuItem(value: 7, child: Text('最近7天'))
              ],
              onChanged: (v) {
                if (v != null) {
                  setState(() => _days = v);
                  _load();
                }
              }),
          const SizedBox(height: 12),
          ExpansionTile(
              title: const Text('本页参考目标（默认未配置）'),
              subtitle: Text(_target == null
                  ? '不会将空样本或未知判为达标'
                  : 'P95 ≤ ${_target!.p95Ms} ms，尝试成功占比 ≥ ${(_target!.successRate * 100).toStringAsFixed(1)}%，每组至少 ${_target!.minSamples} 样本'),
              children: [
                const Text('以下数值只是待确认的输入；点击应用才生效。各分组单独判断，仅本页有效，不是项目发布标准。'),
                TextField(
                    controller: _latency,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: '端到端耗时P95上限（ms）')),
                TextField(
                    controller: _rate,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: '尝试成功占比下限（%）')),
                TextField(
                    controller: _samples,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: '每组最少样本（≥20）')),
                if (_targetError != null)
                  Text(_targetError!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                Wrap(spacing: 12, children: [
                  FilledButton(
                      onPressed: _applyTarget, child: const Text('应用本页参考目标')),
                  TextButton(
                      onPressed: () {
                        setState(() {
                          _target = null;
                          _targetError = null;
                        });
                        _load();
                      },
                      child: const Text('清除参考目标'))
                ]),
              ]),
          if (_loading)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator())),
          if (_error) ...[
            const Text('指标读取失败，未按0或通过处理。'),
            TextButton(onPressed: _load, child: const Text('重试读取'))
          ],
          if (report != null) ...[
            const SizedBox(height: 12),
            if (report['fixtureOnly'] == true)
              const Text('合成数据演示：任何数字均不能作为真实设备性能或发布证据。',
                  style: TextStyle(fontWeight: FontWeight.w500)),
            Text(
                '数据质量：${report['dataQualityDegraded'] == true ? '有缺失/降级，不能判达标' : '本次查询未发现已知缺失（不证明全量完整）'}'),
            const SizedBox(height: 8),
            NexusDisclosure(
              title: const Text('数据质量详情'),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '达到查询上限：${report['truncated']} · 未分类 ${report['unclassifiedEvents']} · 格式异常 ${report['malformedEvents']}'),
                    Text(
                        '父模型不在窗口/缺失：${report['missingModelParents']} · 缺少请求关联：${report['missingLogicalRequestIds']}'),
                    Text(
                        '已排除其他环境 ${report['otherEnvironmentExcluded']} · 排除旧汇总 ${report['legacySummaryRowsExcluded']}（不重复计数）'),
                    Text('持久化降级计数：${jsonEncode(report['persistedHealth'])}'),
                    Text(
                        '本进程降级计数：${jsonEncode(report['processHealth'])}（进程全期，不能与落盘计数相加；重启后未落盘丢失无法追溯）'),
                  ]),
            ),
            const SizedBox(height: 12),
            for (final e in (report['groups'] as Map<String, dynamic>).entries)
              _group(e.key, e.value as Map<String, dynamic>),
            ExpansionTile(
                title: const Text('本机链路关联（最多100条）'),
                subtitle:
                    const Text('仅显示运行/请求/span标识。可在原运行报告中继续回查。复制报告会包含这些关联信息。'),
                children: [
                  for (final span in report['spans'] as List)
                    Padding(
                        padding: const EdgeInsets.all(8),
                        child: SelectableText(jsonEncode(span)))
                ]),
          ],
        ])));
  }
}
