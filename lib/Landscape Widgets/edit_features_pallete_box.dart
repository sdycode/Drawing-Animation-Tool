import 'dart:developer';

import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/controllers/text_controllers/text_controllers.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/frame%20methods/set_polygon_no_to_current_iconsection.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/paint%20methods/showColorPicker.dart';
import 'package:animated_icon_demo/enums/enums.dart';
import 'package:animated_icon_demo/extensions.dart';
import 'package:animated_icon_demo/providers/drawing_board_provider.dart';
import 'package:animated_icon_demo/providers/edit_pallet_provider.dart';
import 'package:animated_icon_demo/utils/text_field_methods/toggle%20methods/toggleEditShapeVerices.dart';
import 'package:animated_icon_demo/widgets/res/Icons/tap_icon.dart';
import 'package:animated_icon_demo/widgets/text_widgets/textfield_no.dart';
import 'package:animated_icon_demo/widgets/text_widgets/textfiledno_with_controller_buttons.dart';
import 'package:animated_icon_demo/widgets/text_widgets/textstyle1.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class EditFeaturesPalleteBox extends StatefulWidget {
  EditFeaturesPalleteBox({Key? key}) : super(key: key);

  @override
  State<EditFeaturesPalleteBox> createState() => _EditFeaturesPalleteBoxState();
}

class _EditFeaturesPalleteBoxState extends State<EditFeaturesPalleteBox> {
  @override
  Widget build(BuildContext context) {
    EditPalletProvider editPalletProvider =
        Provider.of<EditPalletProvider>(context);
    return Positioned(
        top: topbarHeight,
        //
        right: 0,
        // left: 100.sw(context) -editFeaturesPalleteBoxWidth,
        // -editFeaturesPalleteBoxWidth*2,
        child: Stack(
          children: [
            Container(
              margin: EdgeInsets.all(borderMargin),
              width: editFeaturesPalleteBoxWidth,
              // editFeaturesPalleteBoxWidth,
              height: 100.sh(context),
              color: Theme.of(context).primaryColorDark,
              child: getEditPalletForSelectedItem(),
            ),
            GestureDetector(
              onPanUpdate: (d) {
                editFeaturesPalleteBoxWidth -= d.delta.dx;
                if (editFeaturesPalleteBoxWidth < 250) {
                  editFeaturesPalleteBoxWidth = 250;
                }
                if (editFeaturesPalleteBoxWidth > 400) {
                  editFeaturesPalleteBoxWidth = 400;
                }
                editPalletProvider.updateUI();
              },
              child: Container(
                width: 4,
                height: 100.sh(context),
                color: Colors.grey,
              ),
            )
          ],
        ));
  }

  Widget getEditPalletForSelectedItem() {
    if (componentSelectedTypeInTree ==
        ComponentSelectedTypeInTree.drawingBoard) {
      return EditPalletForDrawingBoard();
    }
    return EditPalletForDrawingShape();
    tempWidgetToShowPointsCoordinatesforShape(context);
  }
}

Widget tempWidgetToShowPointsCoordinatesforShape(BuildContext context) {
  return Container(
    width: editFeaturesPalleteBoxWidth,
    // editFeaturesPalleteBoxWidth,
    height: 100.sh(context), color: Theme.of(context).primaryColorDark,
    child: ListView.separated(
        separatorBuilder: (context, index) {
          return Divider();
        },
        shrinkWrap: true,
        itemCount: projectList[currentProjectNo]
            .iconSections[currentIconSectionNo]
            .frames
            .length,
        itemBuilder: (c, fi) {
          ScrollController controller = ScrollController();
          return Container(
              height: 40,
              width: editFeaturesPalleteBoxWidth,
              child:

                  //

                  Scrollbar(
                controller: controller,
                child: ListView.builder(
                    controller: controller,
                    scrollDirection: Axis.horizontal,
                    itemCount: projectList[currentProjectNo]
                        .iconSections[currentIconSectionNo]
                        .frames[fi]
                        .singleFrameModel
                        .points
                        .length,
                    itemBuilder: (cc, pi) {
                      Point e = projectList[currentProjectNo]
                          .iconSections[currentIconSectionNo]
                          .frames[fi]
                          .singleFrameModel
                          .points[pi];
                      return Text(
                        "[ ${e.x.toStringAsFixed(2)} / ${e.y.toStringAsFixed(2)} ]",
                        style: TextStyle(color: Colors.white),
                      );
                    }),
              ));
        }),
  );
}

