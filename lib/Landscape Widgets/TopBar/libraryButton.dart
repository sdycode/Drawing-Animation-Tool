import 'dart:convert';

import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/providers/animation_sheet_provider.dart';
import 'package:animated_icon_demo/providers/prov.dart';
import 'package:annimation/annimation.dart';
import 'package:flutter/material.dart';

libraryButton(BuildContext context, AnimSheetProvider animSheetProvider,
    ProvData provData) {
  return Container(
    margin: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    decoration: BoxDecoration(
      border: Border.all(color: Colors.white),
      // color:topbarColor,
      borderRadius: BorderRadius.circular(topbarHeight * 0.5),
      //  boxShadow: [BoxShadow(color: Colors.blue, spreadRadius: 1, blurRadius: 3, offset: Offset(0,0))]
    ),
    child: TextButton.icon(
        onPressed: () async {
          showLibrary = true;
          animSheetProvider.updateUI();
          provData.updateUI();
          
        },
        icon: Container(
            height: topbarHeight * 0.7,
            child: Image.asset(
              "assets/icons/files.png",
              fit: BoxFit.contain,
            )),
        label: const Text(
          "Library",
          style: TextStyle(
            fontWeight: FontWeight.bold, color: Colors.white,
            // fontSize: topbarHeight*0.4
          ),
        )),
  );
}

class LibrarySampleWidget extends StatelessWidget {
  const LibrarySampleWidget(
      {super.key, required this.jsonFilePath, this.onTap});
  final String jsonFilePath;
  final Function? onTap;

  @override
  Widget build(BuildContext context) {
    double boxSize = 200;
    String filename = "FileName";
    if (jsonFilePath.contains(".json") && jsonFilePath.contains("/")) {
      filename = jsonFilePath.split("/").last.replaceAll(".json", "");
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimationFromAssetFileWithTimeDuration(
          repeat: true,
          filePath: jsonFilePath,
          animationDuration: Duration(milliseconds: 2000),
          size: Size(boxSize, boxSize),
          clickAnimationDirection: ClickAnimationDirection.forwardReverse,
        ),
        Text(
          filename,
        ),
        // ElevatedButton(
        //     onPressed: () {
        //       // if (onTap != null) {
        //       //   onTap!();
        //       // }
        //       // Navigator.pop(context);
        //     },
        //     child: Text("Open"))
      ],
    );
  }
}


