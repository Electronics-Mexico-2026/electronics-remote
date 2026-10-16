// Ventana principal de Electronics Remote con el acomodo de RealVNC Viewer:
// barra de menú (Archivo · Visualizar · Ayuda), caja de ID/búsqueda con la
// cuenta a la derecha, barra lateral (Recientes, Favoritos, Direcciones y el
// equipo «Electronics» con sus grupos), cuadrícula de equipos con miniatura y
// barra de estado. Todo se mapea a funciones que RustDesk ya tiene.

import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../../common.dart';
import '../../common/er_update.dart';
import '../../common/widgets/login.dart';
import '../../common/widgets/peer_card.dart';
import '../../common/widgets/peer_tab_page.dart';
import '../../common/widgets/peers_view.dart';
import '../../consts.dart';
import '../../models/peer_model.dart';
import '../../models/peer_tab_model.dart';
import '../../models/platform_model.dart';
import '../../models/state_model.dart';
import '../../models/user_model.dart';
import '../../utils/multi_window_manager.dart';
import '../pages/connection_page.dart';
import '../pages/desktop_setting_page.dart';
import '../pages/desktop_tab_page.dart';
import 'er_peer_card.dart';
import 'er_preferences.dart';
import 'er_properties.dart';
import 'er_theme.dart';

class ErHome extends StatefulWidget {
  /// Panel «Este equipo» (ID y contraseña de esta PC, avisos de RustDesk).
  final Widget thisDevice;
  const ErHome({Key? key, required this.thisDevice}) : super(key: key);

  @override
  State<ErHome> createState() => _ErHomeState();
}

class _ErHomeState extends State<ErHome> with WindowListener {
  final _search = TextEditingController();
  final _thisDeviceExpanded = true.obs;
  final _sessions = 0.obs;
  final _deviceCount = 0.obs;
  Timer? _timer;
  int _tick = 0;

  PeerTabModel get _tabs => gFFI.peerTabModel;

