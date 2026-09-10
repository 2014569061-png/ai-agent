import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// 底部导航：选中项使用品牌浅色胶囊指示（平面，无光晕/模糊）。
/// 图标与标签随选中态切换颜色。
class ImmersiveNavigationBar extends StatelessWidget {
  const ImmersiveNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.height = 68,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<ImmersiveNavigationDestination> destinations;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppTheme.semanticOf(context);

    return SizedBox(
      height: height,
      child: Row(
        children: List.generate(destinations.length, (i) {
          final selected = i == selectedIndex;
          final item = destinations[i];
          return Expanded(
            child: _NavItem(
              key: ValueKey('nav-${item.label}-$i'),
              icon: selected ? (item.selectedIcon ?? item.icon) : item.icon,
              label: item.label,
              selected: selected,
              color: colors,
              primary: theme.colorScheme.primary,
              onTap: () {
                if (!selected) onDestinationSelected(i);
              },
            ),
          );
        }),
      ),
    );
  }
}

class ImmersiveNavigationDestination {
  const ImmersiveNavigationDestination({
    required this.icon,
    required this.label,
    this.selectedIcon,
  });

  final IconData icon;
  final IconData? selectedIcon;
  final String label;
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.color,
    required this.primary,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final AppSemanticColors color;
  final Color primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 28,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              if (selected)
                Container(
                  width: 48,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppPalette.darkBrandSoft
                        : AppPalette.lightBrandSoft,
                    borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                  ),
                ),
              Icon(
                icon,
                size: 22,
                color: selected ? AppPalette.brand : color.textMuted,
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: selected ? AppPalette.brand : color.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
