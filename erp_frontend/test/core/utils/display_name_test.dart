import 'package:erp_frontend/core/utils/display_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cleanCompanyName', () {
    test('keeps real names unchanged', () {
      expect(cleanCompanyName('Shree Industries'), 'Shree Industries');
      expect(cleanCompanyName('  Manufacturing Co  '), 'Manufacturing Co');
    });

    test('replaces numeric placeholder ids with a readable fallback', () {
      expect(cleanCompanyName('123456'), 'Manufacturing Co');
      expect(cleanCompanyName(1), 'Manufacturing Co');
    });

    test('replaces blank and null-like values', () {
      expect(cleanCompanyName(null), 'Manufacturing Co');
      expect(cleanCompanyName(''), 'Manufacturing Co');
      expect(cleanCompanyName('  '), 'Manufacturing Co');
      expect(cleanCompanyName('null'), 'Manufacturing Co');
    });

    test('honours a custom fallback', () {
      expect(cleanCompanyName('', 'Plant Command Center'), 'Plant Command Center');
    });
  });
}
