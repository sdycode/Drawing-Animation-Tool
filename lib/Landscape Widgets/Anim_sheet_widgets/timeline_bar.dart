
import 'package:animated_icon_demo/Landscape%20Widgets/Anim_sheet_widgets/trianlge_drag_pointer.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/animation_sheet.dart';
import 'package:animated_icon_demo/extensions.dart';
import 'package:flutter/material.dart';

class TimelineBar extends StatelessWidget {
  const TimelineBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      
       width: animTimelineWidthFactor.sw(context),
        height: timelineBarH.sw(context),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), 
        
        
        color: 
        // Colors.green,
        Color.fromARGB(255, 34, 0, 11),
        
        
        ),
       
        child: Stack(children: [
          Positioned(
            
            left: timeLinePointerXPosition,
            child: TriangleDragPointer())
        ]),
    );
  }
}