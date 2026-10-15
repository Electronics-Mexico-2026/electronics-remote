// Electronics Remote: la sesión del panel (login) dura lo que dura el encendido
// de la PC. Al apagar o reiniciar, la próxima vez que se abre la app se pide
// iniciar sesión de nuevo; mientras siga encendida (bloqueo, suspensión), no.
//
// Marca de encendido: una clave VOLÁTIL en HKCU. Windows la borra al cerrar la
// sesión de Windows, al apagar y al reiniciar, también con «Inicio rápido»
// (que hiberna el kernel y deja intacto el contador de arranque, por eso no
// basta con comparar la hora de arranque del sistema). Suspender o bloquear no
// la borra.
//
// Solo toca access_token / user_info (lo mismo que borra el logout); no afecta
// al servicio ni al acceso remoto entrante.
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:win32/win32.dart' as win32;

const _kVolatileKey = r'Software\ElectronicsRemote\SesionEncendido';
const _kRegOptionVolatile = 0x00000001;
const _kRegCreatedNewKey = 0x00000001;
const _kKeyRead = 0x00020019;

/// true si la clave volátil no existía (primer arranque de la app desde que se
/// encendió la PC o se inició sesión en Windows). La deja creada.
bool _isFirstRunSinceBoot() {
  final subKey = _kVolatileKey.toNativeUtf16();
  final hKey = calloc<IntPtr>();
  final disposition = calloc<Uint32>();
  try {
    final rc = win32.RegCreateKeyEx(
        win32.HKEY_CURRENT_USER,
        subKey,
        0,
        nullptr,
        _kRegOptionVolatile,
        _kKeyRead,
        nullptr,
        hKey,
        disposition);
    if (rc != 0) {
      debugPrint('ER: RegCreateKeyEx volátil falló: $rc');
      return false;
    }
    win32.RegCloseKey(hKey.value);
    return disposition.value == _kRegCreatedNewKey;
  } finally {
    calloc.free(subKey);
    calloc.free(hKey);
    calloc.free(disposition);
  }
}

/// Se llama al arrancar la ventana principal, antes de leer el usuario.
Future<void> erLogoutIfNewBoot() async {
  if (!Platform.isWindows || bind.isIncomingOnly()) return;
  try {
    if (!_isFirstRunSinceBoot()) return;
    if (bind.mainGetLocalOption(key: 'access_token').isEmpty &&
        bind.mainGetLocalOption(key: 'user_info').isEmpty) {
      return;
    }
    debugPrint('ER: PC recién encendida, se cierra la sesión del panel');
    await gFFI.userModel.reset(resetOther: true);
  } catch (e) {
    debugPrint('ER: erLogoutIfNewBoot: $e');
  }
}
