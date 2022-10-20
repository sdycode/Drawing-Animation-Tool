import 'package:flutter/material.dart';

class TapImageIcon extends StatelessWidget {
  String imagePath;
  bool tapEnabled;
  double width;
  double height;
  EdgeInsetsGeometry? padding;
  double cornerRadius;
  Function? onTap;
  Function? onLongPress;
  TapImageIcon(
      {Key? key,
      required this.imagePath,
      this.onTap,
      this.onLongPress,
      this.width = 20,
      this.height = 20,
      this.padding = const EdgeInsets.all(4),
      this.cornerRadius = 4,
      
      this.tapEnabled = true
      })
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return 
    
    tapEnabled ? 
    InkWell(
      onLongPress: () {
        if (onLongPress != null) {
          onLongPress!();
        }
      },
      onTap: () {
        if (onTap != null) {
          onTap!();
        }
      },
      child: _child()
    ):_child();
  }
  Widget _child(){
  return Container(
        width: width,
        height: height,
        padding: padding,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(cornerRadius),
          child: Image.asset(
            imagePath,
            // width: width,
            // height: height,
            fit: BoxFit.contain,
          ),
        ),
      );
}
}