class EditPalletForDrawingShape extends StatelessWidget {
  EditPalletForDrawingShape({Key? key}) : super(key: key);

  late EditPalletProvider editPalletProvider;
  late DrawingBoardProvider drawingBoardProvider;
  @override
  Widget build(BuildContext context) {
    editPalletProvider = Provider.of<EditPalletProvider>(context);

    drawingBoardProvider = Provider.of<DrawingBoardProvider>(
      context,
    );
    return Container(
      width: editFeaturesPalleteBoxWidth,
      margin: EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: RawChip(
              onPressed: () {
                showPoints = !showPoints;
                editPalletProvider.updateUI();
                drawingBoardProvider.updateUI();
                // provData.updateUI();
              },
              label: Text("Show Points"),
              // onDeleted: (){ toggleShowAnimationBoard();
              //         provData.updateUI();},
              avatar: Container(
                margin: EdgeInsets.only(right: 2, left: 2),
                child: Padding(
                  padding: const EdgeInsets.only(left: 2, right: 2),
                  child: TapIcon(
                      onTap: () {
                      //  showPoints
                      },
                      icon: Icon(
                      showPoints
                            ? Icons.check_circle
                            : Icons.check_circle_outline_outlined,
                        size: 20,
                      )),
                ),
              ),
            ),
          ),

            Padding(
              padding: const EdgeInsets.all(8.0),
              child: RawChip(
              
              onPressed: () {
                 toggleEditShapeVerices();
                      editPalletProvider.updateUI();
                      drawingBoardProvider.updateUI();
              },
              label: Text("Edit Vertices"),
              // onDeleted: (){ toggleShowAnimationBoard();
              //         provData.updateUI();},
              avatar: Container(
                margin: EdgeInsets.only(right: 2, left: 2),
                child: Padding(
                  padding: const EdgeInsets.only(left: 2, right: 2),
                  child: TapIcon(
                      onTap: () {
                      //  showPoints
                      },
                      icon: Icon(
                      editShapeVertices == EditShapeVertices.shapeVerices
                            ? Icons.check_circle
                            : Icons.check_circle_outline_outlined,
                        size: 20,
                      )),
                ),
              ),
          ),
            ),
          // Row(
          //   children: [
          //     TextWithStyle1(
          //       text: "Edit Vertices",
          //       fontsize: 16,
          //     ),
          //     Spacer(),
          //     TapIcon(
          //         onTap: () {
                  
          //         },
          //         icon: Icon(editShapeVertices == EditShapeVertices.shapeVerices
          //             ? Icons.check_box
          //             : Icons.check_box_outline_blank))
          //   ],
          // ),
          // RotateEditFieldWidget(),

          Container(
              width: double.infinity,
              margin: EdgeInsets.all(8),
              child: ElevatedButton(
                  style: ButtonStyle(
                      backgroundColor: MaterialStateProperty.all(Color(int.parse(
                          "0x${projectList[currentProjectNo].iconSections[currentIconSectionNo].color}")))),
                  onPressed: () {
                    showColorPicker(context, (Color d) {
                      projectList[currentProjectNo]
                              .iconSections[currentIconSectionNo]
                              .color =
                          d.toString().replaceAll(')', '').split('x')[1];
                      editPalletProvider.updateUI();
                      drawingBoardProvider.updateUI();
                      ;
                    },
                        Color(int.parse(
                            "0x${projectList[currentProjectNo].iconSections[currentIconSectionNo].color}")));
                  },
                  child: Text(""))),
          if (drawingObjectType == DrawingObjectType.polygon)
            PolygonNoEditWidget()
          // TextWithStyle1(
          //   text: "Position",
          //   fontsize: 16,
          // ),
          // DrawingBoardPositionFieldWidgetsRow(),
          // TextWithStyle1(
          //   text: "Size",
          //   fontsize: 16,
          // ),
          // DrawingBoardSizeWidgetsRow()
        ],
      ),
    );
  }
}

bool longPressedStarted = false;

class EditPalletForDrawingBoard extends StatefulWidget {
  EditPalletForDrawingBoard({Key? key}) : super(key: key);

