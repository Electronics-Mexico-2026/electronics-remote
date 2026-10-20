// Electronics Remote: actualizaciones desde el bucket público propio
// (latest.json + <tag>/<archivo>); respaldo: releases de GitHub del fork.
// Nunca desde rustdesk/rustdesk.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/widgets/update_progress.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:url_launcher/url_launcher.dart';

const kErBucketUrl =
    'https://storage.googleapis.com/electronics-mexico-webhooks-fotos-publicas/electronics-remote';
const kErReleasesUrl = '$kErBucketUrl/latest.json';

bool _erChecking = false;

String erVersion() => bind.mainGetCommonSync(key: 'er-version');

/// Boton «Buscar actualizaciones» (Ajustes en Windows y Android).
Future<void> erCheckForUpdatesManually() async {
  if (_erChecking) return;
  _erChecking = true;
  try {
    showToast('Buscando actualizaciones…');
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
        showToast('Ya tienes la versión más reciente (${erVersion()}).');
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

/// «1.5.0-er.20», «electronics-remote-1.5.0-er.20» o la URL del release →
/// [mayor, menor, parche, N]. Lo que no se entiende vale 0.
List<int> erVersionKey(String v) {
  var s = v.trim();
  final slash = s.lastIndexOf('/');
  if (slash >= 0) s = s.substring(slash + 1);
  const prefix = 'electronics-remote-';
  if (s.startsWith(prefix)) s = s.substring(prefix.length);
  final parts = s.split('-er.');
  final base = parts[0].split('.').map((e) => int.tryParse(e) ?? 0).toList();
  while (base.length < 3) {
    base.add(0);
  }
  final build = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
  return [base[0], base[1], base[2], build];
}

/// ¿[latest] es más nueva que [current]? Nunca reinstala la misma.
bool erIsNewer(String latest, String current) {
  final a = erVersionKey(latest);
  final b = erVersionKey(current);
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

const _kErLastAutoCheck = 'er-update-last-auto-check';
const Duration kErAutoCheckEvery = Duration(hours: 3);

/// Android: al abrir y al volver a la app (máximo una vez cada 3 h) revisa
/// latest.json del bucket (o releases/latest); si hay una versión más nueva la descarga sola y abre el
/// instalador del sistema. Android exige que la persona toque «Instalar».
Future<void> erAutoUpdateAndroid() async {
  if (!isAndroid || _erChecking) return;
  final now = DateTime.now().millisecondsSinceEpoch;
  final last = int.tryParse(bind.mainGetLocalOption(key: _kErLastAutoCheck)) ?? 0;
  if (now - last < kErAutoCheckEvery.inMilliseconds && now >= last) return;
  _erChecking = true;
  try {
    await bind.mainSetLocalOption(key: _kErLastAutoCheck, value: '$now');
    await bind.mainSetCommon(key: 'er-check-update', value: '');
    for (int i = 0; i < 60; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      final st = await bind.mainGetCommon(key: 'er-update-state');
      if (st == 'checking' || st.isEmpty) continue;
      if (!st.startsWith('available:')) return;
      final url = st.substring('available:'.length);
      if (!erIsNewer(url, erVersion())) return;
      stateGlobal.updateUrl.value = url;
      final v = erVersionKey(url);
      // Solo por WiFi: con datos móviles no descarga y se vuelve a revisar
      // la próxima vez que se abra la app.
      if (await erUpdateApk(quiet: true)) {
        showToast(
            'Hay versión nueva (er.${v[3]}). Se está descargando por WiFi; '
            'cuando aparezca el instalador toca «Instalar».',
            timeout: const Duration(seconds: 8));
      } else {
        await bind.mainSetLocalOption(key: _kErLastAutoCheck, value: '0');
      }
      return;
    }
  } finally {
    _erChecking = false;
  }
}

Future<bool> erUpdateApk({bool quiet = false}) async {
  final apkUrl = bind.mainGetCommonSync(key: 'er-apk-url');
  // sha256 de latest.json del bucket; vacío con el respaldo de GitHub.
  final apkSha256 = bind.mainGetCommonSync(key: 'er-apk-sha256');
  bool ok = false;
  try {
    ok = await gFFI.invokeMethod(
        'er_update_apk', {'url': apkUrl, 'sha256': apkSha256, 'auto': quiet});
  } catch (e) {
    debugPrint('er_update_apk: $e');
  }
  if (ok && quiet) return true;
  if (ok) {
    showToast('Descargando la actualización… al terminar se abrirá el instalador.',
        timeout: const Duration(seconds: 5));
  } else if (!quiet) {
    await launchUrl(Uri.parse(apkUrl), mode: LaunchMode.externalApplication);
  }
  return ok;
}
