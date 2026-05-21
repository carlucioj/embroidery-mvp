import 'package:embroidery_mvp/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App starts without crashing', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(EmbroideryApp(prefs: prefs));
    await tester.pump();

    // App should render without throwing
    expect(tester.takeException(), isNull);
  });
}
