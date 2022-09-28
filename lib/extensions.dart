

import 'package:flutter/material.dart';

extension DeviceScaleWidthNew on num {
  double sw(BuildContext context) {
    return this * (MediaQuery.of(context).size.width / 100).toDouble();
  }
}

extension DeviceScaleHeightNew on num {
  double sh(BuildContext context) {
    return this * (MediaQuery.of(context).size.height / 100).toDouble();
  }
}