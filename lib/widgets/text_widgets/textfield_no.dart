import 'dart:developer';

import 'package:animated_icon_demo/colors/text_field_colors.dart';
import 'package:animated_icon_demo/providers/drawing_board_provider.dart';
import 'package:animated_icon_demo/providers/edit_pallet_provider.dart';
import 'package:animated_icon_demo/utils/text_field_methods/on_changed_in_number_textfield.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TextFieldNumber extends StatefulWidget {
  TextEditingController controller;
  double width;
  double height;

  TextFieldNumber(
      {Key? key, required this.controller, this.width = 60, this.height = 50})
      : super(key: key);

  @override
  State<TextFieldNumber> createState() => _TextFieldNumberState();
}

class _TextFieldNumberState extends State<TextFieldNumber> {
  @override
  Widget build(BuildContext context) {
    EditPalletProvider editPalletProvider =
        Provider.of<EditPalletProvider>(context);

    DrawingBoardProvider drawingBoardProvider =
        Provider.of<DrawingBoardProvider>(
      context,
    );
    return Container(
      width: widget.width,
      height: widget.height,
      child: TextField(
        controller: widget.controller,
        keyboardType: TextInputType.number,
        maxLines: 1,
        minLines: 1,
        cursorColor: noFieldCursorColor,
        onChanged: (v) {
          log("onchangedno $v");
          onChangedInNumberTextfield(v, widget.controller);

          editPalletProvider.updateUI();
          drawingBoardProvider.updateUI();
// widget.controller.selection = TextSelection.fromPosition(TextPosition(offset: widget.controller.text.length));
        },
        style:
            Theme.of(context).textTheme.displayMedium?.copyWith(fontSize: 15),
        decoration: InputDecoration(
            contentPadding: EdgeInsets.only(left: 8),
            border: OutlineInputBorder(
                borderSide:
                    const BorderSide(width: 1, color: Colors.deepPurple),
                borderRadius: BorderRadius.circular(5)),
            enabledBorder: OutlineInputBorder(
                borderSide:
                    const BorderSide(width: 1, color: Colors.deepPurple),
                borderRadius: BorderRadius.circular(5))),
      ),
    );
  }
}
