import 'package:drawing_animation_tool/app/common/number_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ▲▼ steppers on [CommittedNumberField].
///
/// The field is the one control every numeric row in the inspector is made of,
/// so these are pinned at the widget level rather than through the panel: a
/// regression here is a regression in fourteen rows at once.
///
/// The host below **echoes each commit back as the field's `value`**, which is
/// what the real inspector does when the document round-trips. Without that
/// echo the `_pending` bookkeeping is never exercised and a double-commit bug
/// would pass.
void main() {
  late List<double> commits;
  late List<String> spans;

  setUp(() {
    commits = <double>[];
    spans = <String>[];
  });

  Future<void> pumpField(
    WidgetTester tester, {
    double initial = 0,
    double? step,
    double? min,
    double? max,
    bool enabled = true,
    int decimals = 3,
  }) async {
    var value = initial;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 220,
            child: StatefulBuilder(
              builder: (context, setState) => CommittedNumberField(
                key: const Key('f'),
                value: value,
                step: step,
                min: min,
                max: max,
                enabled: enabled,
                decimals: decimals,
                onStepStart: () => spans.add('start'),
                onStepEnd: () => spans.add('end'),
                onCommit: (v) {
                  commits.add(v);
                  setState(() => value = v);
                },
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder arrow(IconData icon) => find.descendant(
        of: find.byKey(const Key('f')),
        matching: find.byIcon(icon),
      );

  Finder up() => arrow(Icons.keyboard_arrow_up);
  Finder down() => arrow(Icons.keyboard_arrow_down);

  String shown(WidgetTester tester) => tester
      .widget<EditableText>(find.descendant(
        of: find.byKey(const Key('f')),
        matching: find.byType(EditableText),
      ))
      .controller
      .text;

  // --- The field without a step is untouched --------------------------------

  testWidgets('no step means no steppers — the field is exactly as it was',
      (tester) async {
    await pumpField(tester);

    expect(up(), findsNothing);
    expect(down(), findsNothing);

    await tester.enterText(find.byKey(const Key('f')), '12.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(commits, [12.5]);
  });

  // --- One click, one step --------------------------------------------------

  testWidgets('a click on ▲ / ▼ commits exactly one increment',
      (tester) async {
    await pumpField(tester, initial: 10, step: 1);

    await tester.tap(up());
    await tester.pumpAndSettle();
    expect(commits, [11.0]);
    expect(shown(tester), '11');

    await tester.tap(down());
    await tester.pumpAndSettle();
    await tester.tap(down());
    await tester.pumpAndSettle();
    expect(commits, [11.0, 10.0, 9.0]);
    expect(shown(tester), '9');
  });

  testWidgets('a press opens and closes the caller\'s coalescing span once',
      (tester) async {
    await pumpField(tester, initial: 0, step: 1);

    await tester.tap(up());
    await tester.pumpAndSettle();

    expect(spans, ['start', 'end'],
        reason: 'the whole press is one span — one undo entry for the caller');
  });

  // --- Press and hold -------------------------------------------------------

  testWidgets('holding ▲ repeats, and the whole hold is ONE span',
      (tester) async {
    await pumpField(tester, initial: 0, step: 1);

    final gesture = await tester.startGesture(tester.getCenter(up()));
    await tester.pump(); // the press itself steps once
    expect(commits, [1.0],
        reason: 'a hold nudges immediately, not after a wait');

    // Past the delay, into the repeat.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(commits.length, greaterThan(4),
        reason: 'the button auto-repeats while it is held');
    expect(commits.last, commits.length.toDouble(),
        reason: 'every repeat is one more increment, in order');
    expect(spans, ['start', 'end'],
        reason: 'a 10-nudge hold must still be ONE undo entry');
  });

  testWidgets('the repeat stops the moment the pointer is released',
      (tester) async {
    await pumpField(tester, initial: 0, step: 1);

    final gesture = await tester.startGesture(tester.getCenter(up()));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();

    final settled = commits.length;
    await tester.pump(const Duration(seconds: 1));
    expect(commits.length, settled,
        reason: 'a released button must not keep counting');
  });

  // --- Bounds ---------------------------------------------------------------

  testWidgets('the stepper stops at min and max instead of emitting refusals',
      (tester) async {
    await pumpField(tester, initial: 100, step: 1, min: 0, max: 100);

    await tester.tap(up());
    await tester.pumpAndSettle();
    expect(commits, isEmpty, reason: '▲ at the ceiling writes nothing');
    expect(shown(tester), '100');

    await tester.tap(down());
    await tester.pumpAndSettle();
    expect(commits, [99.0]);
  });

  testWidgets('a step that would cross a bound lands ON it', (tester) async {
    await pumpField(tester, initial: 3, step: 10, min: 0, max: 100);

    await tester.tap(down());
    await tester.pumpAndSettle();
    expect(commits, [0.0], reason: '3 − 10 clamps to the floor, not to −7');
  });

  // --- Modifiers ------------------------------------------------------------

  testWidgets('Shift multiplies the increment by ten', (tester) async {
    await pumpField(tester, initial: 0, step: 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(up());
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    expect(commits, [10.0]);
  });

  testWidgets('Alt divides it by ten', (tester) async {
    await pumpField(tester, initial: 0, step: 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.tap(up());
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

    expect(commits, [0.1]);
  });

  // --- Where the step starts from -------------------------------------------

  testWidgets('it steps from the text on screen, not from the last commit',
      (tester) async {
    await pumpField(tester, initial: 12, step: 1);

    // Typed but never submitted — the document still holds 12.
    await tester.enterText(find.byKey(const Key('f')), '40');
    await tester.pump();

    await tester.tap(up());
    await tester.pumpAndSettle();

    expect(commits, [41.0],
        reason: 'someone who typed 40 and pressed ▲ means 41');
  });

  testWidgets('repeated fractional steps do not accumulate binary dust',
      (tester) async {
    await pumpField(tester, initial: 0.2, step: 0.1);

    await tester.tap(up());
    await tester.pumpAndSettle();

    expect(commits, [0.3],
        reason: '0.2 + 0.1 must be 0.3, not 0.30000000000004');
    expect(shown(tester), '0.3');
  });

  // --- Keyboard -------------------------------------------------------------

  testWidgets('↑ and ↓ step the focused field', (tester) async {
    await pumpField(tester, initial: 5, step: 1);

    await tester.tap(find.byKey(const Key('f')));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(commits, [6.0, 5.0, 4.0]);
  });

  // --- Disabled -------------------------------------------------------------

  testWidgets('a disabled field does not step', (tester) async {
    await pumpField(tester, initial: 0, step: 1, enabled: false);

    await tester.tap(up(), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(commits, isEmpty);
    expect(spans, isEmpty, reason: 'no span is opened for a refused press');
  });
}
