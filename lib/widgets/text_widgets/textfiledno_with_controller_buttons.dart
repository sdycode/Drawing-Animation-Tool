import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/widgets/res/Icons/tap_icon.dart';
import 'package:animated_icon_demo/widgets/text_widgets/textfield_no.dart';
import 'package:flutter/material.dart';

class TextFieldNoWithContollerButtons extends StatefulWidget {
  TextEditingController controller;
  Function? onTapUp;
  Function? onTapDown;
  Function? onLongPressUp;
  Function? onLongPressDown;

  TextFieldNoWithContollerButtons(
      {Key? key, required this.controller, this.onTapUp, this.onTapDown,this.onLongPressUp, this.onLongPressDown})
      : super(key: key);

  @override
  State<TextFieldNoWithContollerButtons> createState() =>
      _TextFieldNoWithContollerButtonsState();
}

class _TextFieldNoWithContollerButtonsState
    extends State<TextFieldNoWithContollerButtons> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: textFieldBoxHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            child: TextFieldNumber(
              
              controller: widget.controller,
              height: textFieldBoxHeight,
              width: editFeaturesPalleteBoxWidth * 0.22,
            ),
          ),
          const SizedBox(
            width: 5,
          ),
          Column(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              TapIcon(
                onTap: () {
                  if (widget.onTapUp != null) {
                    widget.onTapUp!();
                  }
                },
                onLongPress: (){
                   if (widget.onLongPressUp != null) {
                    widget.onLongPressUp!();
                  }
                },
                icon: const Icon(
                  Icons.arrow_upward,
                  size: 15,
                ),
              ),
              TapIcon( onLongPress: (){
                   if (widget.onLongPressDown != null) {
                    widget.onLongPressDown!();
                  }
                },
                onTap: () {
                  if (widget.onTapDown != null) {
                    widget.onTapDown!();
                  }
                },
                icon: const Icon(
                  Icons.arrow_downward,
                  size: 15,
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}
