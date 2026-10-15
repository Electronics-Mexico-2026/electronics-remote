// Electronics Remote: F8 abre el menú de la sesión (como en RealVNC) en lugar
// de mandarse al equipo remoto. «Enviar F8» del mismo menú lo manda.
// Archivo sin dependencias de escritorio para poder usarlo desde InputModel.

import 'package:flutter/foundation.dart';

final Map<String, VoidCallback> _erF8Openers = {};

void erRegisterF8Opener(String sessionKey, VoidCallback opener) {
  _erF8Openers[sessionKey] = opener;
}

void erUnregisterF8Opener(String sessionKey, VoidCallback opener) {
  if (_erF8Openers[sessionKey] == opener) {
    _erF8Openers.remove(sessionKey);
  }
}

/// true si hay menú para esta sesión (la tecla ya no va al remoto).
bool erHasF8Opener(String sessionKey) => _erF8Openers.containsKey(sessionKey);

void erOpenF8Menu(String sessionKey) => _erF8Openers[sessionKey]?.call();
