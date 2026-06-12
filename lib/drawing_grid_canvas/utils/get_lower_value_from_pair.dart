
import '../models/pair_model.dart';

int getLowerFromPair(Pair pair) {
  if (pair.preIndex < pair.nextIndex) {
    return pair.preIndex;
  }
  return pair.nextIndex;
 
}