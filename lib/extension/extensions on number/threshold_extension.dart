import 'package:animated_icon_demo/constants/math%20constants.dart';

extension ThresholdNum on double {
  double threshold() {
    if (this < thresholdValueNearAndAboveZero && this > 0) {
      return 0.0;
    }
    if (this < 0 && this > -thresholdValueNearAndAboveZero) {
      return 0.0;
    }
    return this;
  }
  // ···
}
