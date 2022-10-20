// To parse this JSON data, do
//
//     final userModel = userModelFromMap(jsonString);

import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/pair_model.dart';
import 'package:flutter/material.dart';
import 'package:meta/meta.dart';
import 'dart:convert';

class UserModel {
  UserModel({
    required this.userProfile,
  });

  UserProfile userProfile;

  factory UserModel.fromJson(String str) => UserModel.fromMap(json.decode(str));

  String toJson() => json.encode(toMap());

  factory UserModel.fromMap(Map<String, dynamic> json) => UserModel(
        userProfile: UserProfile.fromMap(json["userProfile"]),
      );

  Map<String, dynamic> toMap() => {
        "userProfile": userProfile.toMap(),
      };
}

class UserProfile {
  UserProfile({
    required this.userName,
    required this.password,
    required this.projects,
  });

  String userName;
  String password;
  List<int> projects;

  factory UserProfile.fromJson(String str) =>
      UserProfile.fromMap(json.decode(str));

  String toJson() => json.encode(toMap());

  factory UserProfile.fromMap(Map<String, dynamic> json) => UserProfile(
      userName: json["userName"],
      password: json["password"],
      projects: json["projects"] == null
          ? []
          : List<int>.from(json["projects"].map((x) => x))
      // project: List<Project>.from(json["projects"].map((x) => Project.fromMap(x))),

      );

  Map<String, dynamic> toMap() => {
        "userName": userName,
        "password": password,
        "projects": List<dynamic>.from(projects.map((x) => x)),
        // "projects": List<dynamic>.from(project.map((x) => x.toMap())),
      };
}

class Project {
  Project(
      {required this.projectId,
      required this.projectName,
      required this.iconSections,
      required this.width,
      required this.height,
      this.position = Point.zero});

  String projectId;
  String projectName;
  List<IconSection> iconSections;
  double width;
  double height;
  Point position;

  factory Project.fromJson(String str) => Project.fromMap(json.decode(str));

  String toJson() => json.encode(toMap());

  factory Project.fromMap(Map<String, dynamic> json) => Project(
      projectId: json["projectId"],
      projectName: json["projectName"],
      iconSections: List<IconSection>.from(
          json["iconSections"].map((x) => IconSection.fromMap(x))),
      width: json['width'] ?? defaultProjectWidth,
      height: json['height'] ?? defaultProjectHeight,
      position: json["position"] == null
          ? Point.zero
          : Point.fromMap(json["position"]));

  Map<String, dynamic> toMap() => {
        "projectId": projectId,
        "projectName": projectName,
        "iconSections":
            List<Map<String, dynamic>>.from(iconSections.map((x) => x.toMap())),
        "width": width,
        "height": height,
        "position": position.toMap()
      };
}

class IconSection {
  IconSection(
      {required this.iconSectionNo,
      required this.iconSectionName,
      required this.frames,
      required this.position,
      this.drawingObjectType = "polyline"});

  int iconSectionNo;
  String iconSectionName;
  List<Frame> frames;
  Point position;
  String drawingObjectType;
  factory IconSection.fromJson(String str) =>
      IconSection.fromMap(json.decode(str));

  String toJson() => json.encode(toMap());

  factory IconSection.fromMap(Map<String, dynamic> json) => IconSection(
      iconSectionNo: json["iconSectionNo"] ?? 0,
      iconSectionName: json["iconSectionName"] ?? "Polyline_0",
      frames: json["frames"] == null
          ? []
          : List<Frame>.from(json["frames"].map((x) => Frame.fromMap(x))),
      position: json["position"] == null
          ? Point.zero
          : Point.fromMap(json["position"]),
      drawingObjectType: json["drawingObjectType"] ?? "polyline");

  Map<String, dynamic> toMap() => {
        "iconSectionNo": iconSectionNo,
        "iconSectionName": iconSectionName,
        "frames": List<Map<String, dynamic>>.from(frames.map((x) => x.toMap())),
        "position": position.toMap(),
        "drawingObjectType": drawingObjectType
      };
}

class Frame {
  Frame({
    required this.frameNo,
    required this.singleFrameModel,
  });

  int frameNo;

  SingleFrameModel singleFrameModel;

  factory Frame.fromJson(String str) => Frame.fromMap(json.decode(str));

  String toJson() => json.encode(toMap());

  factory Frame.fromMap(Map<String, dynamic> json) => Frame(
        frameNo: json["frameNo"] ?? 0,
        singleFrameModel: json["SingleFrameModel"] == null
            ? SingleFrameModel(frameNo: 0)
            : SingleFrameModel.fromMap(json["SingleFrameModel"]),
      );

  Map<String, dynamic> toMap() => {
        "frameNo": frameNo,
        "SingleFrameModel": singleFrameModel.toMap(),
      };
}

class SingleFrameModel {
  SingleFrameModel(
      {required this.frameNo,
      this.boxSize = const BoxSize(),
      this.hoverPoint = const Point(x: 0, y: 0),
      this.controlPointAdjecntPair,
      this.controlMidPoints = const {},
      this.points = const [],
      this.cornerBoxPoints = const [
        Point.zero,
        Point.zero,
        Point.zero,
        Point.zero
      ],
      this.panPointIndex = -1,
      this.framePosition = 0.0});

