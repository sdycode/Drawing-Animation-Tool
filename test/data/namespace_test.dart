// Regression guard for the v2 Firestore data-isolation contract.
//
// All new (version-2) data must live under `appData/v2/users/...` so the
// legacy top-level `users` collection is never read or written. If someone
// accidentally reverts the namespace in `DataService`, this test fails in CI
// before any data can land in the wrong place.
import 'package:flutter_test/flutter_test.dart';
import 'package:animated_icon_demo/service/firebase_service.dart';

void main() {
  group('v2 Firestore data namespace', () {
    test('root collection is the isolated app namespace, not legacy', () {
      expect(DataService.kRootCollection, 'appData');
      // Must NOT be the legacy top-level collection.
      expect(DataService.kRootCollection, isNot('users'));
    });

    test('data version is v2', () {
      expect(DataService.kDataVersion, 'v2');
    });
  });
}
