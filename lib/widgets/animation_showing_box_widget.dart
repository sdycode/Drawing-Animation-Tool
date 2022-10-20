import 'dart:developer';

import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/get_interpolated_point.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/points_to_offsets.dart';
import 'package:animated_icon_demo/extensions.dart';
import 'package:animated_icon_demo/widgets/animated_paint.dart';
import 'package:flutter/material.dart';

class AnimationShowingBoxWidget extends StatefulWidget {
  AnimationShowingBoxWidget({Key? key}) : super(key: key);

  @override
  State<AnimationShowingBoxWidget> createState() =>
      _AnimationShowingBoxWidgetState();
}

late AnimationController animationController;

class _AnimationShowingBoxWidgetState extends State<AnimationShowingBoxWidget>
    with TickerProviderStateMixin {
  @override
  void initState() {
    animationController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3000));
    // TODO: implement initState
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    Size biggerSize = Size(40.sh(context), 40.sh(context));
    return StatefulBuilder(
        builder: (BuildContext context, StateSetter animState) {
      animationController.addListener(() {
        log("animcont ${animationController.value}");
        // for (var i = 0; i < animatingFramePoints.length; i++) {
        //   Point interPoint = getInterPolatedPoint(
        //       animationController.value, frame1Points[i], frame2Points[i]);
        //   animatingFramePoints[i] = interPoint;
        // }
        // if (mounted) {
        //   setState(() {});

        // }
      });
      return Container(
        width: biggerSize.width,
        height: biggerSize.height,
        color: Colors.green.shade100,
        child: Stack(children: [
          ...(List.generate(animatingFramePoints.length, (int i) {
            return Positioned(
                left: animatingFramePoints[i].x,
                top: animatingFramePoints[i].y,
                child: Container(
                  width: 5,
                  height: 5,
                  color: Colors.pink,
                ));
          })),
          AnimatedMyPaint(
            width: biggerSize.width,
            height: biggerSize.height,
            animPoints: pointsToOffsets(animatingFramePoints),
          ),
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