  int frameNo;
  BoxSize boxSize;
  Point hoverPoint;
  ControlPointAdjecntPair? controlPointAdjecntPair;
  Map<String, Point> controlMidPoints;
  List<Point> points;
  List<Point> cornerBoxPoints;
  int panPointIndex = -1;
  double framePosition;
  factory SingleFrameModel.withAllPointsButNOtFrameNo(
      SingleFrameModel model, int frmno) {
    SingleFrameModel newModel = SingleFrameModel.fromModel(model);
    newModel.frameNo = frmno;
    return newModel;
  }
  factory SingleFrameModel.fromJson(String str) =>
      SingleFrameModel.fromMap(json.decode(str));

  String toJson() => json.encode(toMap());
  factory SingleFrameModel.fromModel(SingleFrameModel model) {
    return model;
  }
  factory SingleFrameModel.fromMap(Map<String, dynamic> json) =>
      SingleFrameModel(
          frameNo: json["frameNo"] ?? 0,
          framePosition: json["framePosition"] ?? 0.0,
          boxSize: json["boxSize"] == null
              ? const BoxSize()
              : BoxSize.fromMap(json["boxSize"]),
          hoverPoint: json["hoverPoint"] == null
              ? Point(x: 0.0, y: 0.0)
              : Point.fromMap(json["hoverPoint"]),
          controlPointAdjecntPair: json["controlPointAdjecntPair"] == null
              ? ControlPointAdjecntPair()
              : ControlPointAdjecntPair.fromMap(
                  json["controlPointAdjecntPair"]),
          controlMidPoints: json["controlMidPoints"] == null
              ? {}
              : Map.from(json["controlMidPoints"])
                  .map((k, v) => MapEntry<String, Point>(k, Point.fromMap(v))),
          points: json["points"] == null
              ? []
              : List<Point>.from(json["points"].map((x) => Point.fromMap(x))),
          cornerBoxPoints: json["cornerBoxPoints"] == null
              ? [Point.zero, Point.zero, Point.zero, Point.zero]
              : List<Point>.from(
                  json["cornerBoxPoints"].map((x) => Point.fromMap(x))));

  Map<String, dynamic> toMap() => {
        "frameNo": frameNo,
        "framePosition": framePosition,
        "boxSize": boxSize.toMap(),
        "hoverPoint": hoverPoint.toMap(),
        "controlPointAdjecntPair": controlPointAdjecntPair?.toMap(),
        "controlMidPoints": Map.from(controlMidPoints)
            .map((k, v) => MapEntry<String, dynamic>(k, v.toMap())),
        "points": List<Map<String, dynamic>>.from(points.map((x) => x.toMap())),
        "cornerBoxPoints": List<Map<String, dynamic>>.from(
            cornerBoxPoints.map((x) => x.toMap()))
      };
}

class BoxSize {
  const BoxSize({
    this.width = 200,
    this.height = 100,
  });

  final int width;
  final int height;

  factory BoxSize.fromJson(String str) => BoxSize.fromMap(json.decode(str));

  String toJson() => json.encode(toMap());

  factory BoxSize.fromMap(Map<String, dynamic> json) => BoxSize(
        width: json["width"],
        height: json["height"],
      );

  Map<String, dynamic> toMap() => {
        "width": width,
        "height": height,
      };
}

class Point {
  const Point({
    required this.x,
    required this.y,
  });

  final double x;
  final double y;

  factory Point.fromJson(String str) => Point.fromMap(json.decode(str));

  String toJson() => json.encode(toMap());
  factory Point.fromOffset(Offset offset) {
    return Point(x: offset.dx, y: offset.dy);
  }
  factory Point.fromMap(Map<String, dynamic> json) => Point(
        x: json["x"] ?? 0,
        y: json["y"] ?? 0,
      );

  factory Point.fromPoint(Point p) => Point(x: p.x, y: p.y);
  static const Point zero = Point(x: 0, y: 0);
  Map<String, dynamic> toMap() => {
        "x": x,
        "y": y,
      };
}

class ControlPointAdjecntPair {
  ControlPointAdjecntPair({
    this.preIndex = 0,
    this.nextIndex = 1,
  });

  int? preIndex;
  int? nextIndex;

  factory ControlPointAdjecntPair.fromJson(String str) =>
      ControlPointAdjecntPair.fromMap(json.decode(str));

  String toJson() => json.encode(toMap());
  ControlPointAdjecntPair.fromPair(Pair pair) {
    this.preIndex = pair.preIndex;
    this.nextIndex = pair.nextIndex;
  }
  factory ControlPointAdjecntPair.fromMap(Map<String, dynamic> json) =>
      ControlPointAdjecntPair(
        preIndex: json["preIndex"],
        nextIndex: json["nextIndex"],
      );

  Map<String, dynamic> toMap() => {
        "preIndex": preIndex,
        "nextIndex": nextIndex,
      };
}
