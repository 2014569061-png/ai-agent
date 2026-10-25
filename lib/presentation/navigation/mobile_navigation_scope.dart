import 'package:flutter/material.dart';

import '../widgets/nexus_home_visuals.dart';

/// The shell owns navigation; chat supplies its existing session actions so
/// drawer history uses the same draft/attachment transitions as the chat page.
class MobileDrawerBridge extends ChangeNotifier {
  WidgetBuilder? builder;
  bool _disposed = false;

  void bind(WidgetBuilder? value) {
    builder = value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) notifyListeners();
    });
  }

  void refresh() => notifyListeners();

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class MobileNavigationScope extends InheritedWidget {
  const MobileNavigationScope({
    super.key,
    required this.selectedIndex,
    required this.openDrawer,
    required this.selectDestination,
    required this.pendingCount,
    required this.drawerBridge,
    required super.child,
  });

  final MobileDrawerBridge drawerBridge;
  final int selectedIndex;
  final int pendingCount;
  final VoidCallback openDrawer;
  final ValueChanged<int> selectDestination;

  static MobileNavigationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MobileNavigationScope>();

  @override
  bool updateShouldNotify(MobileNavigationScope oldWidget) =>
      selectedIndex != oldWidget.selectedIndex ||
      pendingCount != oldWidget.pendingCount ||
      drawerBridge != oldWidget.drawerBridge;
}

class MobileNavigationMenuButton extends StatelessWidget {
  const MobileNavigationMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final navigation = MobileNavigationScope.maybeOf(context)!;
    return IconButton(
      tooltip: navigation.pendingCount > 0
          ? '打开导航菜单，${navigation.pendingCount} 项待处理'
          : '打开导航菜单',
      onPressed: navigation.openDrawer,
      icon: Badge(
        isLabelVisible: navigation.pendingCount > 0,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const NexusHomeIcon(NexusHomeSymbol.menu),
      ),
    );
  }
}

/// Also used by shell embedders that do not provide a chat page.
class MobilePrimaryNavigation extends StatelessWidget {
  const MobilePrimaryNavigation(
      {super.key,
      this.destinations = const [0, 1, 2, 3],
      this.subtleSelection = false});

  final List<int> destinations;
  final bool subtleSelection;

  @override
  Widget build(BuildContext context) {
    final navigation = MobileNavigationScope.maybeOf(context)!;
    final colors = Theme.of(context).colorScheme;
    const labels = ['助手', '任务', '工作区', '设置'];
    const icons = [
      Icons.chat_bubble_outline_rounded,
      Icons.task_alt_rounded,
      Icons.folder_outlined,
      Icons.tune_rounded,
    ];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (final index in destinations)
        Padding(
          padding: EdgeInsets.symmetric(vertical: subtleSelection ? 0 : 2),
          child: Semantics(
            selected: navigation.selectedIndex == index,
            child: ListTile(
              key: ValueKey('mobile-destination-$index'),
              minTileHeight: 48,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              minLeadingWidth: 20,
              horizontalTitleGap: 12,
              minVerticalPadding: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              selected: navigation.selectedIndex == index,
              selectedTileColor: subtleSelection
                  ? Colors.transparent
                  : colors.primary.withValues(alpha: .08),
              selectedColor: colors.primary,
              iconColor: colors.onSurfaceVariant,
              leading: Icon(icons[index], size: 20),
              title: Text(labels[index],
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w400)),
              trailing: index == 1 && navigation.pendingCount > 0
                  ? Text('${navigation.pendingCount} 待处理',
                      style: TextStyle(fontSize: 12, color: colors.primary))
                  : null,
              onTap: () => navigation.selectDestination(index),
            ),
          ),
        ),
    ]);
  }
}
