// Electronics Remote: búfer de teclado como el de RealVNC.
//
// Si la conexión se cae (o se está reconectando) lo que la persona escribe
// no se pierde: se guarda aquí y, en cuanto vuelve la primera imagen del
// equipo, se manda en el mismo orden.
//
// Además, las teclas mandadas justo antes de la caída que el equipo quizá no
// recibió (no llegó ninguna imagen después de ellas) se vuelven a mandar: un
// socket muerto acepta escrituras durante varios segundos antes de que el
// cliente se entere de que la conexión ya no sirve.
//
// También lleva la «vista previa» (como el campo de VNC Viewer): las últimas
// letras escritas, para mostrarlas arriba del teclado del celular.

import 'package:flutter/foundation.dart';

/// Una entrada guardada: una tecla (con sus modificadores de ese momento) o un
/// texto completo (lo que el teclado del celular manda de golpe).
class ErKeyEntry {
  final String? key;
  final String? text;
  final bool down;
  final bool press;
  final bool alt;
  final bool ctrl;
  final bool shift;
  final bool command;
  DateTime at;

  ErKeyEntry.key(
    String name, {
    required this.down,
    required this.press,
    required this.alt,
    required this.ctrl,
    required this.shift,
    required this.command,
    required this.at,
  })  : key = name,
        text = null;

  ErKeyEntry.text(String value, {required this.at})
      : key = null,
        text = value,
        down = false,
        press = true,
        alt = false,
        ctrl = false,
        shift = false,
        command = false;

  /// Cuántos caracteres/teclas representa (para el aviso).
  int get weight => text?.length ?? (down || press ? 1 : 0);

  @override
  String toString() => text != null ? 'text($text)' : 'key($key)';
}

typedef ErKeySender = void Function(ErKeyEntry e);

class ErKeyBuffer {
  /// Tope de lo guardado sin conexión (una página larga de texto).
  static const int maxPending = 4000;

  /// Una tecla cuenta como recibida cuando llega una imagen del equipo al
  /// menos este tiempo después de mandarla.
  static const Duration frameGrace = Duration(milliseconds: 800);

  /// Nunca se reenvía nada mandado hace más de esto antes de la caída.
  static const Duration resendWindow = Duration(seconds: 20);

  /// Pausa entre envíos al vaciar el búfer (que el equipo no se atragante).
  static const Duration flushGap = Duration(milliseconds: 12);

  final DateTime Function() now;
  ErKeyBuffer({DateTime Function()? now}) : now = now ?? DateTime.now;

  bool _down = false;
  bool _flushing = false;
  final List<ErKeyEntry> _pending = [];
  final List<ErKeyEntry> _recent = [];

  /// Se llama cada vez que algo cambia (para el aviso en pantalla).
  void Function(int pendingChars, bool down)? onChanged;

  /// Largo máximo de la vista previa.
  static const int previewMax = 200;

  /// Lo último que se escribió (se borra con el retroceso).
  final ValueNotifier<String> preview = ValueNotifier('');

  /// Caracteres guardados que todavía no llegan al equipo.
  final ValueNotifier<int> pendingNotifier = ValueNotifier(0);

  /// Sin conexión (o reconectando).
  final ValueNotifier<bool> downNotifier = ValueNotifier(false);

  void clearPreview() => preview.value = '';

  void _addPreview(ErKeyEntry e) {
    var v = preview.value;
    if (e.text != null) {
      v += e.text!.replaceAll(String.fromCharCode(10), '⏎');
    } else if (e.down || e.press) {
      final k = e.key!;
      if (e.ctrl || e.alt || e.command) {
        // atajos (Ctrl+C…) no son texto
      } else if (k == 'VK_BACK') {
        if (v.isNotEmpty) {
          final r = v.runes.toList()..removeLast();
          v = String.fromCharCodes(r);
        }
      } else if (k == 'VK_SPACE') {
        v += ' ';
      } else if (k == 'VK_RETURN') {
        v += '⏎';
      } else if (k == 'VK_TAB') {
        v += '⇥';
      } else if (k.runes.length == 1) {
        v += k;
      }
    }
    final r = v.runes;
    if (r.length > previewMax) {
      v = String.fromCharCodes(r.skip(r.length - previewMax));
    }
    preview.value = v;
  }

  bool get isDown => _down;
  bool get isFlushing => _flushing;
  int get pendingCount => _pending.length;
  int get pendingChars => _pending.fold(0, (a, e) => a + e.weight);
  List<ErKeyEntry> get pendingForTest => List.unmodifiable(_pending);

