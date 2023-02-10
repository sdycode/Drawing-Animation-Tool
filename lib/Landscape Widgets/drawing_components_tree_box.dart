import 'dart:developer';
import 'dart:html' as html;
import 'package:animated_icon_demo/Images/icons_paths.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/DrawingCompoents/DrawingComponentTileWidget.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/animation_sheet.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/add%20new%20methods/add_new_iconsection.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/numeric%20funtions/update_framePos_list.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/reset_proper_selectedpointIndex.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/shape%20functions/set_drawingobjecttype_when_iconsection_selected.dart';
import 'package:animated_icon_demo/enums/enums.dart';
import 'package:animated_icon_demo/extensions.dart';
import 'package:animated_icon_demo/providers/drawing_board_provider.dart';
import 'package:animated_icon_demo/providers/edit_pallet_provider.dart';
import 'package:animated_icon_demo/providers/prov.dart';
import 'package:animated_icon_demo/widgets/res/Icons/tap_icon.dart';
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
    EditPalletProvider editProvider = Provider.of<EditPalletProvider>(
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
                      log("iconSectionNosIncludedInAnimation ${iconSectionNosIncludedInAnimation}");
                      setState(() {
                        componentSelectedTypeInTree =
                            ComponentSelectedTypeInTree.drawingBoard;
                      });
                      drawingBoardProvider.updateUI();
                      editProvider.updateUI();
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
