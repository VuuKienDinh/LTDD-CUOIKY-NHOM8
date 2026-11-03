import 'package:flutter_test/flutter_test.dart';
import 'package:datxe/main.dart';

void main() {
  testWidgets('BusTicketBooking app renders AuthScreen', (WidgetTester tester) async {
    await tester.pumpWidget(const BusTicketBookingApp());
    expect(find.textContaining('BusTicketBooking'), findsWidgets);
  });
}
