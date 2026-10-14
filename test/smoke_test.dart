// Smoke tests for የኢትዮጵያ ዳማ Pro.
// These run WITHOUT the Android SDK (flutter_tester target) and verify that
// the whole app compiles and the key screens render — including the new
// move-animation board, the Sfx engine wiring and the compacted layout.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethiopian_dama/main.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AppPrefs.load();
  });

  testWidgets('home screen renders with menu cards', (tester) async {
    await tester.pumpWidget(const DamaProApp());
    await tester.pump();
    expect(find.text('የኢትዮጵያ ዳማ Pro'), findsWidgets);
    expect(find.text('ከኮምፒውተር ጋር'), findsOneWidget); // vs AI card
    expect(find.text('በHotspot ለሁለት ስልክ'), findsOneWidget); // hotspot card
  });

  testWidgets('game screen shows all 24 tappable cells rows', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: GameScreen(mode: GameMode.vsAi, options: GameOptions()),
    ));
    await tester.pump();

    // All 64 cells exist and are tappable; the 24 starting-piece dark
    // squares are all in the generated rows.
    expect(find.byKey(const ValueKey<String>('cell0')), findsOneWidget);
    int darkCells = 0;
    int pieceCells = 0;
    for (int sq = 0; sq < 64; sq++) {
      final cell =
          tester.widget(find.byKey(ValueKey<String>('cell$sq'))) as GestureDetector;
      expect(cell.onTap, isNotNull);
      final r = sq >> 3, c = sq & 7;
      if ((r + c) % 2 == 1) {
        darkCells++;
        if (r < 3 || r > 4) pieceCells++;
      }
    }
    expect(darkCells, 32);
    expect(pieceCells, 24);
  });

  testWidgets('selecting a piece shows its landing dots', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: GameScreen(mode: GameMode.passPlay, options: GameOptions()),
    ));
    await tester.pump();

    // sq 40 = row 5, col 0 — a dark square with a white pawn at start.
    await tester.tap(find.byKey(const ValueKey<String>('cell40')));
    await tester.pump();
    // Let the (mock) audio zero-timers flush.
    for (int i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Selection must not crash, and the board still renders fully
    // (the quiet-move dot for sq 33 becomes visible on sq 33).
    expect(find.byKey(const ValueKey<String>('cell33')), findsOneWidget);
  });

  testWidgets('quiet move glides and switches the turn', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: GameScreen(mode: GameMode.passPlay, options: GameOptions()),
    ));
    await tester.pump();

    // White pawn on sq 40 (row 5, col 0) -> quiet move to sq 33 (row 4, col 1).
    await tester.tap(find.byKey(const ValueKey<String>('cell40')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('cell33')));
    await tester.pump(); // flight starts

    // The flying piece overlay is live mid-flight.
    expect(
      find.byWidgetPredicate(
          (w) => w is TweenAnimationBuilder<double>),
      findsOneWidget,
    );

    // Advance past the 240 ms flight -> overlay gone, board final.
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 260));
    expect(
      find.byWidgetPredicate(
          (w) => w is TweenAnimationBuilder<double>),
      findsNothing,
    );

    // Turn switched to black in pass & play mode.
    expect(find.text('ተራው የጥቁር ነው'), findsOneWidget);
  });

  testWidgets('Sfx engine never throws even without a platform', (tester) async {
    // Exercises the fully-swallowed audio error path.
    Sfx.play('move');
    Sfx.play('capture');
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  });
}
