import 'dart:developer';

import 'package:animated_icon_demo/Landscape%20Widgets/animation_sheet.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';

import 'package:animated_icon_demo/Paints/polyline_paint.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/Point%20methods/get_animatedpoints.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/points_to_offsets.dart';
import 'package:animated_icon_demo/widgets/animation_showing_box_widget.dart';

import 'package:flutter/material.dart';

class AnimatedDrawingBoardWidget extends StatefulWidget {
  const AnimatedDrawingBoardWidget({Key? key}) : super(key: key);

  @override
  State<AnimatedDrawingBoardWidget> createState() =>
      _AnimatedDrawingBoardWidgetState();
}

class _AnimatedDrawingBoardWidgetState
    extends State<AnimatedDrawingBoardWidget> {
  @override
  Widget build(BuildContext context) {
    List<List<Point>> allsectionSPoints = getAnimatedPoints(context);
    List<int> indexes = [];
    for (int iconNo = 0;
        iconNo < projectList[currentProjectNo].iconSections.length;
        iconNo++) {
      // log("iconSectionIndexesToIncludeInAnimationList [$iconNo] : ${iconSectionIndexesToIncludeInAnimationList}");
      if (!iconSectionIndexesToIncludeInAnimationList.contains(iconNo)) {
        continue;
      }
      indexes.add(iconNo);
    }

    log("allsectionSPoints ${allsectionSPoints.length} $indexes");
    return Positioned(
      left: drawingBoardPosition.dx + drawingBoardSize.width + 50,
      top: drawingBoardPosition.dy,
      child: 
      
      allsectionSPoints.isEmpty
          ? 
          Container()
          // Center(
          //     child: Text(
          //       "No Points",
          //       style: Theme.of(context).textTheme.bodyLarge,
          //     ),
          //   )
          : Container(
              width: drawingBoardSize.width,
              height: drawingBoardSize.height,
              color: Colors.orange.shade200,
              child: Stack(
                children: [
                  ...(List.generate(
                    allsectionSPoints.length,
                    (iconIndex) => CustomPaint(
                      size: Size(
                        biggerSize.width.truncate().toDouble(),
                        biggerSize.height.truncate().toDouble(),
                      ),
                      painter: PointsLinePaint(
                          pointsToOffsets(allsectionSPoints[iconIndex]),
                          iconsecIndex: iconIndex,
                          indexes:indexes
                          ),
                    ),
                  )),

                 
                ],
              )),
    );
  }
}
