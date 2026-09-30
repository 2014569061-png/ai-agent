part of 'chat_page.dart';

/// 技能：安装列表、输入联想、斜杠引用与会话内已加载技能。
extension _ChatSkills on _ChatPageState {
  void _resetSessionSkills() {
    _rebuild(() {
      _loadedSessionSkillIds.clear();
      _skillSuggestions = const [];
      _slashSkillSuggestions = const [];
      _skillSuggestionsDismissed = false;
    });
    _onSkillInputChanged();
  }

  Future<void> _loadInstalledSkills() async {
    final generation = ++_skillLoadGeneration;
    try {
      final database = await ref.read(databaseProvider.future);
      final installed = await _skillStore.all(database);
      if (!mounted || generation != _skillLoadGeneration) return;
      final skills = installed
          .where((pack) => pack.enabled)
          .map((pack) {
            final metadata = _skillStore.readMetadata(pack);
            return metadata == null ? null : _InstalledSkill(pack, metadata);
          })
          .whereType<_InstalledSkill>()
          .toList(growable: false);
      final activeIds = skills.map((item) => item.pack.id).toSet();
      final removedSessionIds = _loadedSessionSkillIds
          .where((id) => !activeIds.contains(id))
          .toList(growable: false);
      if (!mounted || generation != _skillLoadGeneration) return;
      _rebuild(() {
        _installedSkills
          ..clear()
          ..addAll(skills);
        _loadedSessionSkillIds.removeWhere((id) => !activeIds.contains(id));
        _skillSuggestions = const [];
        _slashSkillSuggestions = const [];
      });
      for (final id in removedSessionIds) {
        _chat.removeSessionSkillInstruction(id);
      }
      _refreshSkillSuggestions();
    } catch (_) {
      // Skill suggestions are an optional local enhancement.
    }
  }

  void _onSkillInputChanged() {
    _skillSuggestionDebounce?.cancel();
    _skillSuggestionDebounce =
        Timer(const Duration(milliseconds: 320), _refreshSkillSuggestions);
  }

  void _refreshSkillSuggestions() {
    if (!mounted) return;
    if (_installedSkills.isEmpty) {
      if (_skillSuggestions.isNotEmpty || _slashSkillSuggestions.isNotEmpty) {
        _rebuild(() {
          _skillSuggestions = const [];
          _slashSkillSuggestions = const [];
        });
      }
      return;
    }
    final input = _controller.text.trim();
    // 候选规则（前缀过滤、排除已加载、上限 5 条）与去重比较都在
    // skill_suggestion_rules.dart 里，有单测覆盖。
    final slashSuggestions = selectSlashSkillSuggestions<_InstalledSkill>(
      skills: _installedSkills,
      query: slashSkillQuery(input),
      nameOf: (item) => item.metadata.name,
      isLoaded: (item) => _loadedSessionSkillIds.contains(item.pack.id),
    );
    final suggestions = !shouldOfferIntentSkillSuggestions(
            input: input, dismissed: _skillSuggestionsDismissed)
        ? const <_InstalledSkill>[]
        : _skillMatcher
            .match(input, _installedSkills.map((item) => item.metadata))
            .map((match) => _installedSkills.firstWhere(
                (item) => item.metadata.name == match.metadata.name))
            .where((item) => !_loadedSessionSkillIds.contains(item.pack.id))
            .toList(growable: false);
    if (sameSkillSuggestionOrder<_InstalledSkill>(
            suggestions, _skillSuggestions, idOf: (item) => item.pack.id) &&
        sameSkillSuggestionOrder<_InstalledSkill>(
            slashSuggestions, _slashSkillSuggestions,
            idOf: (item) => item.pack.id)) {
      return;
    }
    _rebuild(() {
      _skillSuggestions = suggestions;
      _slashSkillSuggestions = slashSuggestions;
    });
  }

  void _dismissSkillSuggestions() {
    _skillSuggestionDebounce?.cancel();
    _rebuild(() {
      _skillSuggestionsDismissed = true;
      _skillSuggestions = const [];
    });
  }

