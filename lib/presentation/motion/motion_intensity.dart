/// 动效强度（S1）：在分档预算之上，按用户偏好统一放大各装饰效果。
///
/// 只影响「强度」（透明度、尺寸、位移、数量），不影响是否开启——
/// 开关仍由 [MotionBudget] 的分档决定，reduced / off 下依旧全部关闭。
enum MotionIntensity {
  /// 轻盈：原始参数（M1–M10 的设计值，默认）。
  ///
  /// L0 起动效重心转向弹簧与形变，装饰光效默认弱化为轻盈。
  subtle,

  /// 标准：约 1.5 倍。
  standard,

  /// 鲜明：约 2 倍。
  vivid;

  double get gain => switch (this) {
        MotionIntensity.subtle => 1.0,
        MotionIntensity.standard => 1.5,
        MotionIntensity.vivid => 2.0,
      };

  String get label => switch (this) {
        MotionIntensity.subtle => '轻盈',
        MotionIntensity.standard => '标准',
        MotionIntensity.vivid => '鲜明',
      };

  static MotionIntensity parse(String? value) => MotionIntensity.values
      .firstWhere((e) => e.name == value, orElse: () => MotionIntensity.subtle);
}

/// 按增益放大一个基础值：`base × (1 + (gain − 1) × k)`。
/// [k] 为该效果对强度的敏感度（0 = 不随强度变化，1 = 与增益同比）。
double amplify(double base, double gain, double k) =>
    base * (1 + (gain - 1) * k);
