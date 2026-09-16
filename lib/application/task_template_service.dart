import '../domain/collaboration_models.dart';
import 'project_kind.dart';

class TaskTemplate {
  const TaskTemplate({
    required this.id,
    required this.title,
    required this.description,
    required this.taskType,
    required this.systemPrompt,
    required this.requiredInputs,
    required this.allowedTools,
    required this.acceptanceRules,
    this.riskLevel = 'read_only',
    this.implementsChanges = false,
  });

  final String id;
  final String title;
  final String description;
  final String taskType;
  final String systemPrompt;
  final List<String> requiredInputs;
  final List<String> allowedTools;
  final List<String> acceptanceRules;
  final String riskLevel;
  final bool implementsChanges;

  bool get isDevelopmentLoop => implementsChanges;
}

class TaskTemplateService {
  static const implementAndVerify = TaskTemplate(
    id: 'implement-and-verify',
    title: '实现并验证',
    description: '在授权工作区实现需求，随后自动分析、测试并检查真实构建产物。',
    taskType: 'implement_and_verify',
    riskLevel: 'writes_code',
    implementsChanges: true,
    systemPrompt: '''你负责在用户授权的工作区完成开发闭环，而不是只给建议。

必须按这个顺序工作：
1. 先阅读项目结构，确认项目类型（Flutter / Android / Node / Python / 静态网页）。
2. 用 edit_file / write_file 做最小必要改动，禁止编造未执行的修改。
3. 改完后必须用 terminal 执行项目对应的验证命令，并依据真实输出汇报。
4. Flutter 默认执行：flutter analyze、flutter test、flutter build apk --release。
5. Android Gradle 默认执行测试和 assembleRelease。
6. Node 执行 package.json 中已有的 test/build 脚本。
7. 构建完成后检查产物是否真实存在，禁止只报一个理论路径。
8. 最后列出修改文件、验证状态（未验证 / 通过 / 失败）和下一步。
失败时说明失败步骤、关键日志和可单步重试的命令，不要整轮假装成功。''',
    requiredInputs: ['工作区路径', '要实现的需求'],
    allowedTools: [
      'read_file',
      'list_directory',
      'search_files',
      'edit_file',
      'write_file',
      'move_file',
      'delete_file',
      'terminal',
    ],
    acceptanceRules: [
      '实际修改了代码或明确说明无需改动的证据',
      '执行了项目对应的分析/测试/构建命令',
      '产物路径对应真实文件，或明确说明构建失败原因',
    ],
  );

  static const _templates = <TaskTemplate>[
    implementAndVerify,
    TaskTemplate(
      id: 'project-analysis',
      title: '项目解读',
      description: '输出技术栈、模块边界、启动方式、风险项和阅读路径。',
      taskType: 'project_analysis',
      systemPrompt: '你负责做项目解读。先识别项目类型，再基于授权工作区给出技术栈、模块边界、启动/验证命令和风险。不要修改文件。',
      requiredInputs: ['工作区路径或项目结构'],
      allowedTools: ['read_file', 'list_directory', 'search_files'],
      acceptanceRules: ['包含技术栈', '包含模块边界', '包含风险和下一步'],
    ),
    TaskTemplate(
      id: 'bug-fix',
      title: '问题修复',
      description: '定位根因并在授权工作区落地修复，随后运行验证命令。',
      taskType: 'bug_fix',
      riskLevel: 'writes_code',
      implementsChanges: true,
      systemPrompt: '''你负责修复问题。先给证据和根因，再直接在授权工作区修改代码。
修复后必须运行项目对应的验证命令（Flutter：flutter analyze / flutter test；能构建时再构建）。
不要只给建议；如果无法修改，必须说明缺了哪项授权或工具。''',
      requiredInputs: ['错误日志、堆栈或复现步骤'],
      allowedTools: [
        'read_file',
        'list_directory',
        'search_files',
        'edit_file',
        'write_file',
        'terminal',
      ],
      acceptanceRules: ['指出根因', '列出证据', '给出并执行验证命令'],
    ),
    TaskTemplate(
      id: 'code-review',
      title: '代码审查',
      description: '按严重级别输出问题、证据、修复建议和待确认项。',
      taskType: 'code_review',
      systemPrompt: '你负责代码审查。按严重级别审查风险，不提交代码、不修改远端仓库。',
      requiredInputs: ['diff、代码片段或 PR 链接'],
      allowedTools: ['read_file', 'list_directory', 'search_files'],
      acceptanceRules: ['问题有严重级别', '问题有证据', '建议可验证'],
    ),
    TaskTemplate(
      id: 'release-check',
      title: '发布检查',
      description: '检查版本、签名、环境变量、测试、构建产物和变更说明。',
      taskType: 'release_check',
      riskLevel: 'writes_code',
      implementsChanges: true,
      systemPrompt: '''你负责发布前检查。先核对版本、测试和构建产物是否真实存在。
对 Flutter/Android 项目，优先执行分析、测试和构建，并检查 APK 是否存在、包名是否符合预期。
不要执行发布上传。''',
      requiredInputs: ['版本信息、构建输出或发布说明'],
      allowedTools: [
        'read_file',
        'list_directory',
        'search_files',
        'terminal',
      ],
      acceptanceRules: ['有发布清单', '明确阻断项', '明确验证命令和真实产物'],
    ),
  ];

  List<TaskTemplate> all() => _templates;

  TaskTemplate? findByType(String? taskType) {
    var normalized = taskType?.trim() ?? '';
    if (normalized.isEmpty || normalized == 'general') {
      return null;
    }
    if (normalized.startsWith('development:')) {
      normalized = normalized.substring('development:'.length);
    }
    for (final template in _templates) {
      if (template.taskType == normalized || template.id == normalized) {
        return template;
      }
    }
    return null;
  }

  TaskTemplate forTask(DevelopmentTaskInput task) {
    return findByType(task.taskType) ?? _templates[0];
  }

  String promptBlock({
    required String? taskType,
    ProjectKindDetection? project,
  }) {
    final template = findByType(taskType);
    if (template == null) return '';
    final buffer = StringBuffer()
      ..writeln('[开发任务模板：${template.title}]')
      ..writeln(template.systemPrompt.trim())
      ..writeln('验收标准：${template.acceptanceRules.join('；')}。');
    if (project != null && project.isKnown) {
      buffer
        ..writeln('当前识别到的项目类型：${project.kind.label}。')
        ..writeln(
            '建议验证步骤：${[project.testCommand, project.buildCommand].whereType<String>().join('；')}');
    }
    return buffer.toString().trim();
  }
}
