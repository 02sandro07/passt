import 'package:flutter_test/flutter_test.dart';

import 'package:passt/main.dart';

void main() {
  test('alle Store-Produkte der drei Stufen sind hinterlegt', () {
    expect(products.keys, containsAll([
      'passt_genau',
      'passt_genau_geschenk',
      'passt_alle_event',
      'passt_alle_verein',
    ]));
  });
}
