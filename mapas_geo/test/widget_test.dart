import 'package:flutter_test/flutter_test.dart';
import 'package:mapas_geo/main.dart';

void main() {
  testWidgets('Muestra el localizador y sus estados iniciales', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Localizador de Puntos'), findsOneWidget);
    expect(find.text('Obteniendo ubicación...'), findsOneWidget);
    expect(find.text('Toca el mapa para elegir un destino'), findsOneWidget);
  });
}
