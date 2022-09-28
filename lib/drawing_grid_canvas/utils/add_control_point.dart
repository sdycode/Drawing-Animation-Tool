  import 'package:flutter/material.dart';

import '../drawing_grid_canvas_fields.dart';
import 'get_lower_value_from_pair.dart';

void addControlPointIfNeeded(TapUpDetails d) {
    controlMidPoints[getLowerFromPair(controlPointAdjecntPair)] =
        d.localPosition;
  }