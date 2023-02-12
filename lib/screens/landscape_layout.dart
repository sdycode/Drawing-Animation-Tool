import 'dart:developer';

import 'package:animated_icon_demo/Landscape%20Widgets/animation_sheet.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/drawing_board_background_box.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/drawing_board_widget.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/drawing_components_tree_box.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/edit_features_pallete_box.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/top_bar.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/numeric%20funtions/getActualStickserPositionFromPercentValue.dart';
import 'package:animated_icon_demo/enums/enums.dart';
import 'package:animated_icon_demo/extensions.dart';
import 'package:animated_icon_demo/providers/animation_sheet_provider.dart';
import 'package:animated_icon_demo/providers/prov.dart';
import 'package:animated_icon_demo/widgets/drawer.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LandscapeLayoutScreen extends StatefulWidget {
  LandscapeLayoutScreen({Key? key}) : super(key: key);

  @override
  State<LandscapeLayoutScreen> createState() => _LandscapeLayoutScreenState();
}
final scaffoldKey = GlobalKey<ScaffoldState>();
late AnimationController newanimationController;

class _LandscapeLayoutScreenState extends State<LandscapeLayoutScreen>
    with TickerProviderStateMixin {
  @override
  void initState() {
    // TODO: implement initState
    super.initState();
     if(projectList.length> currentProjectNo){
      if(projectList[currentProjectNo].iconSections.length>currentIconSectionNo){
        componentSelectedTypeInTree = ComponentSelectedTypeInTree.drawingObject;
      }
    }
      
    newanimationController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3000));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<AnimSheetProvider>(context, listen: false)
            .animationSheetFromTop = 100.sh(context) - 10;
        setState(() {});
      }
    });
    newanimationController.addListener(() {

      if (mounted) {
        setState(() {
       timeLinePointerXPosition =    getActualStickserPositionFromPercentValue(newanimationController.value*100, context);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ProvData provData = Provider.of<ProvData>(
      context,
    );
    AnimSheetProvider animSheetProvider =
        Provider.of<AnimSheetProvider>(context, listen: false);
    log("build in land");
   
    return Scaffold(
      endDrawer: AppDrawer(),
      key: scaffoldKey,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: Theme.of(context).primaryColor,
        child: Stack(children: [
          TopBar(),
          DrawingComponentsTreeBox(),
          DrawingBoardBackgroundBox(),
          EditFeaturesPalleteBox(),
          AnimationSheetWidget(),
          // Positioned(
          //     left: 250,
          //     top: 150,
          //     child: Text("${animSheetProvider.animationSheetFromTop}")),
          // Consumer<AnimSheetProvider>(
          //   builder: (context, animSheetProvider, child) {
          //     log("build in land in consumer");
          //     return Positioned(
          //         top: animSheetProvider.animationSheetFromTop,
          //         child: child ?? Container());
          //   },
          //   child: AnimationSheetWidget(),
          // )
        ]),
      ),
    );
  }
}
