import 'package:flutter_hbb/models/er_key_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

ErKeyEntry k(String name, DateTime t) => ErKeyEntry.key(name,
    down: false,
    press: true,
    alt: false,
    ctrl: false,
    shift: false,
    command: false,
    at: t);

void main() {
  test('lo escrito sin conexión se manda en orden al volver', () async {
    var t = DateTime(2026, 10, 16, 14, 0, 0);
    final b = ErKeyBuffer(now: () => t);
    b.markDown();
    expect(b.offer(ErKeyEntry.text('hola ', at: t)), isTrue);
    expect(b.offer(k('VK_BACK', t)), isTrue);
    expect(b.offer(ErKeyEntry.text('mundo', at: t)), isTrue);
    final sent = <String>[];
    final n = await b.markUpAndFlush((e) => sent.add(e.toString()),
        sleep: (_) async {});
    expect(sent, ['text(hola )', 'key(VK_BACK)', 'text(mundo)']);
    expect(n, 11);
    expect(b.offer(k('a', t)), isFalse); // ya hay conexión: se manda directo
  });

  test('lo mandado sin imagen posterior se reenvía; lo confirmado no',
      () async {
    var t = DateTime(2026, 10, 16, 14, 0, 0);
    final b = ErKeyBuffer(now: () => t);
    expect(b.offer(k('a', t)), isFalse);
    t = t.add(const Duration(seconds: 1));
    b.onFrame(); // llegó imagen 1 s después: «a» llegó
    expect(b.offer(k('b', t)), isFalse);
    t = t.add(const Duration(milliseconds: 100));
    expect(b.offer(k('c', t)), isFalse);
    t = t.add(const Duration(seconds: 15)); // el enlace murió sin avisar
    b.markDown();
    expect(b.pendingForTest.map((e) => e.key), ['b', 'c']);
    final sent = <String?>[];
    await b.markUpAndFlush((e) => sent.add(e.key), sleep: (_) async {});
    expect(sent, ['b', 'c']);
  });

  test('un Enter sin confirmar no se reenvía (ni lo de antes)', () async {
    var t = DateTime(2026, 10, 16, 14, 0, 0);
    final b = ErKeyBuffer(now: () => t);
    for (final n in ['l', 's', 'VK_RETURN', 'p']) {
      expect(b.offer(k(n, t)), isFalse);
      t = t.add(const Duration(milliseconds: 100));
    }
    b.markDown();
    expect(b.pendingForTest.map((e) => e.key), ['p']);
  });

  test('el teclado reemplaza o borra varias letras: se replica igual', () {
    final base = '1' * 8;
    // agregar una letra
    var d = ErTextDiff.of('${base}hol', '${base}hola');
    expect([d.backspaces, d.insert], [0, 'a']);
    // borrar una palabra completa de golpe
    d = ErTextDiff.of('${base}hola mundo', '${base}hola ');
    expect([d.backspaces, d.insert], [5, '']);
    // autocorrector del mismo largo (antes no mandaba nada)
    d = ErTextDiff.of('${base}tu', '${base}tú');
    expect([d.backspaces, d.insert], [1, 'ú']);
    // sugerencia que cambia la palabra
    d = ErTextDiff.of('${base}teh', '${base}the ');
    expect([d.backspaces, d.insert], [2, 'he ']);
  });
}
