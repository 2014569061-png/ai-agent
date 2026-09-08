import '../domain/collaboration_models.dart';

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
}

class TaskTemplateService {
  static const _templates = <TaskTemplate>[
    TaskTemplate(
      id: 'project-analysis',
      title: '项目解读',
      description: '输出技术栈、模块边界、启动方式、风险项和阅读路径。',
      taskType: 'project_analysis',
      systemPrompt: '你负责做项目解读。只基于用户授权的工作区和输入分析，不修改文件。',
      requiredInputs: ['工作区路径或项目结构'],
      allowedTools: ['read_file', 'list_directory', 'search_files'],
      acceptanceRules: ['包含技术栈', '包含模块边界', '包含风险和下一步'],
    ),
    TaskTemplate(
      id: 'bug-fix',
      title: '问题修复',
      description: '定位根因、影响范围、排查顺序，并生成受控修复建议。',
      taskType: 'bug_fix',
      systemPrompt: '你负责诊断问题。先给证据和根因，再给修复建议，不直接写入文件。',
      requiredInputs: ['错误日志、堆栈或复现步骤'],
      allowedTools: ['read_file', 'list_directory', 'search_files'],
      acceptanceRules: ['指出根因', '列出证据', '给出验证方式'],
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
      systemPrompt: '你负责发布前检查。输出可勾选清单和阻断项，不执行发布。',
      requiredInputs: ['版本信息、构建输出或发布说明'],
      allowedTools: ['read_file', 'list_directory', 'search_files'],
      acceptanceRules: ['有发布清单', '明确阻断项', '明确验证命令'],
    ),
  ];

  List<TaskTemplate> all() => _templates;

  TaskTemplate forTask(DevelopmentTaskInput task) {
    return _templates.firstWhere(
      (template) => template.taskType == task.taskType,
      orElse: () => _templates[0],
    );
  }
}
