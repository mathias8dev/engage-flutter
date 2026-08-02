import 'package:flutter_test/flutter_test.dart';

import 'package:engage_flutter_example/main.dart';

void main() {
  testWidgets('renders the example shell', (tester) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('Engage Flutter'), findsOneWidget);
    expect(find.textContaining('Installation:'), findsOneWidget);
  });
}
