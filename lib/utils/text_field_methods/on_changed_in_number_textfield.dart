import 'dart:developer';

import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/controllers/text_controllers/text_controllers.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/enums/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/editable_text.dart';

void onChangedInNumberTextfield(String text, TextEditingController controller) {
  log("onChangedInNumberTextfield $text / ${controller.text}");
  if (componentSelectedTypeInTree == ComponentSelectedTypeInTree.drawingBoard) {
    if (controller == TextControllers.drawingaBoard_Y_posController) {
      if (checkStringCanBeCastedToDouble(text)) {
        drawingBoardPosition = Offset(
          drawingBoardPosition.dx,
          double.parse(text),
        );
      }
    } else if (controller == TextControllers.drawingaBoard_X_posController) {
      if (checkStringCanBeCastedToDouble(text)) {
        drawingBoardPosition = Offset(
          double.parse(text),
          drawingBoardPosition.dy,
        );
      }
    }
  } else {
    if (controller == TextControllers.shape_angle_Controller) {
      log("onchangedno controller ${controller.text}");
      if (checkStringCanBeCastedToDouble(text)) {
        finalAngle = double.parse(text);
      }
    }
  }
}
// if (componentSelectedTypeInTree ==
//     ComponentSelectedTypeInTree.drawingBoard) {

//     }
// if (componentSelectedTypeInTree ==
//     ComponentSelectedTypeInTree.drawingObject) {}

bool checkStringCanBeCastedToDouble(String text) {
  if (double.tryParse(text) is double) {
    return true;
  }
  return false;
}
