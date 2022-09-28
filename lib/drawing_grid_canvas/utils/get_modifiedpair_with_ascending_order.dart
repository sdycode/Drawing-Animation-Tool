import '../models/pair_model.dart';

Pair getModifiedPairwithAscendingOrder(Pair pair) {
  if (pair.preIndex < pair.nextIndex) {
    return pair;
  } else {
    int temp = pair.preIndex;
    pair.preIndex = pair.nextIndex;

    pair.nextIndex = temp;
    return pair;
  }
}