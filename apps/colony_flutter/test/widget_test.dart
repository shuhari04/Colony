// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:colony_flutter/src/bridge/bridge_server_controller.dart';
import 'package:colony_flutter/src/design/theme.dart';
import 'package:colony_flutter/src/state/app_state.dart';
import 'package:colony_flutter/src/ui/world/world_screen.dart';

void main() {
  testWidgets('App boots', (WidgetTester tester) async {
    final state = AppState();
    final bridge = BridgeServerController();
    await tester.pumpWidget(
      MaterialApp(
        theme: ColonyTheme.dark(),
        home: WorldScreen(state: state, bridgeController: bridge),
      ),
    );
    expect(find.byType(WorldScreen), findsOneWidget);
  });
}
