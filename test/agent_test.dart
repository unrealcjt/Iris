

import 'package:Iris/iris_assistant/iris_tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  IrisTools irisTools = IrisTools();

  test('测试获取技能', () async {
    TestWidgetsFlutterBinding.ensureInitialized();

    String skill = await irisTools.loadSkillDocumentFromFolder("searchWeb");
    print(skill);
  });
}