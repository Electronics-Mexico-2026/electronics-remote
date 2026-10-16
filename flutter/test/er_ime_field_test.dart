import 'package:flutter_hbb/models/er_ime_field.dart';
import 'package:flutter_test/flutter_test.dart';

final pad = '1' * 1024;

/// Lo que hace el teclado: escribe [text] donde está el cursor.
String typeAt(String v, int caret, String text) =>
    v.substring(0, caret) + text + v.substring(caret);

void main() {
  test('cursor movido por el teclado: las letras llegan como letras, no «1»',
      () {
    final f = ErImeField(pad);
    f.apply('${pad}abc', pad.length + 3);
    // El teclado mueve el cursor 3 a la izquierda (solo selección) y se
    // escribe «hola».
    var v = f.value;
    var caret = v.length - 3;
    final sent = <String>[];
    for (final ch in 'hola'.split('')) {
      v = typeAt(v, caret, ch);
      caret++;
      final e = f.apply(v, caret);
      expect(e.backspaces, 0);
      sent.add(e.insert);
    }
    expect(sent, ['h', 'o', 'l', 'a']);
    expect(f.needsReset, isTrue);
  });

  test('cursor al inicio del campo: no se manda el relleno de «1»', () {
    final f = ErImeField(pad);
    final e = f.apply('x$pad', 1);
    expect([e.backspaces, e.insert], [0, 'x']);
  });

  test('el teclado reescribe el relleno junto con la palabra', () {
    final f = ErImeField(pad);
    f.apply('${pad}hola', pad.length + 4);
    // Samsung toma «1111hola» como una palabra y la cambia por «Hola».
    final v = '${pad.substring(4)}Hola';
    final e = f.apply(v, v.length);
    expect([e.backspaces, e.insert], [4, 'Hola']);
    // y lo de siempre sigue igual: sugerencia al final, retroceso, palabra
    // de «1» borrada de golpe = un solo retroceso.
    final g = ErImeField(pad);
    g.apply('${pad}teh', pad.length + 3);
    var d = g.apply('${pad}the ', pad.length + 4);
    expect([d.backspaces, d.insert], [2, 'he ']);
    d = g.apply('$pad', pad.length);
    expect([d.backspaces, d.insert], [4, '']);
    d = g.apply(pad.substring(1), pad.length - 1);
    expect([d.backspaces, d.insert], [1, '']);
    d = g.apply('', 0);
    expect([d.backspaces, d.insert], [1, '']);
  });
}
