import 'package:flutter_hbb/common/er_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compara por er.N y nunca reinstala la misma', () {
    expect(erIsNewer('1.5.0-er.20', '1.5.0-er.19'), isTrue);
    expect(erIsNewer('1.5.0-er.10', '1.5.0-er.9'), isTrue);
    expect(erIsNewer('1.5.0-er.19', '1.5.0-er.19'), isFalse);
    expect(erIsNewer('1.5.0-er.18', '1.5.0-er.19'), isFalse);
    expect(erIsNewer('1.5.1-er.1', '1.5.0-er.99'), isTrue);
    expect(
        erIsNewer(
            'https://github.com/Electronics-Mexico-2026/electronics-remote/releases/tag/electronics-remote-1.5.0-er.21',
            '1.5.0-er.20'),
        isTrue);
    expect(erIsNewer('electronics-remote-1.5.0-er.20', '1.5.0-er.20'), isFalse);
    expect(erIsNewer('basura', '1.5.0-er.3'), isFalse);
  });
}
