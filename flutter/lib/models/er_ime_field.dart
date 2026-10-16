// Electronics Remote (Android): el campo oculto que recibe el teclado del
// celular.
//
// El campo empieza lleno de «1» de relleno para que el retroceso siempre
// llegue. Antes se comparaba solo por el largo o por el prefijo común, y eso
// suponía que el cursor del teclado estaba al final. Cuando el teclado lo
// movía (deslizar en la barra espaciadora, flechas del teclado Samsung,
// sugerencias), cada letra se mandaba como el último carácter del campo,
// un «1», o se mandaba el relleno completo.
//
// Aquí la diferencia usa la posición del cursor y nunca manda el relleno.

class ErImeEdit {
  final int backspaces;
  final String insert;
  const ErImeEdit(this.backspaces, this.insert);

  @override
  String toString() => 'ErImeEdit($backspaces, "$insert")';
}

class ErImeField {
  /// Con menos relleno que esto (o con el campo demasiado largo) se rellena.
  static const int minPad = 256;
  static const int maxLength = 8192;

  final String initText;
  String _value;
  int _pad;
  bool _caretAtEnd = true;

  ErImeField(this.initText)
      : _value = initText,
        _pad = initText.length;

  String get value => _value;

  /// El campo debe volver a [initText] con el cursor al final (en cuanto el
  /// teclado no esté componiendo una palabra).
  bool get needsReset =>
      !_caretAtEnd || _pad < minPad || _value.length > maxLength;

  void reset() {
    _value = initText;
    _pad = initText.length;
    _caretAtEnd = true;
  }

  /// [caret] es dónde quedó el cursor después del cambio; -1 si no se sabe.
  ErImeEdit apply(String newValue, int caret) {
    final old = _value;
    _value = newValue;
    _caretAtEnd = caret < 0 || caret >= newValue.length;

    final minLen = old.length < newValue.length ? old.length : newValue.length;
    var p = 0;
    while (p < minLen && old.codeUnitAt(p) == newValue.codeUnitAt(p)) {
      p++;
    }
    if (p > 0 && p < newValue.length && _isHigh(newValue.codeUnitAt(p - 1))) {
      p--;
    }

    // Lo que está después del cursor no cambió (solo si el cursor no está al
    // final: con el cursor al final, una sugerencia que reemplaza la palabra
    // tiene que borrarla completa en el equipo).
    var s = 0;
    if (!_caretAtEnd) {
      final room = minLen - p;
      final afterCaret = newValue.length - caret;
      final maxS = afterCaret < room ? afterCaret : room;
      while (s < maxS &&
          old.codeUnitAt(old.length - 1 - s) ==
              newValue.codeUnitAt(newValue.length - 1 - s)) {
        s++;
      }
      if (s > 0 && _isLow(newValue.codeUnitAt(newValue.length - s))) s--;
    }

    final removed = old.substring(p, old.length - s);
    final insert = newValue.substring(p, newValue.length - s);

    var inPad = _pad - p;
    if (inPad < 0) inPad = 0;
    if (inPad > removed.length) inPad = removed.length;
    final typedRemoved = removed.substring(inPad).runes.length;
    if (p < _pad) _pad = p;

    var backspaces = typedRemoved;
    // Borrar dentro del relleno es un retroceso de verdad en el equipo, pero
    // uno solo aunque el teclado borre la «palabra» de 1 completa. Si el
    // teclado reescribe el relleno junto con una palabra, no cuenta.
    if (insert.isEmpty && typedRemoved == 0 && inPad > 0) backspaces = 1;
    return ErImeEdit(backspaces, insert);
  }

  static bool _isHigh(int c) => c >= 0xD800 && c <= 0xDBFF;
  static bool _isLow(int c) => c >= 0xDC00 && c <= 0xDFFF;
}
