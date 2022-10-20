import 'dart:developer';
import 'dart:html' as html;
import 'package:animated_icon_demo/Images/icons_paths.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/add%20new%20methods/add_new_iconsection.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/numeric%20funtions/update_framePos_list.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/reset_proper_selectedpointIndex.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/shape%20functions/set_drawingobjecttype_when_iconsection_selected.dart';
import 'package:animated_icon_demo/enums/enums.dart';
import 'package:animated_icon_demo/extensions.dart';
import 'package:animated_icon_demo/providers/drawing_board_provider.dart';
import 'package:animated_icon_demo/providers/prov.dart';
import 'package:animated_icon_demo/widgets/res/Icons/tap_image_icon.dart';
import 'package:animated_icon_demo/widgets/text_widgets/textstyle1.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class DrawingComponentsTreeBox extends StatefulWidget {
  DrawingComponentsTreeBox({Key? key}) : super(key: key);

  @override
  State<DrawingComponentsTreeBox> createState() =>
      _DrawingComponentsTreeBoxState();
}

class _DrawingComponentsTreeBoxState extends State<DrawingComponentsTreeBox> {
  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    html.document.onContextMenu.listen((event) => event.preventDefault());
  }

  @override
  Widget build(BuildContext context) {
    DrawingBoardProvider drawingBoardProvider =
        Provider.of<DrawingBoardProvider>(
      context,
    );
    // log("componentSelectedTypeInTree ${componentSelectedTypeInTree}");
    return Positioned(
        top: topbarHeight,
        child: Container(
            margin: const EdgeInsets.all(borderMargin),
            width: drawingComponentsTreeBoxWidth,
            height: 100.sh(context),
            color: Theme.of(context).primaryColorDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: topbarHeight * 0.6,
                  width: drawingComponentsTreeBoxWidth,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      TextWithStyle1(
                        text: " Components",
                        onTap: () {},
                        fontsize: 16,
                      ),
                      const Spacer(),
                      IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: topbarHeight * 0.5,
                          onPressed: () {
                            currentFrameNo = 0;
                            addNewIconSection();
                            setState(() {});
                          },
                          icon: const Icon(
                            Icons.add,
                            size: topbarHeight * 0.5,
                          ))
                    ],
                  ),
                ),
                const Divider(
                  color: Colors.grey,
                  thickness: 0.5,
                ),
                Container(
                  decoration: BoxDecoration(
                      color: componentSelectedTypeInTree ==
                              ComponentSelectedTypeInTree.drawingBoard
                          ? Colors.grey.withAlpha(120)
                          : Colors.transparent),
                  child: TextWithStyle1(
                    text: " Drawing Board",
                    onTap: () {
                      setState(() {
                        componentSelectedTypeInTree =
                            ComponentSelectedTypeInTree.drawingBoard;
                      });
                      drawingBoardProvider.updateUI();
                    },
                    fontsize: 16,
                  ),
                ),
                const Divider(
                  color: Colors.grey,
                  indent: 10,
                  endIndent: 10,
                  thickness: 0.3,
                ),
                Container(
                  padding: const EdgeInsets.only(left: 20),
                  child: ListView.builder(
                    itemCount:
                        projectList[currentProjectNo].iconSections.length,
                    shrinkWrap: true,
                    itemBuilder: (c, i) {
                      return DrawingComponentTileWidget(i);
                    },
                  ),
                )
              ],
            )));
  }
}

class DrawingComponentTileWidget extends StatelessWidget {
  final i;
  DrawingComponentTileWidget(this.i, {Key? key}) : super(key: key);

  _openMenu(BuildContext context, TapDownDetails event,
      DrawingBoardProvider drawingBoardProvider, i) async {
    double fontsize = 18;

    final menuItem = await showMenu<int>(
        color: Colors.black,
        context: context,
        items: [
          PopupMenuItem(
            value: 1,
            onTap: () {
              log("seconday build called with $showOuterBox");
              if (showOuterBox == ShowOuterBox.hide) {
                showOuterBox = ShowOuterBox.show;
              } else {
                showOuterBox = ShowOuterBox.hide;
              }
              // drawingBoardProvider.updateUI();
              log("seconday build called with $showOuterBox");
            },
            child: TextWithStyle1(
              text: showOuterBox == ShowOuterBox.hide
                  ? "Show Outer Box"
                  : "Hide Outer Box",
              ignoreTap: true,
              fontsize: fontsize,
            ),
          ),
          PopupMenuItem(
            value: 2,
            onTap: () {
              if (projectList[currentProjectNo].iconSections.length > 1 &&
                  projectList[currentProjectNo].iconSections.length > i) {
                projectList[currentProjectNo].iconSections.removeAt(i);
                if (projectList[currentProjectNo].iconSections.length > i) {
                  currentIconSectionNo = i;
                } else {
                  currentIconSectionNo = i - 1;
                }
                set_drawingobjecttype_when_iconsection_selected();
              }
            },
            child: TextWithStyle1(
              text: "Delete",
              ignoreTap: true,
              fontsize: fontsize,
            ),
          ),
        ],
        position: RelativeRect.fromLTRB(
            event.globalPosition.dx,
            event.globalPosition.dy,
            event.globalPosition.dx,
            event.globalPosition.dy));
    drawingBoardProvider.updateUI();
  }

  @override
  Widget build(BuildContext context) {
    DrawingBoardProvider drawingBoardProvider =
        Provider.of<DrawingBoardProvider>(
      context,
    );  ProvData provData = Provider.of<ProvData>(
          context,
        );
    log("seconday build called ");
    return GestureDetector(
      onSecondaryTapDown: (TapDownDetails d) {
        _openMenu(context, d, drawingBoardProvider, i);
        log("on seconday tap down ${d.localPosition}");
      },
      onTap: () {
        // Iconsection tapped or selected
        componentSelectedTypeInTree = ComponentSelectedTypeInTree.drawingObject;
        // setDrawingObjectForThis(projectList[currentProjectNo]
        //     .iconSections[currentIconSectionNo]
        //     .drawingObjectType);
        currentIconSectionNo = i;
        set_drawingobjecttype_when_iconsection_selected();
        if (currentFrameNo >
            projectList[currentProjectNo]
                    .iconSections[currentIconSectionNo]
                    .frames
                    .length -
                1) {
          currentFrameNo = projectList[currentProjectNo]
                  .iconSections[currentIconSectionNo]
                  .frames
                  .length -
              1;
        }
        updateFramePostList();
        resetSelectedPointIndexAfterAnyChange();
        // log("componentSelectedTypeInTree bef ${componentSelectedTypeInTree}");
        // drawingBoardProvider.updateUI();
        //      Provider.of<ProvData>(
        //   context,
        // ).updateUI();
      
        provData.updateUI();
        // log("componentSelectedTypeInTree after ${componentSelectedTypeInTree}");
      },
      child: Container(
        padding: EdgeInsets.all(4),
        width: drawingComponentsTreeBoxWidth - 80,
        decoration: BoxDecoration(
            color: currentIconSectionNo == i &&
                    componentSelectedTypeInTree ==
                        ComponentSelectedTypeInTree.drawingObject
                ? Colors.grey.withAlpha(120)
                : Colors.transparent),
        child: Text(
          projectList[currentProjectNo].iconSections[i].iconSectionName,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }
}