  void _loadSuggestedSkill(SkillSuggestionItem item) {
    final skill = _installedSkills
        .where((candidate) => candidate.pack.id == item.id)
        .firstOrNull;
    if (skill == null) return;
    final body = _skillStore.readBody(skill.pack, maxChars: 8000);
    if (body == null || body.trim().isEmpty) {
      FloatingToast.show(context, 'Skill 内容不可用', tone: ToastTone.warning);
      return;
    }
    _chat.addSessionSkillInstruction(
      id: skill.pack.id,
      name: skill.metadata.name,
      instruction: '## 当前会话已加载 Skill：${skill.metadata.name}\n\n$body',
    );
    _rebuild(() {
      _loadedSessionSkillIds.add(skill.pack.id);
      _skillSuggestions = _skillSuggestions
          .where((candidate) => candidate.pack.id != skill.pack.id)
          .toList(growable: false);
    });
    HapticFeedback.selectionClick();
    FloatingToast.show(context, '已为当前会话加载 ${skill.metadata.name}');
  }

  void _insertSlashSkillReference(SkillSuggestionItem item) {
    final current = _controller.text;
    // 文本变换抽到 slash_skill_query.dart（纯函数、有单测）：这里只负责把结果
    // 写回输入框并收起候选。
    final next = insertSlashSkillReference(current, item.name);
    if (next == null) return;
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _rebuild(() => _slashSkillSuggestions = const []);
    HapticFeedback.selectionClick();
  }

  void _removeSessionSkill(String id) {
    _chat.removeSessionSkillInstruction(id);
    _rebuild(() => _loadedSessionSkillIds.remove(id));
    _refreshSkillSuggestions();
  }

  /// 会话指标条（对标 DeepSeek 输入区上方的指标胶囊）。
  ///
  /// 空会话与纯聊天不渲染，避免在首页制造噪音；自定义聊天背景下
  /// 自动切深色半透明底，保证可读性。
  /// 输入区上方的技能提示槽位。
  ///
  /// 三条技能提示（`/` 补全 / 自动建议 / 已加载）视觉同构、都只在非运行态出现，
  /// 因此共用一个槽位，只渲染优先级最高的那条（规则见 [resolveComposerSkillSlot]）。
  /// 输入区上方因此最多只剩：运行状态条（或指标条）+ 上下文提示 + 本槽位。
  List<SkillSuggestionItem> _toSkillItems(List<_InstalledSkill> skills) =>
      skills
          .map((skill) => SkillSuggestionItem(
                id: skill.pack.id,
                name: skill.metadata.name,
                description: skill.metadata.description,
              ))
          .toList(growable: false);

  /// Resolves explicit `/skill_name` references before the user message is sent.
  /// The command itself stays out of conversation history; its content is injected
  /// into this session only, exactly as a tapped suggestion would be.
  String? _resolveSlashSkillReferences(String input) {
    // token 的识别（哪些是完整命令）与删除都在 slash_skill_query.dart 里，有单测；
    // 这里只负责副作用：加载技能到当前会话。
    final names = slashSkillCommandNames(input);
    if (names.isEmpty) return input;

    final recognized = <String>{};
    for (final name in names) {
      final skill = _installedSkills
          .where((candidate) => candidate.metadata.name == name)
          .firstOrNull;
      // Unknown slash tokens are ordinary user text (for example /tmp or
      // /build). Only a known installed Skill is consumed as a command.
      if (skill == null) continue;
      if (!_loadedSessionSkillIds.contains(skill.pack.id)) {
        final body = _skillStore.readBody(skill.pack, maxChars: 8000);
        if (body == null || body.trim().isEmpty) {
          FloatingToast.show(context, 'Skill 不可读取：/$name',
              tone: ToastTone.warning);
          return null;
        }
        _chat.addSessionSkillInstruction(
          id: skill.pack.id,
          name: skill.metadata.name,
          instruction: '## 当前会话已加载 Skill：${skill.metadata.name}\n\n$body',
        );
        if (mounted) {
          _rebuild(() => _loadedSessionSkillIds.add(skill.pack.id));
        }
      }
      recognized.add(name);
    }
    if (recognized.isEmpty) return input;
    return removeSlashSkillCommands(input, recognized);
  }
}