  @override
  State<EditPalletForDrawingBoard> createState() =>
      _EditPalletForDrawingBoardState();
}

class _EditPalletForDrawingBoardState extends State<EditPalletForDrawingBoard> {
  @override
  void initState() {
    // TODO: implement initState
    TextControllers.drawingaBoard_X_posController.text =
        drawingBoardPosition.dx.toStringAsFixed(2);
    TextControllers.drawingaBoard_Y_posController.text =
        drawingBoardPosition.dy.toStringAsFixed(2);
    TextControllers.drawingaBoard_width_Controller.text =
        drawingBoardSize.width.toStringAsFixed(2);
    TextControllers.drawingaBoard_height_posController.text =
        drawingBoardSize.height.toStringAsFixed(2);
    super.initState();
  }

  late EditPalletProvider editPalletProvider;
  late DrawingBoardProvider drawingBoardProvider;
  @override
  Widget build(BuildContext context) {
    editPalletProvider = Provider.of<EditPalletProvider>(context);
    // log("editPalletProvider updated ");
    drawingBoardProvider =
        Provider.of<DrawingBoardProvider>(context, listen: false);
    return Container(
      width: editFeaturesPalleteBoxWidth,
      margin: EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextWithStyle1(
            text: "Position",
            fontsize: 16,
          ),
          DrawingBoardPositionFieldWidgetsRow(),
          TextWithStyle1(
            text: "Size",
            fontsize: 16,
          ),
          DrawingBoardSizeWidgetsRow()
        ],
      ),
    );
  }
}

class PolygonNoEditWidget extends StatelessWidget {
  const PolygonNoEditWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    EditPalletProvider editPalletProvider =
        Provider.of<EditPalletProvider>(context);

    DrawingBoardProvider drawingBoardProvider =
        Provider.of<DrawingBoardProvider>(context, listen: true);
    return GestureDetector(
      onTap: () {
        log("tapped ");
      },
      onPanUpdate: (d) {
        // log("onPanUpdate width ${d.delta} / ${TextControllers.drawingaBoard_width_Controller.text}");

        if (d.delta.dy.sign < 0) {
          noOfSidesOfPolygon++;
        } else {
          noOfSidesOfPolygon--;
          if (noOfSidesOfPolygon < 3) {
            noOfSidesOfPolygon = 3;
          }
        }
        set_polygon_no_to_current_iconsection();
        TextControllers.polygon_no_Controller.text =
            noOfSidesOfPolygon.toString();
        editPalletProvider.updateUI();
        drawingBoardProvider.updateUI();
      },
      child: TextWithTextField(
        controller: TextControllers.polygon_no_Controller,
        textFieldTitle: "Sides",
        onTapUp: () {
          noOfSidesOfPolygon++;
          set_polygon_no_to_current_iconsection();
          TextControllers.polygon_no_Controller.text =
              noOfSidesOfPolygon.toString();
          editPalletProvider.updateUI();
          drawingBoardProvider.updateUI();
        },
        onTapDown: () {
          noOfSidesOfPolygon--;
          if (noOfSidesOfPolygon < 3) {
            noOfSidesOfPolygon = 3;
          }
          set_polygon_no_to_current_iconsection();
          TextControllers.polygon_no_Controller.text =
              noOfSidesOfPolygon.toString();
          ;
          editPalletProvider.updateUI();
          drawingBoardProvider.updateUI();
        },
      ),
    );
  }
}

// class RotateEditFieldWidget extends StatelessWidget {
//   const RotateEditFieldWidget({Key? key}) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     EditPalletProvider editPalletProvider =
//         Provider.of<EditPalletProvider>(context);

//     DrawingBoardProvider drawingBoardProvider =
//         Provider.of<DrawingBoardProvider>(context, listen: true);
//     return GestureDetector(
//       onTap: () {
//         log("tapped ");
//       },
//       onPanUpdate: (d) {
//         // log("onPanUpdate width ${d.delta} / ${TextControllers.drawingaBoard_width_Controller.text}");
//         finalAngle += 0.02 * (d.delta.dy.sign);

//         TextControllers.shape_angle_Controller.text =
//             finalAngle.toStringAsFixed(2);

//         editPalletProvider.updateUI();
//         drawingBoardProvider.updateUI();
//       },
//       child: TextWithTextField(
//         controller: TextControllers.shape_angle_Controller,
//         textFieldTitle: "Angle",
//         onTapUp: () {
//           finalAngle += 0.1;

