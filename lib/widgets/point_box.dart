import 'package:flutter/material.dart';

class BoxPoint extends StatelessWidget {
  final isSelected;
  final isHovered;
  final child;

  const BoxPoint({Key? key, required this.isSelected,required this.isHovered, required this.child})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
 
      child: Transform.scale(
        scale: isHovered ? 1.2:1,
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            boxShadow: isHovered  ?const [BoxShadow(
              blurRadius: 1,spreadRadius: 1,offset: Offset(1,1)
            )]:[],
              border: Border.all(),
              color: isSelected ? Colors.purple.shade300 : Colors.white),
          child: child,
        ),
      ),
    );
  }
}
