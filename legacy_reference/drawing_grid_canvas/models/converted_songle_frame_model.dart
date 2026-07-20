// // To parse this JSON data, do
// //
// //     final sampleModel = sampleModelFromMap(jsonString);

// import 'dart:convert';

// import 'package:animated_icon_demo/drawing_grid_canvas/hover_paint.dart';

// // class SampleModel {
// //     SampleModel({
// //         required this.singleFrameModel,
// //     });

// //     SingleFrameModel singleFrameModel;

// //     factory SampleModel.fromJson(String str) => SampleModel.fromMap(json.decode(str));

// //     String toJson() => json.encode(toMap());

// //     factory SampleModel.fromMap(Map<String, dynamic> json) => SampleModel(
// //         singleFrameModel: SingleFrameModel.fromMap(json["SingleFrameModel"]),
// //     );

// //     Map<String, dynamic> toMap() => {
// //         "SingleFrameModel": singleFrameModel.toMap(),
// //     };
// // }

// class SingleFrameModel {
//     SingleFrameModel({
//           required this.frameNo,
//         this.boxSize = const BoxSize(),
//         this.hoverPoint= const  Point(x: 0,y: 0),
//         this.controlPointAdjecntPair ,
//         this.controlMidPoints = const {},
//         this.points =const [],
//     });

//     int frameNo;
//     BoxSize boxSize;
//     Point hoverPoint ;
//     ControlPointAdjecntPair? controlPointAdjecntPair = ControlPointAdjecntPair() ;
//     Map<String, Point> controlMidPoints ={};
//     List<Point> points;

//     factory SingleFrameModel.fromJson(String str) => SingleFrameModel.fromMap(json.decode(str));

//     String toJson() => json.encode(toMap());

//     factory SingleFrameModel.fromMap(Map<String, dynamic> json) => SingleFrameModel(
//         frameNo: json["frameNo"],
//         boxSize: BoxSize.fromMap(json["boxSize"]),
//         hoverPoint: Point.fromMap(json["hoverPoint"]),
//         controlPointAdjecntPair: ControlPointAdjecntPair.fromMap(json["controlPointAdjecntPair"]),
//         controlMidPoints: Map.from(json["controlMidPoints"]).map((k, v) => MapEntry<String, Point>(k, Point.fromMap(v))),
//         points: List<Point>.from(json["points"].map((x) => Point.fromMap(x))),
//     );

//     Map<String, dynamic> toMap() => {
//         "frameNo": frameNo,
//         "boxSize": boxSize.toMap(),
//         "hoverPoint": hoverPoint.toMap(),
//         "controlPointAdjecntPair": controlPointAdjecntPair?.toMap(),
//         "controlMidPoints": Map.from(controlMidPoints).map((k, v) => MapEntry<String, dynamic>(k, v.toMap())),
//         "points": List<dynamic>.from(points.map((x) => x.toMap())),
//     };
// }

// class BoxSize {
//     const BoxSize({
//         this.width = 200,
//         this.height =100,
//     });

//    final int width;
//    final int height;

//     factory BoxSize.fromJson(String str) => BoxSize.fromMap(json.decode(str));

//     String toJson() => json.encode(toMap());

//     factory BoxSize.fromMap(Map<String, dynamic> json) => BoxSize(
//         width: json["width"],
//         height: json["height"],
//     );

//     Map<String, dynamic> toMap() => {
//         "width": width,
//         "height": height,
//     };
// }

// class Point {
//   const  Point({
//         required this.x,
//         required this.y,
//     });

//     final x;
//     final y;

//     factory Point.fromJson(String str) => Point.fromMap(json.decode(str));

//     String toJson() => json.encode(toMap());

//     factory Point.fromMap(Map<String, dynamic> json) => Point(
//         x: json["x"],
//         y: json["y"],
//     );

//     Map<String, dynamic> toMap() => {
//         "x": x,
//         "y": y,
//     };
// }

// class ControlPointAdjecntPair {
//      ControlPointAdjecntPair({
//         this.preIndex =0,
//         this.nextIndex= 1,
//     });

//     int preIndex;
//     int nextIndex;

//     factory ControlPointAdjecntPair.fromJson(String str) => ControlPointAdjecntPair.fromMap(json.decode(str));

//     String toJson() => json.encode(toMap());

//     factory ControlPointAdjecntPair.fromMap(Map<String, dynamic> json) => ControlPointAdjecntPair(
//         preIndex: json["preIndex"],
//         nextIndex: json["nextIndex"],
//     );

//     Map<String, dynamic> toMap() => {
//         "preIndex": preIndex,
//         "nextIndex": nextIndex,
//     };
// }
