import 'package:animated_icon_demo/Global/global.dart';
import 'package:animated_icon_demo/Images/icons_paths.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/screens/landscape_layout.dart';
import 'package:animated_icon_demo/widgets/res/Icons/tap_image_icon.dart';
import 'package:flutter/material.dart';

showProjecListInDialog(BuildContext context) async {
  showDialog(
    context: context,
    builder: (context) {
      return Dialog(
    
        backgroundColor: Colors.grey.shade100,
        insetPadding:
            EdgeInsets.symmetric(horizontal: w * 0.1, vertical: h * 0.1),
        child: Column(
          // mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: GridView(
                padding: EdgeInsets.all(20),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6, childAspectRatio: 1),
                children: [
                  ...List.generate(
                      projectList.length,
                      (i) => Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8)
                          ,color: currentProjectNo==i?Colors.blue.shade300.withAlpha(150):Colors.transparent
                        ),
                        padding: EdgeInsets.all(8),
                        child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 220,
                                  height: 150,
                                  child: TapImageIcon(
                                    imagePath: IconsImagesPaths.file,
                                    onTap: () async {
                                      currentProjectNo = i;
                                      Navigator.maybePop(context);
                                  
                                      Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (context) => LandscapeLayoutScreen()
                              // DrawGridCanvase()

                              ));
                                    },
                                  ),
                                ),
                                Text(
                                  projectList[i].projectName,
                                  style: TextStyle(fontSize: 15),
                                )
                              ],
                            ),
                      ))
                ],
              ),
            ),
            // SingleChildScrollView(
            //   child: Wrap(

            //     children: [

            //       ...List.generate(projectList.length+40, (i) => Column(
            //         mainAxisSize: MainAxisSize.min,
            //         children: [
            //           Container(width: 180, height: 150,
            //           child: TapImageIcon(imagePath: IconsImagesPaths.file,

            //           onTap: (){},

            //           ),), Text("projectList[i].projectName")
            //         ],

            //       ))
            //     ],
            //   ),
            // )
          ],
        ),
      );
    },
  );
}
