import 'package:flutter/material.dart';

/// NEXUS Agent 统一品牌标志。
///
/// 产品界面、头像和启动页均通过这个组件引用同一份主视觉素材，避免
/// 使用不同的机器人/星星图标造成品牌识别不一致。
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 48,
    this.withGlow = false,
    this.padding = 0,
  });

  static const assetPath = 'assets/branding/nexus_mark.png';

  final double size;
  final bool withGlow;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'NEXUS Agent Logo',
    );

    return Padding(padding: EdgeInsets.all(padding), child: image);
  }
}