//           TextControllers.shape_angle_Controller.text =
//               finalAngle.toStringAsFixed(2);
//           editPalletProvider.updateUI();
//           drawingBoardProvider.updateUI();
//         },
//         onTapDown: () {
//           finalAngle -= 0.1;

//           TextControllers.shape_angle_Controller.text =
//               finalAngle.toStringAsFixed(2);
//           editPalletProvider.updateUI();
//           drawingBoardProvider.updateUI();
//           editPalletProvider.updateUI();
//           drawingBoardProvider.updateUI();
//         },
//       ),
//     );
//   }
// }

class DrawingBoardSizeWidgetsRow extends StatelessWidget {
  const DrawingBoardSizeWidgetsRow({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    EditPalletProvider editPalletProvider =
        Provider.of<EditPalletProvider>(context);

    DrawingBoardProvider drawingBoardProvider =
        Provider.of<DrawingBoardProvider>(context, listen: false);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        GestureDetector(
          onTap: () {
            log("tapped ");
          },
          onPanUpdate: (d) {
            // log("onPanUpdate width ${d.delta} / ${TextControllers.drawingaBoard_width_Controller.text}");
            drawingBoardSize = Size(
                drawingBoardSize.width + d.delta.dy, drawingBoardSize.height);

            TextControllers.drawingaBoard_width_Controller.text =
                drawingBoardSize.width.toStringAsFixed(2);

            editPalletProvider.updateUI();
            drawingBoardProvider.updateUI();
          },
          child: TextWithTextField(
            controller: TextControllers.drawingaBoard_width_Controller,
            textFieldTitle: "W",
            onTapUp: () {
              drawingBoardSize =
                  Size(drawingBoardSize.width + 1, drawingBoardSize.height);

              TextControllers.drawingaBoard_width_Controller.text =
                  drawingBoardSize.width.toStringAsFixed(2);
              editPalletProvider.updateUI();
              drawingBoardProvider.updateUI();
            },
            onTapDown: () {
              drawingBoardSize =
                  Size(drawingBoardSize.width - 1, drawingBoardSize.height);

              TextControllers.drawingaBoard_width_Controller.text =
                  drawingBoardSize.width.toStringAsFixed(2);
              editPalletProvider.updateUI();
              drawingBoardProvider.updateUI();
            },
          ),
        ),
        GestureDetector(
          onPanUpdate: (d) {
            drawingBoardSize = Size(
                drawingBoardSize.width, drawingBoardSize.height + d.delta.dy);

            TextControllers.drawingaBoard_height_posController.text =
                drawingBoardSize.height.toStringAsFixed(2);
            editPalletProvider.updateUI();
            drawingBoardProvider.updateUI();
          },
          child: TextWithTextField(
            controller: TextControllers.drawingaBoard_height_posController,
            textFieldTitle: "H",
            onTapUp: () {
              drawingBoardSize =
                  Size(drawingBoardSize.width, drawingBoardSize.height + 1);

              TextControllers.drawingaBoard_height_posController.text =
                  drawingBoardSize.width.toStringAsFixed(2);
              editPalletProvider.updateUI();
              drawingBoardProvider.updateUI();
            },
            onTapDown: () {
              drawingBoardSize =
                  Size(drawingBoardSize.width, drawingBoardSize.height - 1);

              TextControllers.drawingaBoard_height_posController.text =
                  drawingBoardSize.height.toStringAsFixed(2);
              editPalletProvider.updateUI();
              drawingBoardProvider.updateUI();
            },
          ),
        )
      ],
    );
  }
}

