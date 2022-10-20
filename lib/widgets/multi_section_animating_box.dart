import 'dart:developer';

import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/get_interpolated_point.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/points_to_offsets.dart';
import 'package:animated_icon_demo/extensions.dart';
import 'package:animated_icon_demo/widgets/animated_paint.dart';
import 'package:flutter/material.dart';

class MultiSectionAnimationShowingBoxWidget extends StatefulWidget {
  MultiSectionAnimationShowingBoxWidget({Key? key}) : super(key: key);

  @override
  State<MultiSectionAnimationShowingBoxWidget> createState() =>
      _MultiSectionAnimationShowingBoxWidgetState();
}

late AnimationController multianimationController;

class _MultiSectionAnimationShowingBoxWidgetState
    extends State<MultiSectionAnimationShowingBoxWidget>
    with TickerProviderStateMixin {
  @override
  void initState() {
    multianimationController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3000));
    // TODO: implement initState
    super.initState();
  }

  Set set = Set();
  @override
  Widget build(BuildContext context) {
    set.clear();
    log("siss ${animatePointsModels.length}");
    Size biggerSize = Size(40.sh(context), 40.sh(context));
    return StatefulBuilder(
        builder: (BuildContext context, StateSetter animState) {
      multianimationController.addListener(() {
        if (multianimationController.status == AnimationStatus.completed) {
          multianimationController.stop();

          multianimationController.reset();
        }
        log("progress value ${set.length}");
        set.add(multianimationController.value);
        for (var j = 0; j < animatePointsModels.length; j++) {
          for (var i = 0;
              i < animatePointsModels[j].animatingFramePoints.length;
              i++) {
            Point interPoint = getInterPolatedPoint(
                multianimationController.value,
                animatePointsModels[j].frame1Points[i],
                animatePointsModels[j].frame2Points[i]);
            // log("point in progress : ${multianimationController.value} :  modelno $i : @ $j : ${interPoint.x} :${interPoint.y} ");
            animatePointsModels[j].animatingFramePoints[i] = interPoint;
          }
        }
        // for (var i = 0; i < animatingFramePoints.length; i++) {
        //   Point interPoint = getInterPolatedPoint(
        //       animationController.value, frame1Points[i], frame2Points[i]);
        //   animatingFramePoints[i] = interPoint;
        // }
        if (mounted) {
          setState(() {});
        }
      });
      return Container(
        width: biggerSize.width,
        height: biggerSize.height,
        color: Colors.green.shade100,
        child: Stack(children: [
          // if (animatePointsModels.length > 0)
          //   AnimatedMyPaint(
          //     width: biggerSize.width,
          //     height: biggerSize.height,
          //     animPoints:
          //         pointsToOffsets(animatePointsModels[0].animatingFramePoints),
          //   ),
          // if (animatePointsModels.length > 1)
          //   AnimatedMyPaint(
          //     width: biggerSize.width,
          //     height: biggerSize.height,
          //     animPoints:
          //         pointsToOffsets(animatePointsModels[1].animatingFramePoints),
          //   )
          ...(List.generate(animatePointsModels.length, (j) {
            return AnimatedMyPaint(
              width: biggerSize.width,
              height: biggerSize.height,
              animPoints:
                  pointsToOffsets(animatePointsModels[j].animatingFramePoints),
            );
          })),
          // ...(List.generate(animatingFramePoints.length, (int i) {
          //   return Positioned(
          //       left: animatingFramePoints[i].x,
          //       top: animatingFramePoints[i].y,
          //       child: Container(
          //         width: 5,
          //         height: 5,
          //         color: Colors.pink,
          //       ));
          // })),
          // AnimatedMyPaint(
          //   width: biggerSize.width,
          //   height: biggerSize.height,
          //   animPoints: pointsToOffsets(animatingFramePoints),
          // ),
          // ...(List.generate(animatingFramePoints.length, (int i) {
          //   return Positioned(
          //       left: animatingFramePoints[i].x,
          //       top: animatingFramePoints[i].y,
          //       child: Container(
          //         width: 5,
          //         height: 5,
          //         color: Colors.pink,
          //       ));
          // }))
        ]),
      );
    });
  }
}
