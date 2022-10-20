import 'dart:developer';

import 'package:animated_icon_demo/Landscape%20Widgets/animatedDrawingBoardWidget.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/animation_sheet.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/drawing_board_widget.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/Paints/polyline_paint.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/get_interpolated_point.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/numeric%20funtions/getPercentValueForStickPosition.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/numeric%20funtions/get_index_for_new_frame_for_frameposition.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/numeric%20funtions/get_modified_percentvalue_for_preframeno.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/points_to_offsets.dart';
import 'package:animated_icon_demo/enums/enums.dart';
import 'package:animated_icon_demo/extensions.dart';
import 'package:animated_icon_demo/providers/drawing_board_provider.dart';
import 'package:animated_icon_demo/widgets/error/error_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class DrawingBoardBackgroundBox extends StatefulWidget {
  DrawingBoardBackgroundBox({Key? key}) : super(key: key);

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
            DrawingBoardWidget(),
            if (showAnimationBoard == ShowAnimationBoard.show)
              AnimatedDrawingBoardWidget()
          ]),
        ));
  }
}