  @override
  void initState() {
    super.initState();
    _thisDeviceExpanded.value = erGetOpt('er-this-device') != 'N';
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _onTick());
    windowManager.addListener(this);
    // Al abrir, la lista principal es «Mis computadoras».
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _selectSection(PeerTabIndex.ab);
    });
  }

  // Lo mismo que hacía ConnectionPage (la vista que esta reemplaza) con la
  // ventana principal.
  bool _isWindowMinimized = false;

  @override
  void onWindowEvent(String eventName) {
    super.onWindowEvent(eventName);
    if (eventName == 'minimize') {
      _isWindowMinimized = true;
    } else if (eventName == 'maximize' || eventName == 'restore') {
      if (_isWindowMinimized && isWindows) {
        Get.forceAppUpdate();
      }
      _isWindowMinimized = false;
    }
  }

  @override
  void onWindowEnterFullScreen() {
    stateGlobal.resizeEdgeSize.value = 0;
  }

  @override
  void onWindowLeaveFullScreen() {
    stateGlobal.resizeEdgeSize.value = stateGlobal.isMaximized.isTrue
        ? kMaximizeEdgeSize
        : windowResizeEdgeSize;
  }

  @override
  void onWindowClose() {
    super.onWindowClose();
    bind.mainOnMainWindowClose();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onTick() async {
    _tick++;
    _deviceCount.value = _tabs.currentTabCachedPeers.length;
    // Miniaturas nuevas que guardaron las ventanas de sesión.
    if (_tick % 15 == 0) ErState.thumbsVersion.value++;
    // Con «Solo en línea» los apagados no están en pantalla y nadie
    // preguntaría por ellos; se pregunta por todos los de la sección.
    if (ErState.onlineOnly.value && _tick % 5 == 0) {
      final ids = _currentPeers().map((e) => e.id).toList();
      if (ids.isNotEmpty) bind.queryOnlines(ids: ids);
    }
    if (_tick % 2 == 0) _countSessions();
  }

  List<Peer> _currentPeers() {
    switch (PeerTabIndex.values[_tabs.currentTab]) {
      case PeerTabIndex.recent:
        return gFFI.recentPeersModel.peers;
      case PeerTabIndex.fav:
        return gFFI.favoritePeersModel.peers;
      case PeerTabIndex.lan:
        return gFFI.lanPeersModel.peers;
      case PeerTabIndex.ab:
        return gFFI.abModel.peersModel.peers;
      case PeerTabIndex.group:
        return gFFI.groupModel.peersModel.peers;
    }
  }

  Future<void> _countSessions() async {
    var n = 0;
    try {
      final ids = await rustDeskWinManager.getAllSubWindowIds();
      for (final w in ids) {
        try {
          final r = await DesktopMultiWindow.invokeMethod(
              w, kWindowEventGetRemoteList, null);
          if (r is String && r.trim().isNotEmpty) {
            n += r.split(',').where((e) => e.trim().isNotEmpty).length;
          }
        } catch (_) {}
      }
    } catch (_) {}
    if (mounted) _sessions.value = n;
  }

  // ------------------------------------------------------------- acciones

  Future<void> _selectSection(PeerTabIndex t, {bool keepGroup = false}) async {
    final i = t.index;
    if (i != _tabs.currentTab) {
      _tabs.setCurrentTabCachedPeers([]);
      ErState.clearSelection();
    }
    if (t == PeerTabIndex.group && !keepGroup) {
      gFFI.groupModel.selectedAccessibleItemName.value = '';
    }
    _tabs.setCurrentTab(i);
    _load(t, force: false);
    await bind.setLocalFlutterOption(k: kOptionPeerTabIndex, v: i.toString());
  }

  void _load(PeerTabIndex t, {required bool force}) {
    final user = gFFI.userModel;
    if (force &&
        (t == PeerTabIndex.group || t == PeerTabIndex.ab) &&
        user.isLogin &&
        user.networkError.isNotEmpty) {
      // Con un error de red anterior grupos y libreta no piden nada; pedir de
      // nuevo el usuario borra el error y al terminar jala los dos.
      user.refreshCurrentUser();
      return;
    }
    switch (t) {
      case PeerTabIndex.recent:
        bind.mainLoadRecentPeers();
        break;
      case PeerTabIndex.fav:
        bind.mainLoadFavPeers();
        break;
      case PeerTabIndex.lan:
        bind.mainDiscover();
        bind.mainLoadLanPeers();
        break;
      case PeerTabIndex.ab:
        erPullMyAb(force: force, quiet: false);
        break;
      case PeerTabIndex.group:
        gFFI.groupModel.pull(force: force);
        break;
    }
  }

  void _refresh() {
    _load(PeerTabIndex.values[_tabs.currentTab], force: true);
    ErState.thumbsVersion.value++;
  }

  void _newConnection() {
    ErState.searchFocus.requestFocus();
    _search.selection =
        TextSelection(baseOffset: 0, extentOffset: _search.text.length);
  }

  BasePeerCard? _selectedCard() {
    final p = ErState.selectedPeer;
    if (p == null || ErState.selectedId.value.isEmpty) return null;
    return erCardFor(p, ErState.selectedTab);
  }

  void _rename() => _selectedCard()?.erRename();

  void _remove() {
    final c = _selectedCard();
    if (c == null || c.tab == PeerTabIndex.group) return;
    if (c.tab == PeerTabIndex.ab && !gFFI.abModel.current.canWrite()) return;
    c.erRemove();
  }

  void _properties() {
    final p = ErState.selectedPeer;
    if (p == null || ErState.selectedId.value.isEmpty) return;
    erShowProperties(p, ErState.selectedTab);
  }

  void _connectSelected() {
    final p = ErState.selectedPeer;
    if (p == null || ErState.selectedId.value.isEmpty) return;
    connectInPeerTab(context, p, ErState.selectedTab);
  }

  void _submitSearch(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    final idLike = t.replaceAll(' ', '');
    final visible = _tabs.currentTabCachedPeers;
    final tab = PeerTabIndex.values[_tabs.currentTab];
    final exact = visible
        .where((p) =>
            p.id == idLike || erPeerName(p).toLowerCase() == t.toLowerCase())
        .toList();
    if (exact.length == 1) {
      connectInPeerTab(context, exact.first, tab);
    } else if (visible.length == 1) {
      connectInPeerTab(context, visible.first, tab);
    } else {
      connect(context, idLike);
    }
  }

  void _setView(PeerUiType t) async {
    peerCardUiType.value = t;
    await bind.setLocalFlutterOption(
        k: kOptionPeerCardUiType, v: t.index.toString());
  }

  void _setSort(String s) async {
    peerSort.value = s;
    await bind.setLocalFlutterOption(k: kOptionPeerSorting, v: s);
  }

  // ---------------------------------------------------------------- vista

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: kErFontText),
      ),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              _newConnection,
          const SingleActivator(LogicalKeyboardKey.f5): _refresh,
        },
        child: Focus(
          autofocus: true,
          child: Container(
            color: theme.scaffoldBackgroundColor,
            child: Column(
              children: [
                _menuBar(context),
                _topRow(context),
                Divider(height: 1, color: theme.dividerColor),
                Expanded(
                  child: Obx(() => Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (ErState.showSidebar.value) ...[
                            SizedBox(width: 248, child: _sidebar(context)),
                            VerticalDivider(
                                width: 1, color: theme.dividerColor),
                          ],
                          Expanded(child: _content(context)),
                        ],
                      )),
                ),
                Obx(() => ErState.showStatusbar.value
                    ? _statusBar(context)
                    : const SizedBox.shrink()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Barra de menú -----------------------------------------------------

  Widget _menuBar(BuildContext context) {
    final style = erTextStyle(context, size: 13);
    MenuItemButton item(String text, VoidCallback? onPressed,
            {MenuSerializableShortcut? shortcut}) =>
        MenuItemButton(
          onPressed: onPressed,
          shortcut: shortcut,
          // Sin acción = gris, como RealVNC (el estilo fija el color).
          child: Text(text,
              style: onPressed == null
                  ? style.copyWith(color: Theme.of(context).disabledColor)
                  : style),
        );
    Widget sub(String text, List<Widget> children) => SubmenuButton(
          menuChildren: children,
          child: Text(text, style: style),
        );
    return Container(
      height: 30,
      alignment: Alignment.centerLeft,
      color: Theme.of(context).colorScheme.background,
      child: Obx(() {
        final hasSel = ErState.selectedId.value.isNotEmpty;
        final selTab = ErState.selectedTab;
        final canRemove = hasSel &&
            selTab != PeerTabIndex.group &&
            (selTab != PeerTabIndex.ab || gFFI.abModel.current.canWrite());
        final isLogin = gFFI.userModel.userName.value.isNotEmpty;
        final uiType = peerCardUiType.value;
        final sort = peerSort.value;
        final onlineOnly = ErState.onlineOnly.value;
        return MenuBar(
          style: MenuStyle(
            backgroundColor: const MaterialStatePropertyAll(Colors.transparent),
            elevation: const MaterialStatePropertyAll(0),
            padding: const MaterialStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 4)),
          ),
          children: [
            sub('Archivo', [
              item('Nueva conexión…', _newConnection,
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyN,
                      control: true)),
              item('Cerrar sesión',
                  isLogin ? () => gFFI.userModel.logOut() : null),
              const Divider(height: 8),
              item('Renombrar', hasSel ? _rename : null,
                  shortcut: const SingleActivator(LogicalKeyboardKey.f2)),
              item('Eliminar', canRemove ? _remove : null,
                  shortcut: const SingleActivator(LogicalKeyboardKey.delete)),
              item('Duplicar', null,
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyD,
                      control: true)),
              item('Propiedades…', hasSel ? _properties : null,
                  shortcut: const SingleActivator(LogicalKeyboardKey.enter,
                      alt: true)),
              const Divider(height: 8),
              item('Importar conexiones…', null),
              item('Exportar conexiones…', null),
              const Divider(height: 8),
              item('Preferencias…', () => erShowPreferences()),
              const Divider(height: 8),
              item('Salir', () => windowManager.close()),
            ]),
            sub('Visualizar', [
              CheckboxMenuButton(
                value: uiType == PeerUiType.grid,
                onChanged: (_) => _setView(PeerUiType.grid),
                child: Text('Iconos', style: style),
              ),
              CheckboxMenuButton(
                value: uiType == PeerUiType.list,
                onChanged: (_) => _setView(PeerUiType.list),
                child: Text('Detalles', style: style),
              ),
              const Divider(height: 8),
              sub('Ordenar por', [
                for (final e in [
                  (PeerSortType.remoteId, 'ID del equipo'),
                  (PeerSortType.remoteHost, 'Nombre del equipo'),
                  (PeerSortType.username, 'Usuario'),
                  (PeerSortType.status, 'Estado (en línea primero)'),
                ])
                  CheckboxMenuButton(
                    value: sort == e.$1,
                    onChanged: (_) => _setSort(e.$1),
                    child: Text(e.$2, style: style),
                  ),
              ]),
              sub('Filtrar', [
                CheckboxMenuButton(
                  value: !onlineOnly,
                  onChanged: (_) async {
                    ErState.onlineOnly.value = false;
                    await erSetOpt(kErOptOnlineOnly, 'N');
                  },
                  child: Text('Todos los equipos', style: style),
                ),
                CheckboxMenuButton(
                  value: onlineOnly,
                  onChanged: (_) async {
                    ErState.onlineOnly.value = true;
                    await erSetOpt(kErOptOnlineOnly, 'Y');
                  },
                  child: Text('Solo en línea', style: style),
                ),
              ]),
              item('Actualizar', _refresh,
                  shortcut: const SingleActivator(LogicalKeyboardKey.f5)),
              CheckboxMenuButton(
                value: ErState.showSidebar.value,
                onChanged: (_) =>
                    ErState.toggle(ErState.showSidebar, kErOptShowSidebar),
                child: Text('Mostrar barra lateral', style: style),
              ),
              CheckboxMenuButton(
                value: ErState.showStatusbar.value,
                onChanged: (_) =>
                    ErState.toggle(ErState.showStatusbar, kErOptShowStatusbar),
                child: Text('Mostrar barra de estado', style: style),
              ),
            ]),
            sub('Ayuda', [
              item('Buscar actualizaciones', () => erCheckForUpdatesManually()),
              item('Panel de Electronics Remote',
                  () => launchUrl(Uri.parse(kErPanelUrl))),
              const Divider(height: 8),
              item(
                  'Acerca de Electronics Remote…',
                  () => DesktopTabPage.onAddSetting(
                      initialPage: SettingsTabKey.about)),
            ]),
          ],
        );
      }),
    );
  }

  // Logo + caja de ID/búsqueda + cuenta --------------------------------

  Widget _topRow(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: theme.colorScheme.background,
      child: Row(
        children: [
          erIsotipo(size: 26),
          const SizedBox(width: 8),
          ShaderMask(
            shaderCallback: (r) => ErColors.gradient.createShader(r),
            child: Text('Electronics Remote',
                style: erTitleStyle(context,
                    size: 16, weight: FontWeight.w700, color: Colors.white)),
          ),
          const SizedBox(width: 14),
          Expanded(child: _searchBox(context)),
          const SizedBox(width: 12),
          _account(context),
        ],
      ),
    );
  }

  Widget _searchBox(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 32,
      child: TextField(
        controller: _search,
        focusNode: ErState.searchFocus,
        autocorrect: false,
        enableSuggestions: false,
        maxLines: 1,
        style: erTextStyle(context, size: 13),
        cursorColor: ErColors.cyan,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: theme.scaffoldBackgroundColor,
          hintText: 'Escribe el ID del equipo o busca por nombre',
          hintStyle: erTextStyle(context, size: 13, color: theme.hintColor),
          prefixIcon:
              Icon(Icons.search_rounded, size: 18, color: theme.hintColor),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 34, minHeight: 32),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _search,
            builder: (_, v, __) => v.text.isEmpty
                ? const SizedBox.shrink()
                : InkWell(
                    onTap: () {
                      _search.clear();
                      peerSearchText.value = '';
                    },
                    child: Icon(Icons.close_rounded,
                        size: 16, color: theme.hintColor),
                  ),
          ),
          suffixIconConstraints:
              const BoxConstraints(minWidth: 30, minHeight: 32),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: ErColors.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: ErColors.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: ErColors.blue, width: 1.5),
          ),
        ),
        onChanged: (v) => peerSearchText.value = v,
        onSubmitted: _submitSearch,
      ).workaroundFreezeLinuxMint(),
    );
  }

  Widget _account(BuildContext context) {
    return Obx(() {
      final user = gFFI.userModel;
      if (user.userName.value.isEmpty) {
        return OutlinedButton.icon(
          onPressed: () => loginDialog(),
          icon: const Icon(Icons.login_rounded, size: 16),
          label: Text('Iniciar sesión', style: erTextStyle(context)),
        );
      }
      final name = user.displayNameOrUserName;
      return PopupMenuButton<String>(
        tooltip: 'Cuenta del panel',
        position: PopupMenuPosition.under,
        onSelected: (v) {
          if (v == 'panel') {
            launchUrl(Uri.parse(kErPanelUrl));
          } else if (v == 'logout') {
            user.logOut();
          }
        },
        itemBuilder: (context) {
          final email =
              (UserModel.getLocalUserInfo()?['email'] ?? '').toString();
          return [
            PopupMenuItem<String>(
              enabled: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: erTextStyle(context,
                          size: 14, weight: FontWeight.w600)),
                  if (email.isNotEmpty)
                    Text(email,
                        style: erTextStyle(context,
                            size: 12, color: Theme.of(context).hintColor)),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
                value: 'panel',
                child: Text('Administrar cuenta', style: erTextStyle(context))),
            PopupMenuItem<String>(
                value: 'logout',
                child: Text('Cerrar sesión', style: erTextStyle(context))),
          ];
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: ErColors.online),
              child: const Icon(Icons.check_rounded,
                  size: 14, color: Colors.white),
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(name,
                  overflow: TextOverflow.ellipsis,
                  style: erTextStyle(context, weight: FontWeight.w500)),
            ),
            const Icon(Icons.arrow_drop_down_rounded, size: 20),
          ],
        ),
      );
    });
  }

  // Barra lateral ------------------------------------------------------

  Widget _sidebar(BuildContext context) {
    final theme = Theme.of(context);
    // Mismo fondo que el centro: antes era colorScheme.background y, sin la
    // lista de grupos, quedaba un bloque gris vacío.
    return Container(
      color: theme.scaffoldBackgroundColor,
      child: ChangeNotifierProvider.value(
        value: gFFI.peerTabModel,
        child: Consumer<PeerTabModel>(
          builder: (context, model, _) => Obx(() {
            final cur = PeerTabIndex.values[model.currentTab];
            final ab = gFFI.abModel;
            final mine = erHasMyAb() && ab.currentName.value == erMyAbName();
            final count = mine ? ab.currentAbPeers.length : 0;
            final login = gFFI.userModel.userName.value.isNotEmpty;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(kErMyComputers,
                            overflow: TextOverflow.ellipsis,
                            style: erTitleStyle(context, size: 15)),
                      ),
                      Tooltip(
                        message: 'Actualizar (F5)',
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.refresh_rounded,
                              size: 18, color: ErColors.cyan),
                          onPressed: () {
                            _selectSection(PeerTabIndex.ab);
                            _refresh();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: Text(
                      !login
                          ? 'Inicia sesión para ver tus equipos'
                          : (count == 0
                              ? 'Sin computadoras asignadas'
                              : '$count ${count == 1 ? 'computadora' : 'computadoras'}'),
                      style: erTextStyle(context,
                          size: 12,
                          color: theme.textTheme.bodySmall?.color
                              ?.withOpacity(0.7))),
                ),
                if (model.isEnabled[PeerTabIndex.ab.index])
                  _navItem(context, Icons.grid_view_rounded, kErMyComputers,
                      cur == PeerTabIndex.ab,
                      () => _selectSection(PeerTabIndex.ab)),
                if (model.isEnabled[PeerTabIndex.recent.index])
                  _navItem(context, Icons.history_rounded, 'Recientes',
                      cur == PeerTabIndex.recent,
                      () => _selectSection(PeerTabIndex.recent)),
                if (model.isEnabled[PeerTabIndex.fav.index])
                  _navItem(context, Icons.star_border_rounded, 'Favoritos',
                      cur == PeerTabIndex.fav,
                      () => _selectSection(PeerTabIndex.fav)),
                if (model.isEnabled[PeerTabIndex.lan.index])
                  _navItem(context, Icons.wifi_tethering_rounded, 'Red local',
                      cur == PeerTabIndex.lan,
                      () => _selectSection(PeerTabIndex.lan)),
                const Spacer(),
                Divider(height: 1, color: theme.dividerColor),
                _thisDevicePanel(context),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _navItem(BuildContext context, IconData icon, String text,
      bool selected, VoidCallback onTap,
      {double indent = 0, Widget? leading, bool bold = false}) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 34,
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        padding: EdgeInsets.only(left: 6 + indent, right: 8),
        decoration: BoxDecoration(
          color: selected ? ErColors.selected : null,
          borderRadius: BorderRadius.circular(6),
          border: selected
              ? Border(left: BorderSide(color: ErColors.cyan, width: 3))
              : null,
        ),
        child: Row(
          children: [
            SizedBox(width: 20, child: leading),
            Icon(icon,
                size: 18,
                color: selected ? ErColors.cyan : theme.iconTheme.color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  overflow: TextOverflow.ellipsis,
                  style: erTextStyle(context,
                      size: 13,
                      weight: bold || selected
                          ? FontWeight.w600
                          : FontWeight.w400)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thisDevicePanel(BuildContext context) {
    return Obx(() => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () async {
                _thisDeviceExpanded.value = !_thisDeviceExpanded.value;
                await erSetOpt(
                    'er-this-device', _thisDeviceExpanded.value ? 'Y' : 'N');
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                child: Row(
                  children: [
                    Icon(
                        _thisDeviceExpanded.value
                            ? Icons.arrow_drop_down_rounded
                            : Icons.arrow_right_rounded,
                        size: 20),
                    const SizedBox(width: 4),
                    Text('Este equipo', style: erTitleStyle(context, size: 14)),
                  ],
                ),
              ),
            ),
            if (_thisDeviceExpanded.value)
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.45),
                child: SingleChildScrollView(child: widget.thisDevice),
              ),
          ],
        ));
  }

  // Centro -------------------------------------------------------------

  Widget _content(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): _rename,
        const SingleActivator(LogicalKeyboardKey.delete): _remove,
        const SingleActivator(LogicalKeyboardKey.enter, alt: true): _properties,
        const SingleActivator(LogicalKeyboardKey.enter): _connectSelected,
      },
      child: Focus(
        focusNode: ErState.gridFocus,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            ErState.gridFocus.requestFocus();
          },
          child: Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: ChangeNotifierProvider.value(
              value: gFFI.peerTabModel,
              child: PeerTabPage(
                erMode: true,
                erGroupView: const ErGroupView(),
                erAbView: const ErMyAbView(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Barra de estado ----------------------------------------------------

  Widget _statusBar(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.background,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Obx(() => Text('${_deviceCount.value} dispositivo(s)',
              style: erTextStyle(context, size: 12))),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRect(
              child: DefaultTextStyle.merge(
                style: erTextStyle(context, size: 12),
                child: const OnlineStatusWidget(),
              ),
            ),
          ),
          Obx(() => Text('Sesiones activas: ${_sessions.value}',
              style: erTextStyle(context, size: 12))),
          const SizedBox(width: 10),
          Tooltip(
            message: 'Preferencias',
            child: InkWell(
              onTap: () => erShowPreferences(),
              child: const Icon(Icons.settings_rounded, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

/// «Mis computadoras»: solo la libreta «Equipos de <usuario>» que el sitio
/// le comparte a la persona; sin ella, un aviso y nada más.
class ErMyAbView extends StatelessWidget {
  const ErMyAbView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final user = gFFI.userModel;
      final ab = gFFI.abModel;
      if (!user.isLogin) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Inicia sesión con tu cuenta del panel para ver los equipos',
                  style: erTextStyle(context)),
              const SizedBox(height: 12),
              ElevatedButton(
                  onPressed: loginDialog,
                  child: Text('Iniciar sesión', style: erTextStyle(context))),
            ],
          ),
        );
      } else if (user.networkError.isNotEmpty) {
        return netWorkErrorWidget();
      }
      final has = erHasMyAb();
      if (has && ab.currentName.value != erMyAbName()) {
        Future.microtask(erSelectMyAb);
        return const Center(child: CircularProgressIndicator());
      }
      if (!has || (ab.currentAbEmpty && !ab.currentAbLoading.value)) {
        if (!has &&
            (ab.currentAbLoading.value ||
                (ab.addressbooks.isEmpty && ab.abPullError.isEmpty))) {
          return const Center(child: CircularProgressIndicator());
        }
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(kErNoComputers,
                  textAlign: TextAlign.center, style: erTextStyle(context)),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                  onPressed: () => erPullMyAb(quiet: false),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text('Actualizar', style: erTextStyle(context))),
            ],
          ),
        );
      }
      return Column(
        children: [
          if (ab.currentAbLoading.value && ab.currentAbEmpty)
            const LinearProgressIndicator(),
          buildErrorBanner(context,
              loading: ab.currentAbLoading,
              err: ab.abPullError,
              retry: null,
              close: ab.clearPullErrors),
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: AddressBookPeersView(menuPadding: kDesktopMenuPadding),
            ),
          ),
        ],
      );
    });
  }
}

/// Equipos del panel (grupo) sin la lista propia de la izquierda: la barra
/// lateral ya elige el grupo.
class ErGroupView extends StatelessWidget {
  const ErGroupView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final user = gFFI.userModel;
      if (!user.isLogin) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Inicia sesión con tu cuenta del panel para ver los equipos',
                  style: erTextStyle(context)),
              const SizedBox(height: 12),
              ElevatedButton(
                  onPressed: loginDialog,
                  child: Text('Iniciar sesión', style: erTextStyle(context))),
            ],
          ),
        );
      } else if (user.networkError.isNotEmpty) {
        return netWorkErrorWidget();
      } else if (gFFI.groupModel.groupLoading.value && gFFI.groupModel.emtpy) {
        return const Center(child: CircularProgressIndicator());
      }
      return Column(
        children: [
          buildErrorBanner(context,
              loading: gFFI.groupModel.groupLoading,
              err: gFFI.groupModel.groupLoadError,
              retry: null,
              close: () => gFFI.groupModel.groupLoadError.value = ''),
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: MyGroupPeerView(menuPadding: kDesktopMenuPadding),
            ),
          ),
        ],
      );
    });
  }
}
