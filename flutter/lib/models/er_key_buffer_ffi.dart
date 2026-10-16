import 'dart:async';

import '../common.dart';
import 'model.dart';

/// Electronics Remote: volvió la imagen tras una reconexión; se manda lo que
/// la persona escribió mientras no había conexión.
void erFlushSavedKeys(FFI ffi) {
  final buf = ffi.inputModel.erKeys;
  if (!buf.isDown) return;
  // Un respiro para que el equipo termine de acomodar la sesión.
  Timer(const Duration(milliseconds: 400), () async {
    if (ffi.closed) return;
    final sent = await buf.markUpAndFlush(ffi.inputModel.erSendSaved);
    if (sent > 0) {
      showToast(sent == 1
          ? 'Se mandó 1 tecla que quedó guardada'
          : 'Se mandaron $sent teclas que quedaron guardadas');
    }
  });
}

/// Aviso en pantalla la primera vez que algo se guarda sin conexión.
void Function(int, bool) erKeyBufferNotice() {
  var told = false;
  return (int pending, bool down) {
    if (!down) {
      told = false;
      return;
    }
    if (pending > 0 && !told) {
      told = true;
      showToast('Sin conexión: guardo lo que escribes y lo mando al volver');
    }
  };
}
