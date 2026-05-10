import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:Iris/iris_assistant/mascot_controller.dart';

class IrisSelectionArea extends StatelessWidget {
  final Widget child;
  final Function(String text)? onActionSelected; // 点击自定义功能的回调

  const IrisSelectionArea({
    super.key,
    required this.child,
    this.onActionSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      contextMenuBuilder: (context, selectableRegionState) {
        final buttonItems = selectableRegionState.contextMenuButtonItems;

        // 3. 插入你的自定义功能按钮
        buttonItems.insert(0, ContextMenuButtonItem(
          label: '询问 Iris',
          onPressed: () async {
            selectableRegionState.copySelection(SelectionChangedCause.toolbar);
            selectableRegionState.hideToolbar();
            await Future.delayed(const Duration(milliseconds: 100));
            final data = await Clipboard.getData(Clipboard.kTextPlain);
            if (data != null && data.text != null && data.text!.isNotEmpty) {
              MascotController().activeMascot(data.text!);
            }
          },
        ));

        // 4. 返回适配当前平台的工具栏
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: selectableRegionState.contextMenuAnchors,
          buttonItems: buttonItems,
        );
      },
      child: child,
    );
  }
}