  void _notify() {
    pendingNotifier.value = pendingChars;
    downNotifier.value = _down;
    onChanged?.call(pendingChars, _down);
  }

  /// Llegó una imagen del equipo: lo mandado hasta hace [frameGrace] llegó.
  void onFrame() {
    if (_recent.isEmpty) return;
    final cutoff = now().subtract(frameGrace);
    _recent.removeWhere((e) => !e.at.isAfter(cutoff));
  }

  /// Devuelve true si la entrada se guardó (no hay conexión) y el que llama
  /// NO debe mandarla. Si devuelve false, el que llama la manda y aquí queda
  /// anotada como «sin confirmar» hasta la siguiente imagen.
  bool offer(ErKeyEntry e) {
    _addPreview(e);
    if (_down || _flushing) {
      if (_pending.length < maxPending) {
        _pending.add(e);
        _notify();
      }
      return true;
    }
    final t = now();
    e.at = t;
    _recent.add(e);
    final old = t.subtract(resendWindow);
    while (_recent.isNotEmpty && _recent.first.at.isBefore(old)) {
      _recent.removeAt(0);
    }
    if (_recent.length > maxPending) _recent.removeAt(0);
    return false;
  }

  /// La conexión se cayó o se está reconectando.
  void markDown() {
    if (_down) return;
    _down = true;
    // Lo mandado sin imagen posterior se vuelve a poner al frente.
    final old = now().subtract(resendWindow);
    var unconfirmed = _recent.where((e) => e.at.isAfter(old)).toList();
    _recent.clear();
    // Un Enter o un atajo (Ctrl+V, Alt+F4…) repetido hace daño si sí había
    // llegado: no se reenvía ni lo de antes, solo lo escrito después.
    final last = unconfirmed.lastIndexWhere((e) =>
        e.ctrl || e.alt || e.command || e.key == 'VK_RETURN' ||
        (e.text?.contains('\n') ?? false));
    if (last >= 0) unconfirmed = unconfirmed.sublist(last + 1);
    if (unconfirmed.isNotEmpty) {
      _pending.insertAll(0, unconfirmed);
      if (_pending.length > maxPending) {
        _pending.removeRange(maxPending, _pending.length);
      }
    }
    _notify();
  }

  /// Volvió la imagen: se manda todo lo guardado, en orden. Devuelve cuántos
  /// caracteres/teclas se mandaron.
  Future<int> markUpAndFlush(ErKeySender send,
      {Future<void> Function(Duration)? sleep}) async {
    if (!_down) return 0;
    _down = false;
    if (_pending.isEmpty) {
      _notify();
      return 0;
    }
    _flushing = true;
    var sent = 0;
    final wait = sleep ?? (d) => Future.delayed(d);
    try {
      while (_pending.isNotEmpty) {
        if (_down) break; // se volvió a caer: lo que falta sigue guardado
        final e = _pending.removeAt(0);
        send(e);
        e.at = now();
        _recent.add(e);
        sent += e.weight;
        await wait(flushGap);
      }
    } finally {
      _flushing = false;
      _notify();
    }
    return sent;
  }

  /// Se cerró la sesión: lo guardado ya no tiene a dónde ir.
  void clear() {
    _down = false;
    _flushing = false;
    _pending.clear();
    _recent.clear();
    preview.value = '';
    _notify();
  }
}

/// Diferencia entre lo que había en el campo oculto y lo que hay ahora: cuántos
/// caracteres borrar del final y qué texto escribir después. Sirve cuando el
/// teclado del celular reemplaza una palabra (autocorrector, sugerencias,
/// borrar palabra completa), no solo cuando agrega o quita una letra.
class ErTextDiff {
  final int backspaces;
  final String insert;
  const ErTextDiff(this.backspaces, this.insert);

  static ErTextDiff of(String oldValue, String newValue) {
    var p = 0;
    final n = oldValue.length < newValue.length ? oldValue.length : newValue.length;
    while (p < n && oldValue.codeUnitAt(p) == newValue.codeUnitAt(p)) {
      p++;
    }
    // No partir un par sustituto (emoji) a la mitad.
    if (p > 0 && p < newValue.length) {
      final c = newValue.codeUnitAt(p - 1);
      if (c >= 0xD800 && c <= 0xDBFF) p--;
    }
    final removed = oldValue.substring(p);
    return ErTextDiff(removed.runes.length, newValue.substring(p));
  }

  @override
  String toString() => 'ErTextDiff($backspaces, "$insert")';
}
