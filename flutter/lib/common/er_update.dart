// Electronics Remote: actualizaciones desde los releases propios en GitHub
// (Electronics-Mexico-2026/electronics-remote), nunca desde rustdesk/rustdesk.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/widgets/update_progress.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:url_launcher/url_launcher.dart';

const kErReleasesUrl =
    'https://github.com/Electronics-Mexico-2026/electronics-remote/releases/latest';

bool _erChecking = false;

String erVersion() => bind.mainGetCommonSync(key: 'er-version');

/// Boton «Buscar actualizaciones» (Ajustes en Windows y Android).
Future<void> erCheckForUpdatesManually() async {
  if (_erChecking) return;
  _erChecking = true;
  try {
    showToast('Buscando actualizaciones...');
    await bind.mainSetCommon(key: 'er-check-update', value: '');
    for (int i = 0; i < 60; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      final st = await bind.mainGetCommon(key: 'er-update-state');
      if (st == 'checking' || st.isEmpty) continue;
      if (st.startsWith('available:')) {
        final url = st.substring('available:'.length);
        stateGlobal.updateUrl.value = url;
        erStartUpdate(url);
      } else if (st == 'none') {
        showToast('Ya tienes la version mas reciente (${erVersion()})');
      } else {
        showToast('No se pudo revisar si hay actualizaciones');
      }
      return;
    }
    showToast('No se pudo revisar si hay actualizaciones');
  } finally {
    _erChecking = false;
  }
}

/// Boton «Actualizar»: descarga e instala la version del release.
void erStartUpdate(String releasePageUrl) {
  if (isAndroid) {
    erUpdateApk();
  } else if (isWindows && bind.mainIsInstalled()) {
    handleUpdate(releasePageUrl);
  } else {
    launchUrl(Uri.parse(releasePageUrl));
  }
}

Future<void> erUpdateApk() async {
  final apkUrl = bind.mainGetCommonSync(key: 'er-apk-url');
  bool ok = false;
  try {
    ok = await gFFI.invokeMethod('er_update_apk', apkUrl);
  } catch (e) {
    debugPrint('er_update_apk: $e');
  }
  if (ok) {
    showToast('Descargando actualizacion... al terminar se abrira el instalador',
        timeout: const Duration(seconds: 5));
  } else {
    await launchUrl(Uri.parse(apkUrl), mode: LaunchMode.externalApplication);
  }
}
