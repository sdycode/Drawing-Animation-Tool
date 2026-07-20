import 'package:flutter/material.dart';

class TextWithStyle1 extends StatefulWidget {
  final text;
  final Function? onTap;
  final fontsize;
  final ignoreTap;

  const TextWithStyle1(
      {Key? key, required this.text, this.onTap, this.fontsize = 20, this.ignoreTap = false})
      : super(key: key);

  @override
  State<TextWithStyle1> createState() => _TextWithStyle1State();
}

class _TextWithStyle1State extends State<TextWithStyle1> {
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: widget.ignoreTap,
      child: InkWell(
        onTap: () {
          if (widget.onTap == null) {
          } else {
            widget.onTap!();
          }
        },
        child: Text(
          widget.text,
          style: Theme.of(context)
              .textTheme
              .displayMedium
              ?.copyWith(fontSize: widget.fontsize),
        ),
      ),
    );
  }
}
