// import 'package:animated_icon_demo/drawing_grid_canvas/models/pair_model.dart';
// import 'package:flutter/material.dart';
// import 'dart:convert';

// class SingleFrameModel {
//   int frameNo;
//   double width;
//   double height;

//   SingleFrameModel(
//       {required this.frameNo, required this.width, required this.height});
//   Offset hoverPoint = Offset.zero;
//   Pair controlPointAdjecntPair = Pair(0, 1);
//   Map<int, Offset> controlMidPoints = {};
//   // List<Offset> points = [];
//   // int panPointIndex = -1;
//   // bool pathClosed = false;

//   String toJson() => json.encode(toMap());

//   factory SingleFrameModel.fromMap(Map<String, dynamic> json) {
//     SingleFrameModel singleFrameModel = SingleFrameModel(
//         frameNo: json["frameNo"]! as int,
//         width: json["width"]! as double,
//         height: json["height"]! as double);
//     singleFrameModel.hoverPoint = Offset(Point.fromMap(json["hoverPoint"]).x,
//         Point.fromMap(json["hoverPoint"]).y);
//     singleFrameModel.controlPointAdjecntPair =
//         Pair.fromMap(json['controlPointAdjecntPair']);
// singleFrameModel.controlMidPoints = ControlMidPoints.fromMap(json["controlMidPoints"]).controlMidPoints;
//     return singleFrameModel;
//   }

//   Map<String, dynamic> toMap() => {
//         "frameNo": frameNo,
//         "width": width,
//         "height": height,
//         "hoverPoint": hoverPoint,
//         "controlPointAdjecntPair": controlPointAdjecntPair,
//         // "controlMidPoints": controlMidPoints,
//         // "points": points,
//         // "panPointIndex": panPointIndex,
//         // "pathClosed": pathClosed
//       };
// }

// class Point {
//   double x;
//   double y;
//   Point(this.x, this.y);
//   Map<String, dynamic> toMap() => {"x": x, "y": y};
//   factory Point.fromMap(Map<String, dynamic> json) {
//     return Point(json["x"], json["y"]);
//   }
// }

// class ControlMidPoints{
//     Map<int, Offset> controlMidPoints ={};
//     ControlMidPoints(this.controlMidPoints);
//    factory ControlMidPoints.fromMap(Map<int, Point> json){
// ControlMidPoints controlMidPoints = ControlMidPoints({});
// // controlMidPoints.controlMidPoints=  json[]
//     return controlMidPoints;
//    }
// }


// // {
// //     "projectId": "shubham0",
// //     "projectName": "AnimatedIconProjectshubham0",
// //     "iconSections": [
// //         {
// //             "iconSection": {
// //                 "iconSectionNo": 0,
// //                 "iconSectionName": "",
// //                 "frames": [
// //                     {
// //                         "frameNo": 0,
// //                         "boxSize": {
// //                             "width": 100,
// //                             "height": 100
// //                         }
// //                     },
// //                     {}
// //                 ]
// //             }
// //         },
// //         {
// //             "iconSection": {}
// //         }
// //     ]
// // }