import 'package:flutter/material.dart';

Color settingsBgColor(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
}

Color settingsCardColor(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? const Color(0xFF1C1C1E) : Colors.white;
}

Color settingsDividerColor(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? const Color(0xFF38383A) : const Color(0xFFE5E5EA);
}

Color settingsMutedColor(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70);
}

class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle(this.title, {super.key, this.padding});
  final String title;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: settingsMutedColor(context),
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}

class SettingsGroupCard extends StatelessWidget {
  const SettingsGroupCard({
    super.key,
    required this.children,
    this.padding,
    this.margin,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: margin ?? const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: settingsCardColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xFF2C2C2E) : const Color(0x0F000000),
            width: 0.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key, this.indent = 54, this.endIndent = 0});
  final double indent;
  final double endIndent;

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 0.5,
      thickness: 0.5,
      indent: indent,
      endIndent: endIndent,
      color: settingsDividerColor(context),
    );
  }
}

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    this.icon,
    this.iconColor,
    this.iconGlyphColor = Colors.white,
    this.leading,
    required this.title,
    this.titleColor,
    this.subtitle,
    this.subtitleColor,
    this.trailingText,
    this.trailingTextColor,
    this.trailingBadge,
    this.trailingWidget,
    this.showChevron = true,
    this.selected,
    this.onTap,
    this.contentPadding,
  });

  final IconData? icon;
  final Color? iconColor;
  final Color iconGlyphColor;
  final Widget? leading;
  final String title;
  final Color? titleColor;
  final String? subtitle;
  final Color? subtitleColor;
  final String? trailingText;
  final Color? trailingTextColor;
  final Widget? trailingBadge;
  final Widget? trailingWidget;
  final bool showChevron;
  final bool? selected;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget? leadingWidget = leading;
    if (leadingWidget == null && icon != null) {
      leadingWidget = Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: iconColor ?? const Color(0xFF007AFF),
          borderRadius: BorderRadius.circular(7),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: iconGlyphColor, size: 17),
      );
    }

    final hasChevron = showChevron &&
        onTap != null &&
        trailingWidget == null &&
        (selected == null);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: contentPadding ??
              const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              if (leadingWidget != null) ...[
                leadingWidget,
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: titleColor ??
                            (isDark ? Colors.white : const Color(0xFF000000)),
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 11,
                          color: subtitleColor ??
                              (isDark
                                  ? const Color(0xFF8E8E93)
                                  : const Color(0xFF8E8E93)),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailingWidget != null) ...[
                trailingWidget!,
              ] else ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (trailingBadge != null) trailingBadge!,
                    if (trailingText != null && trailingText!.isNotEmpty) ...[
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Text(
                          trailingText!,
                          style: TextStyle(
                            fontSize: 14,
                            color: trailingTextColor ??
                                (isDark
                                    ? const Color(0xFF8E8E93)
                                    : const Color(0xFF8E8E93)),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    if (selected != null)
                      if (selected == true)
                        const Icon(
                          Icons.check_rounded,
                          size: 20,
                          color: Color(0xFF007AFF),
                        )
                      else
                        const SizedBox(width: 20),
                    if (hasChevron)
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: isDark
                            ? const Color(0xFF545458)
                            : const Color(0xFFC7C7CC),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor = const Color(0xFF34C759),
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeTrackColor: activeColor,
          activeThumbColor: Colors.white,
        ),
      ),
    );
  }
}
