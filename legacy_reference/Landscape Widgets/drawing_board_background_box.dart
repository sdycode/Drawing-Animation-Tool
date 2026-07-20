
import 'package:animated_icon_demo/Landscape%20Widgets/animatedDrawingBoardWidget.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/drawing_board_widget.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/enums/enums.dart';
import 'package:animated_icon_demo/extensions.dart';
import 'package:animated_icon_demo/providers/drawing_board_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class DrawingBoardBackgroundBox extends StatefulWidget {
  const DrawingBoardBackgroundBox({Key? key}) : super(key: key);

  @override
  State<DrawingBoardBackgroundBox> createState() =>
      _DrawingBoardBackgroundBoxState();
}

class _DrawingBoardBackgroundBoxState extends State<DrawingBoardBackgroundBox> {
  @override
  Widget build(BuildContext context) {
    DrawingBoardProvider drawingBoardProvider =
        Provider.of<DrawingBoardProvider>(
      context,
    );
    return Positioned(
        top: topbarHeight,
        left: drawingComponentsTreeBoxWidth,
        child: Container(
          width: 100.sw(context) -
              drawingComponentsTreeBoxWidth -
              editFeaturesPalleteBoxWidth,
          height: 100.sh(context) - topbarHeight,
          color: Colors.purple.shade100.withAlpha(150),
          child: Stack(children: [
            const DrawingBoardWidget(),
            if (showAnimationBoard == ShowAnimationBoard.show)
              const AnimatedDrawingBoardWidget()
          ]),
        ));
  }
}
