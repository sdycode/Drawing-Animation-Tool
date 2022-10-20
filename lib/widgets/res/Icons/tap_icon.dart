import 'package:flutter/material.dart';

class TapIcon extends StatelessWidget {
  Widget icon;
  Function? onTap;  Function? onLongPress;
   TapIcon({Key? key, required this.icon, this.onTap,this.onLongPress}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
 
      onLongPress: (){
 if (onLongPress != null) {
          onLongPress!();
        }
        
      },
      onTap: () {
        if (onTap != null) {
          onTap!();
        }
        
  
      },
      child: icon,
    );
  }
}
