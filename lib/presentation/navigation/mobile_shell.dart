import '../../application/jobs/job_board_providers.dart';
import 'mobile_navigation_scope.dart';
import '../../infrastructure/share/deep_link_service.dart';
import 'assistant_entry_surface.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/chat_controller.dart';
import '../chat/chat_page.dart';
import '../theme/mobile_theme.dart';
import '../jobs/jobs_inbox_page.dart';
import '../projects/project_picker_page.dart';
import '../settings/settings_page.dart';

/// Android/iOS navigation stays independent of the desktop layout, even on
/// tablets. Pages are created on demand; each section owns its navigation stack.
class MobileShell extends ConsumerStatefulWidget {
  const MobileShell({super.key, this.pageBuilders, this.deepLinks});

  /// Embedding/test seam. Production always uses the four existing workflows.
  final List<WidgetBuilder>? pageBuilders;
  final DeepLinkService? deepLinks;

  @override
  ConsumerState<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends ConsumerState<MobileShell> {
  int _index = 0;
  int _pendingCount = 0;
  bool _drawerOpen = false;
  bool _refreshingPending = false;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _drawerBridge = MobileDrawerBridge();
  final _visited = <int>{0};
  final _rootPages = <int, Widget>{};
  final _navigators = List.generate(4, (_) => GlobalKey<NavigatorState>());
  final _canPop = List.filled(4, false);
  final _visibility = List.generate(4, (index) => ValueNotifier(index == 0));
  late DeepLinkService _links;
  @override
  void initState() {
    super.initState();
    _links = widget.deepLinks ?? DeepLinkService.instance;
    _links.addListener(_externalEntry);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshPending());
      if (mounted && (_links.hasPending || _links.hasRejection)) {
        _externalEntry();
      }
    });
  }

  void _externalEntry() {
    if (!mounted) return;
    final warning = _links.takeRejection();
    if (warning != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(warning)));
        }
      });
    }
    if (_links.lastEventAccepted && _links.hasPending && _index != 0) {
      _select(0);
    }
  }

  @override
  void didUpdateWidget(MobileShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final links = widget.deepLinks ?? DeepLinkService.instance;
    if (!identical(links, _links)) {
      _links.removeListener(_externalEntry);
      _links = links;
      _links.addListener(_externalEntry);
    }
  }

  @override
  void dispose() {
    _links.removeListener(_externalEntry);
    _drawerBridge.dispose();
    for (final visibility in _visibility) {
      visibility.dispose();
    }
    super.dispose();
  }

  Future<void> _refreshPending() async {
    if (widget.pageBuilders != null || _refreshingPending || !mounted) return;
    _refreshingPending = true;
    try {
      final board = await ref.read(jobBoardProvider.future);
      final count = (await board.attentionJobs()).length;
      if (mounted && count != _pendingCount) {
        setState(() => _pendingCount = count);
      }
    } catch (_) {
      // Keep navigation available if the local task store cannot be read.
    } finally {
      _refreshingPending = false;
    }
  }

  void _openDrawer() {
    FocusManager.instance.primaryFocus?.unfocus();
    _drawerBridge.refresh();
    _scaffoldKey.currentState?.openDrawer();
  }

  void _select(int index) {
    _scaffoldKey.currentState?.closeDrawer();
    unawaited(_refreshPending());
    for (var i = 0; i < _visibility.length; i++) {
      _visibility[i].value = i == index &&
          !_drawerOpen &&
          (ModalRoute.of(context)?.isCurrent ?? true);
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _visited.add(index);
      _index = index;
    });
  }

  Future<void> _openConversation(String conversationId) async {
    try {
      await ref
          .read(chatControllerProvider.notifier)
          .switchConversationById(conversationId);
      if (mounted) _select(0);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('打开会话失败，请重试')),
      );
    }
  }

  Widget _page(BuildContext context, int index) {
    return _rootPages.putIfAbsent(index, () => _createPage(context, index));
  }

  Widget _createPage(BuildContext context, int index) {
    final builders = widget.pageBuilders;
    if (builders != null) {
      assert(builders.length == 4);
      return builders[index](context);
    }
    return switch (index) {
      0 => const ChatPage(),
      1 => JobsInboxPage(
          onConversationSelected: (value) =>
              unawaited(_openConversation(value))),
      2 => ProjectPickerPage(onProjectSelected: () => _select(0)),
      _ => const SettingsPage(),
    };
  }

  void _navigationChanged(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final canPop = _navigators[index].currentState?.canPop() ?? false;
      if (_canPop[index] != canPop) setState(() => _canPop[index] = canPop);
    });
  }

  @override
  Widget build(BuildContext context) {
    final parentRoute = ModalRoute.of(context);
    for (var i = 0; i < _visibility.length; i++) {
      _visibility[i].value =
          i == _index && !_drawerOpen && (parentRoute?.isCurrent ?? true);
    }

    if (widget.pageBuilders == null) {
      ref.listen(chatControllerProvider.select((s) => (s.running, s.paused)),
          (_, __) => unawaited(_refreshPending()));
    }
    return MobileNavigationScope(
      selectedIndex: _index,
      pendingCount: _pendingCount,
      drawerBridge: _drawerBridge,
      openDrawer: _openDrawer,
      selectDestination: _select,
      child: PopScope<Object?>(
        canPop: !_drawerOpen && _index == 0 && !_canPop[_index],
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (_drawerOpen) {
            _scaffoldKey.currentState?.closeDrawer();
            return;
          }
          if (MediaQuery.viewInsetsOf(context).bottom > 0) {
            FocusManager.instance.primaryFocus?.unfocus();
            return;
          }
          final navigator = _navigators[_index].currentState;
          if (navigator?.canPop() ?? false) {
            // maybePop respects a child's unsaved-edit PopScope.
            unawaited(navigator!.maybePop());
          } else if (_index != 0) {
            _select(0);
          }
        },
        child: Scaffold(
          key: _scaffoldKey,
          onDrawerChanged: (open) {
            setState(() => _drawerOpen = open);
            if (open) unawaited(_refreshPending());
          },
          drawerScrimColor: Colors.black.withValues(alpha: .16),
          drawer: ListenableBuilder(
            listenable: _drawerBridge,
            builder: (context, _) =>
                _drawerBridge.builder?.call(context) ??
                const Drawer(
                    child: SafeArea(
                        child: Padding(
                            padding: EdgeInsets.all(16),
                            child: MobilePrimaryNavigation()))),
          ),
          resizeToAvoidBottomInset: false,
          body: MobileCanvas(
              child: IndexedStack(
            index: _index,
            children: List.generate(4, (index) {
              if (!_visited.contains(index)) return const SizedBox.shrink();
              return TickerMode(
                enabled: index == _index,
                child: AssistantEntrySurface(
                    visibility: _visibility[index],
                    parentRoute: parentRoute,
                    child: Navigator(
                      key: _navigators[index],
                      observers: [
                        _TabNavigationObserver(() => _navigationChanged(index))
                      ],
                      onGenerateRoute: (_) => MaterialPageRoute<void>(
                        builder: (context) => _page(context, index),
                      ),
                    )),
              );
            }),
          )),
        ),
      ),
    );
  }
}

class _TabNavigationObserver extends NavigatorObserver {
  _TabNavigationObserver(this.onChanged);
  final VoidCallback onChanged;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      onChanged();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      onChanged();
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      onChanged();
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      onChanged();
}

/// Platform, not screen width, selects the phone entrypoint.
bool usesMobileShell(TargetPlatform platform) =>
    platform == TargetPlatform.android || platform == TargetPlatform.iOS;
