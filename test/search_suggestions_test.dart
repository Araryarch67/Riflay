import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riflay/ui/pages/search/search_box.dart';
import 'package:riflay/ui/pages/search/search_input.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('the Liquid glass bar\'s field shows recent searches on the page, and a pick searches', (tester) async {
    SharedPreferences.setMockInitialValues({
      'search.recent.v1': ['houshou marine', 'kyapi'],
    });
    final input = SearchInput();
    addTearDown(input.dispose);
    final searched = <String>[];
    input.submitted.addListener(() => searched.add(input.submitted.value.$1));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SearchSuggestions(input: input),
              const Spacer(),
              // Where the bar carries the field.
              TextField(controller: input.controller, focusNode: input.focus),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Recent searches'), findsNothing, reason: 'not before the field has the focus');

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('Recent searches'), findsOneWidget);
    expect(find.text('houshou marine'), findsOneWidget);
    expect(find.text('kyapi'), findsOneWidget);

    await tester.tap(find.text('kyapi'));
    await tester.pumpAndSettle();
    expect(searched, ['kyapi']);
    expect(input.controller.text, 'kyapi');
    expect(input.focus.hasFocus, isFalse);
    expect(find.text('Recent searches'), findsNothing);
  });
}
