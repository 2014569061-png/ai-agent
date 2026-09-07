import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/immersive_effects_controller.dart';

/// 沉浸式底部导航：选中项使用小范围光晕 indicator 而非厚重的实心胶囊色块。
/// 图标/标签随选中态切换颜色，配合淡入的径向光晕表达「选中」。
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
    final effect = ImmersiveEffectsController.resolve(context);
    final glowEnabled = ImmersiveEffectsController.glowEnabled(effect);

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
              glowEnabled: glowEnabled,
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
    required this.glowEnabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final AppSemanticColors color;
  final Color primary;
  final bool glowEnabled;
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
              if (selected && glowEnabled)
                AnimatedOpacity(
                  opacity: 1,
                  duration: AppTokens.durationFast,
                  child: Container(
                    width: 52,
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: RadialGradient(
                        colors: [
                          color.focusGlow.withValues(alpha: .9),
                          color.focusGlow.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              Icon(
                icon,
                size: 23,
                color: selected ? primary : color.textMuted,
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? primary : color.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
