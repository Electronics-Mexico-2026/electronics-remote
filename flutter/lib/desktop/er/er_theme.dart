// Electronics Remote: colores, letras y estado de la ventana principal
// (acomodo tipo RealVNC Viewer). Todo lo nuevo de la marca vive en
// lib/desktop/er/ para no tocar de más el código de RustDesk.

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../models/ab_model.dart';
import '../../models/peer_model.dart';
import '../../models/peer_tab_model.dart';
import '../../models/platform_model.dart';

class ErColors {
  static const violet = Color(0xFF4937F1);
  static const blue = Color(0xFF2572F8);
  static const cyan = Color(0xFF00ADFF);
  static const night = Color(0xFF0A0F1C);
  static const panel = Color(0xFF141414);
  static const surface = Color(0xFF111827);
  static const line = Color(0xFF1F2A44);
  static const online = Color(0xFF22C55E);
  static const offline = Color(0xFF6B7280);
  static const selected = Color(0x332572F8);
  static const gradient = LinearGradient(
    colors: [violet, blue, cyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

// Regla del dueño: cada persona ve SOLO las computadoras a las que tiene
// derecho. El sitio (usuario «sitio» del panel) le comparte una libreta
// «Equipos de <usuario>» con la contraseña guardada; esa es la lista.
const String kErMyComputers = 'Mis computadoras';
const String kErNoComputers =
    'Todavía no tienes computadoras asignadas. Pídele acceso al administrador.';

String erMyAbName() {
  final u = gFFI.userModel.userName.value;
  return u.isEmpty ? '' : 'Equipos de $u';
}

bool erHasMyAb() {
  final n = erMyAbName();
  return n.isNotEmpty && gFFI.abModel.addressbooks.containsKey(n);
}

/// Deja como actual la libreta de la persona (si existe).
Future<void> erSelectMyAb() async {
  if (!erHasMyAb()) {
    await erForgetRemovedComputers();
    return;
  }
  final n = erMyAbName();
  if (gFFI.abModel.currentName.value != n) {
    await gFFI.abModel.setCurrentName(n);
  }
  await erForgetRemovedComputers();
}

const String _kErOptMyAbIds = 'er-my-ab-ids';

/// Si a la persona le quitaron una computadora de su libreta, se olvida la
/// contraseña recordada en este aparato: al volver a dársela, se la pide.
Future<void> erForgetRemovedComputers() async {
  final ab = gFFI.abModel;
  if (gFFI.userModel.userName.value.isEmpty) return;
  if (gFFI.userModel.networkError.value.isNotEmpty) return;
  if (ab.abPullError.value.isNotEmpty || ab.addressbooks.isEmpty) return;
  final mine = erMyAbName();
  final book = ab.addressbooks[mine];
  if (book != null && !book.initialized) return;
  final now = (book?.peers.map((p) => p.id).toSet() ?? <String>{});
  final prev = erGetOpt(_kErOptMyAbIds)
      .split(',')
      .where((e) => e.isNotEmpty)
      .toSet();
  for (final id in prev.difference(now)) {
    await bind.mainForgetPassword(id: id);
  }
  final joined = (now.toList()..sort()).join(',');
  if (joined != erGetOpt(_kErOptMyAbIds)) await erSetOpt(_kErOptMyAbIds, joined);
}

/// Pide al panel las libretas y deja la de la persona.
Future<void> erPullMyAb({bool force = true, bool quiet = true}) async {
  await gFFI.abModel.pullAb(
      force: force ? ForcePullAb.listAndCurrent : null, quiet: quiet);
  await erSelectMyAb();
}

const String kErFontText = 'Montserrat';
const String kErFontTitle = 'BaiJamjuree';
const String kErPanelUrl = 'https://remote.electronicsmexico.site';

// Opciones locales propias (LocalConfig, por usuario de Windows).
const String kErOptShowSidebar = 'er-show-sidebar';
const String kErOptShowStatusbar = 'er-show-statusbar';
const String kErOptOnlineOnly = 'er-filter-online';
const String kErOptHideThumbs = 'er-hide-thumbs';
const String kErOptAskRemember = 'er-ask-remember-password';
const String kErOptSection = 'er-sidebar-section';

String erGetOpt(String key) => bind.mainGetLocalOption(key: key);
Future<void> erSetOpt(String key, String value) =>
    bind.mainSetLocalOption(key: key, value: value);

/// «Y» por omisión: solo un «N» explícito lo apaga.
bool erOptOn(String key) => erGetOpt(key) != 'N';

/// «N» por omisión: solo un «Y» explícito lo prende.
bool erOptYes(String key) => erGetOpt(key) == 'Y';

class ErState {
  static final showSidebar = erOptOn(kErOptShowSidebar).obs;
  static final showStatusbar = erOptOn(kErOptShowStatusbar).obs;
  static final onlineOnly = erOptYes(kErOptOnlineOnly).obs;
  static final hideThumbs = erOptYes(kErOptHideThumbs).obs;

  /// Equipo seleccionado en la cuadrícula (un clic).
  static final selectedId = ''.obs;
  static Peer? selectedPeer;
  static PeerTabIndex selectedTab = PeerTabIndex.recent;

  /// Sube cada vez que se guarda una miniatura o se pulsa Actualizar.
  static final thumbsVersion = 0.obs;

  /// Caja de arriba «Escribe el ID del equipo o busca por nombre».
  static final searchFocus = FocusNode(debugLabel: 'er-search');

  /// Foco de la cuadrícula: F2, Supr y Alt+Enter solo actúan aquí.
  static final gridFocus = FocusNode(debugLabel: 'er-grid');

  static void select(Peer peer, PeerTabIndex tab) {
    selectedPeer = peer;
    selectedTab = tab;
    selectedId.value = peer.id;
  }

  static void clearSelection() {
    selectedPeer = null;
    selectedId.value = '';
  }

  static Future<void> toggle(RxBool v, String key,
      {bool defaultOn = true}) async {
    v.value = !v.value;
    await erSetOpt(key, v.value ? 'Y' : 'N');
  }
}

/// Texto con la letra de la marca.
TextStyle erTitleStyle(BuildContext context,
        {double size = 15,
        FontWeight weight = FontWeight.w600,
        Color? color}) =>
    TextStyle(
      fontFamily: kErFontTitle,
      fontSize: size,
      fontWeight: weight,
      color: color ?? Theme.of(context).textTheme.titleLarge?.color,
    );

TextStyle erTextStyle(BuildContext context,
        {double size = 13,
        FontWeight weight = FontWeight.w400,
        Color? color}) =>
    TextStyle(
      fontFamily: kErFontText,
      fontSize: size,
      fontWeight: weight,
      color: color ?? Theme.of(context).textTheme.titleLarge?.color,
    );

/// Isotipo «e» de Electronics México.
Widget erIsotipo({double size = 28}) => Image.asset(
      'assets/er_isotipo.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
    );

/// Nombre que se muestra del equipo: alias (del panel o local), si no
/// hostname, si no ID. Los equipos del panel no traen alias; el que se pone
/// con «Renombrar» se guarda local por equipo.
String erPeerName(Peer p) {
  if (p.alias.trim().isNotEmpty) return p.alias.trim();
  final local = erLocalAlias(p.id);
  if (local.isNotEmpty) return local;
  if (p.hostname.trim().isNotEmpty) return p.hostname.trim();
  return p.id;
}

final Map<String, (DateTime, String)> _erAliasCache = {};

String erLocalAlias(String id) {
  final now = DateTime.now();
  final hit = _erAliasCache[id];
  if (hit != null && now.difference(hit.$1) < const Duration(seconds: 3)) {
    return hit.$2;
  }
  var v = '';
  try {
    v = bind.mainGetPeerOptionSync(id: id, key: 'alias').trim();
  } catch (_) {}
  _erAliasCache[id] = (now, v);
  return v;
}
