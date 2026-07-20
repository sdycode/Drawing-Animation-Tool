import 'package:flutter/material.dart';

class ControlBoxPoint extends StatelessWidget {
  final Offset position;
  const ControlBoxPoint(this.position,{Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx-5,
        top: position.dy-5,
        child: Container(
      decoration:
          const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
      height: 10,
      width: 10,
    ));
  }
}
