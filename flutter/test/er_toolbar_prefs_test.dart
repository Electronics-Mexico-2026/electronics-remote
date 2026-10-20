import 'dart:convert';

import 'package:flutter_hbb/common/er_toolbar_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('guardar posición conserva el pin que ya estaba', () {
    final raw = ErToolbarPrefs.merge('{"pin":true}',
        edge: 'left', fraction: 0.2);
    final p = ErToolbarPrefs.parse(raw);
    expect(p.pin, isTrue);
    expect(p.edge, 'left');
    expect(p.fraction, 0.2);
    expect(p.collapsed, isNull);
  });

  test('guardar escondida conserva borde y posición', () {
    var raw = ErToolbarPrefs.merge(null, edge: 'bottom', fraction: 0.9);
    raw = ErToolbarPrefs.merge(raw, collapsed: true);
    raw = ErToolbarPrefs.merge(raw, pin: false);
    expect(jsonDecode(raw),
        {'edge': 'bottom', 'fraction': 0.9, 'collapsed': true, 'pin': false});
  });

  test('valores dañados se ignoran', () {
    final p = ErToolbarPrefs.parse(
        '{"pin":"si","edge":"centro","fraction":7,"collapsed":1}');
    expect(p.pin, isNull);
    expect(p.edge, isNull);
    expect(p.fraction, 1.0);
    expect(p.collapsed, isNull);
    expect(ErToolbarPrefs.parse('no es json').edge, isNull);
  });
}
