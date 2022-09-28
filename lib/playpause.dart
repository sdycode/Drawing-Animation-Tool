import 'package:animated_icon_demo/Animated/my_animated_icons.dart' as my;
import 'package:flutter/material.dart';

class PlayPause extends StatefulWidget {
  PlayPause({Key? key}) : super(key: key);

  @override
  State<PlayPause> createState() => _PlayPauseState();
}

class _PlayPauseState extends State<PlayPause> with TickerProviderStateMixin {
  late AnimationController controller;

  bool isPlaying = false;

  @override
  void initState() {
    // TODO: implement initState
    controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000));

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
        onTap: () {
          setState(() {
            isPlaying ? controller.reverse() : controller.forward();
            isPlaying = !isPlaying;
          });
        },
        child: Wrap(
          // mainAxisAlignment: MainAxisAlignment.center,
          children: [
          ...(animatedIconDataList.map((  e) =>     AnimatedIcon(
              icon: e as AnimatedIconData,
              progress: controller,
              size: 100,
            )).toList()),
           

              AnimatedIcon(
              icon: AnimatedIcons.play_pause,
              progress: controller,
              size: 100,
            ),
            // my.MyAnimatedIcon(
            //     icon: my.MyAnimatedIcons.play_pause,
            //     progress: controller,
            //     size: 120)
          ],
        ));
  }

  List animatedIconDataList =[AnimatedIcons.pause_play,
  
  
  AnimatedIcons.add_event ,
  AnimatedIcons.arrow_menu , 

  AnimatedIcons. ellipsis_search,
  AnimatedIcons.event_add ,
  AnimatedIcons.search_ellipsis ,
  AnimatedIcons.home_menu ,
  AnimatedIcons.close_menu ,
  AnimatedIcons.view_list ,

  ];
}
