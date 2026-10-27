import 'package:flutter/material.dart';
import '../../application/desktop_host_service.dart';
import '../navigation/desktop_devices_dialog.dart';
import '../projects/project_picker_page.dart';
import '../scheduled/scheduled_tasks_page.dart';
import '../diagnostics/log_viewer_page.dart';
import '../theme/desktop_theme.dart';
import 'provider_list_page.dart';
import 'extensions_page.dart';
import 'appearance_theme_page.dart';
import 'data_management_page.dart';
import '../theme/mobile_theme.dart';

class DesktopSettingsPage extends StatefulWidget {
  const DesktopSettingsPage(
      {super.key, required this.onUpdate, required this.onFontSize});
  final VoidCallback onUpdate, onFontSize;
  @override
  State<DesktopSettingsPage> createState() => _DesktopSettingsPageState();
}

class _DesktopSettingsPageState extends State<DesktopSettingsPage> {
  int _category = 0;
  String _query = '';
  String? _error;
  static const _categories = [
    '模型与服务商',
    '项目与执行',
    '工具与 MCP',
    '外观与快捷键',
    '数据与更新',
    'Android 设备'
  ];
  void _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  Widget _link(
          String title, String detail, IconData icon, VoidCallback action) =>
      Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
              contentPadding: const EdgeInsets
                  .symmetric(horizontal: 18, vertical: 10),
              title:
                  Text(
                      title,
                      style:
                          const TextStyle(
                              fontSize: DesktopTheme.baseSize,
                              fontWeight: FontWeight.w600)),
              subtitle:
                  Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(detail)),
              leading: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: DesktopTheme.of(context).selected,
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon,
                      size: 19, color: DesktopTheme.of(context).accent)),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: action));
  Future<void> _configure({bool? tray, bool? notifications}) async {
    try {
      final host = DesktopHostService.instance;
      await host.configure(
          closeToTray: tray ?? host.closeToTray,
          notifications: notifications ?? host.notifications);
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = '保存设置失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final host = DesktopHostService.instance;
    final colors = DesktopTheme.of(context);
    final groups = <List<Widget>>[
      [
        _link('管理模型与服务商', 'API 地址、模型、密钥和连接测试', Icons.smart_toy_outlined,
            () => _open(const ProviderListPage()))
      ],
      [
        _link('项目工作区', '选择或管理项目目录', Icons.folder_outlined,
            () => _open(const ProjectPickerPage())),
        _link('定时任务', '应用运行时检查到期任务；退出或休眠期间不执行', Icons.schedule,
            () => _open(const ScheduledTasksPage())),
        SwitchListTile(
            title: const Text('关闭窗口时保留在托盘'),
            subtitle: const Text('托盘菜单可重新打开或退出并停止任务。应用退出、注销或系统休眠时停止调度。'),
            value: host.closeToTray,
            onChanged: (value) => _configure(tray: value)),
        SwitchListTile(
            title: const Text('任务通知'),
            subtitle: const Text('任务完成、失败或需要审批时通知'),
            value: host.notifications,
            onChanged: (value) => _configure(notifications: value)),
      ],
      [
        _link('管理扩展', '技能、MCP 服务和工具授权', Icons.extension_outlined,
            () => _open(const ExtensionsPage()))
      ],
      [
        _link('外观', '浅色、深色与系统主题；遵循系统高对比度和减少动态效果', Icons.palette_outlined,
            () => _open(const AppearanceThemePage())),
        _link('字体大小', '调整界面文字大小', Icons.text_fields, widget.onFontSize),
        const Padding(
            padding: EdgeInsets.all(16),
            child: SelectableText(
                'Ctrl+K  命令中心\nCtrl+P  搜索项目、会话与任务\nCtrl+1～5  切换页面\nEnter  发送（输入法组合期间不发送）\nShift+Enter  换行\n右键消息  编辑、引用、分叉和复制\n命令中心可切换专注、执行、审查布局')),
      ],
      [
        _link('数据与备份', '导出记录、备份与恢复', Icons.storage_outlined,
            () => _open(const DataManagementPage())),
        _link('诊断日志', '查看实际运行记录与错误', Icons.bug_report_outlined,
            () => _open(const LogViewerPage())),
        _link('检查更新', '校验下载包后打开升级位置', Icons.system_update, widget.onUpdate),
      ],
      [
        _link(
            '已连接 Android 设备',
            '授权后投屏、截图与输入；设备命令显式绑定序列号',
            Icons.phone_android,
            () => showDialog<void>(
                context: context, builder: (_) => const DesktopDevicesDialog()))
      ],
    ];
    const icons = [
      Icons.smart_toy_outlined,
      Icons.folder_outlined,
      Icons.extension_outlined,
      Icons.palette_outlined,
      Icons.storage_outlined,
      Icons.phone_android_outlined
    ];
    const descriptions = [
      '配置连接，让合适的模型参与工作。密钥继续使用系统安全存储。',
      '管理项目、计划任务和桌面后台行为。',
      '连接技能与 MCP，明确工具的授权边界。',
      '让工作台适应你的视觉和键盘操作习惯。',
      '管理本地数据、诊断记录与应用更新。',
      '连接和操作已授权的 Android 设备。',
    ];
    final matches = [
      for (var i = 0; i < _categories.length; i++)
        if (_query.isEmpty ||
            _categories[i].toLowerCase().contains(_query.trim().toLowerCase()))
          i
    ];
    Widget navigation() => Material(
        color: colors.sidebar,
        child: ListView(padding: const EdgeInsets.all(14), children: [
          Text('偏好设置',
              style: TextStyle(
                  fontSize: 11,
                  color: colors.muted,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                  hintText: '搜索分类', prefixIcon: Icon(Icons.search, size: 18))),
          const SizedBox(height: 14),
          if (matches.isEmpty)
            Padding(
                padding: const EdgeInsets.all(12),
                child: Text('没有匹配的分类', style: TextStyle(color: colors.muted))),
          for (final i in matches)
            Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: ListTile(
                    key: ValueKey('desktop-settings-category-$i'),
                    selected: _category == i,
                    leading: Icon(icons[i], size: 18),
                    title: Text(_categories[i],
                        style:
                            const TextStyle(fontSize: DesktopTheme.labelSize)),
                    onTap: () => setState(() => _category = i))),
        ]));
    Widget content() => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: ListView(padding: const EdgeInsets.all(28), children: [
              Row(children: [
                Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                        color: colors.selected,
                        borderRadius: BorderRadius.circular(MobileTheme.insetRadius)),
                    child:
                        Icon(icons[_category], color: colors.accent, size: 23)),
                const SizedBox(width: 14),
                Expanded(
                    child: Text(_categories[_category],
                        style: Theme.of(context).textTheme.headlineSmall)),
              ]),
              const SizedBox(height: 12),
              Text(descriptions[_category],
                  style: TextStyle(color: colors.muted, height: 1.6)),
              const SizedBox(height: 26),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
              ...groups[_category],
            ])));
    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
          title: const Text('设置'),
          bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Divider(height: 1, color: colors.border))),
      body: LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < 760) {
          return Column(children: [
            Padding(
                padding: const EdgeInsets.all(16),
                child: DropdownButtonFormField<int>(
                    key: ValueKey('desktop-settings-compact-$_category'),
                    initialValue: _category,
                    decoration: const InputDecoration(labelText: '设置分类'),
                    items: [
                      for (var i = 0; i < _categories.length; i++)
                        DropdownMenuItem(value: i, child: Text(_categories[i]))
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _category = value);
                    })),
            Expanded(child: content()),
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(width: 240, child: navigation()),
          VerticalDivider(width: 1, color: colors.border),
          Expanded(child: content()),
        ]);
      }),
    );
  }
}
