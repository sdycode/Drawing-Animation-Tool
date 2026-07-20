import 'package:drawing_animation_tool/app/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app boots', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: DrawingAnimationToolApp()),
    );
    expect(find.text('Drawing Animation Tool'), findsOneWidget);
  });

  group('FeatureFallback', () {
    // docs/v3/08 §2: the default ErrorWidget takes unbounded size, so inside a
    // Row it throws AGAIN during layout — that second throw is the white screen.
    // These two tests pin the property that makes containment actually work.
    final details = FlutterErrorDetails(exception: Exception('boom'));

    testWidgets('survives tight constraints inside a Row', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Row(
            children: [
              SizedBox(
                width: 40,
                height: 30,
                child: FeatureFallback(details: details),
              ),
              const Expanded(child: Text('sibling still renders')),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('sibling still renders'), findsOneWidget);
    });

    testWidgets('survives an unbounded-height column slot', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              SizedBox(
                width: 300,
                height: 200,
                child: FeatureFallback(details: details),
              ),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
