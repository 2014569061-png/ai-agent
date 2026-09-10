import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/mojibake_repair.dart';

void main() {
  test('repairs known legacy Chinese mojibake without changing normal text',
      () {
    expect(MojibakeRepair.repair('閫氱敤鍔╂墜'), '通用助手');
    expect(MojibakeRepair.repair('鏂颁細'), '新会话');
    expect(MojibakeRepair.repair('正常中文内容'), '正常中文内容');
    expect(MojibakeRepair.changed('閫氱敤鍔╂墜'), isTrue);
    expect(MojibakeRepair.changed('正常中文内容'), isFalse);
  });
}