class DrawingBoardPositionFieldWidgetsRow extends StatelessWidget {
  const DrawingBoardPositionFieldWidgetsRow({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    EditPalletProvider editPalletProvider =
        Provider.of<EditPalletProvider>(context);
    // log("editPalletProvider in DrawingBoardPositionFieldWidgetsRow updated ");
    DrawingBoardProvider drawingBoardProvider =
        Provider.of<DrawingBoardProvider>(context, listen: false);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        GestureDetector(
          onPanUpdate: (d) {
            drawingBoardPosition = Offset(
                drawingBoardPosition.dx + d.delta.dy, drawingBoardPosition.dy);
            TextControllers.drawingaBoard_X_posController.text =
                drawingBoardPosition.dx.toStringAsFixed(2);
            log("delat x ${d.delta} / ${TextControllers.drawingaBoard_X_posController.text}");
            editPalletProvider.updateUI();
            drawingBoardProvider.updateUI();
          },
          child: TextWithTextField(
            controller: TextControllers.drawingaBoard_X_posController,
            textFieldTitle: "X",
            onTapUp: () {
              log("x+ called ${drawingBoardPosition}");
              drawingBoardPosition = Offset(
                  drawingBoardPosition.dx + 0.5, drawingBoardPosition.dy);
              TextControllers.drawingaBoard_X_posController.text =
                  drawingBoardPosition.dx.toStringAsFixed(2);
              editPalletProvider.updateUI();
              drawingBoardProvider.updateUI();
            },
            onTapDown: () {
              drawingBoardPosition = Offset(
                  drawingBoardPosition.dx - 0.5, drawingBoardPosition.dy);
              TextControllers.drawingaBoard_X_posController.text =
                  drawingBoardPosition.dx.toStringAsFixed(2);
              editPalletProvider.updateUI();
              drawingBoardProvider.updateUI();
            },
          ),
        ),
        GestureDetector(
          onPanUpdate: (d) {
            drawingBoardPosition = Offset(
                drawingBoardPosition.dx, drawingBoardPosition.dy + d.delta.dy);
            TextControllers.drawingaBoard_Y_posController.text =
                drawingBoardPosition.dy.toStringAsFixed(2);
            log("delat y ${d.delta} / ${TextControllers.drawingaBoard_Y_posController.text}");
            editPalletProvider.updateUI();
            drawingBoardProvider.updateUI();
          },
          child: TextWithTextField(
            controller: TextControllers.drawingaBoard_Y_posController,
            textFieldTitle: "Y",
            onTapUp: () {
              drawingBoardPosition = Offset(
                  drawingBoardPosition.dx, drawingBoardPosition.dy + 0.5);
              TextControllers.drawingaBoard_Y_posController.text =
                  drawingBoardPosition.dy.toStringAsFixed(2);
              editPalletProvider.updateUI();
              drawingBoardProvider.updateUI();
            },
            onTapDown: () {
              drawingBoardPosition = Offset(
                  drawingBoardPosition.dx, drawingBoardPosition.dy - 0.5);
              TextControllers.drawingaBoard_Y_posController.text =
                  drawingBoardPosition.dy.toStringAsFixed(2);
              editPalletProvider.updateUI();
              drawingBoardProvider.updateUI();
            },
          ),
        )
      ],
    );
  }
}

class TextWithTextField extends StatefulWidget {
  String textFieldTitle;
  TextEditingController controller;
  Function? onTapUp;
  Function? onTapDown;
  Function? onLongPressUp;
  Function? onLongPressDown;
  TextStyle? titletextStyle;
  TextWithTextField(
      {Key? key,
      required this.textFieldTitle,
      required this.controller,
      this.titletextStyle,
      this.onTapUp,
      this.onTapDown,
      this.onLongPressUp,
      this.onLongPressDown})
      : super(key: key);

  @override
  State<TextWithTextField> createState() => _TextWithTextFieldState();
}

class _TextWithTextFieldState extends State<TextWithTextField> {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: editFeaturesPalleteBoxWidth * 0.4,
      height: 50,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextWithStyle1(
              text: widget.textFieldTitle,
              fontsize: getFontSizeForLength(widget.textFieldTitle.length)),
          TextFieldNoWithContollerButtons(
            controller: widget.controller,
            onTapUp: () {
              if (widget.onTapUp != null) {
                widget.onTapUp!();
              }
            },
            onLongPressUp: () {
              if (widget.onLongPressUp != null) {
                widget.onLongPressUp!();
              }
            },
            onLongPressDown: () {
              if (widget.onLongPressDown != null) {
                widget.onLongPressDown!();
              }
            },
            onTapDown: () {
              if (widget.onTapDown != null) {
                widget.onTapDown!();
              }
            },
          )
        ],
      ),
    );
  }
}

getFontSizeForLength(int length) {
  if (length < 2) {
    return 16;
  }
  // } else if (length < 6) {
  //   return 16;
  // }

  return 10;
}
