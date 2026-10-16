// Electronics Remote para Android: pantalla principal con el acomodo de
// RealVNC Viewer (barra de arriba con ☰ / título / filtro / lupa, cajón con
// la cuenta y las secciones, cuadrícula de equipos con miniatura e insignia
// de en línea, botón «+» de nueva conexión). Con el celular abierto (ancho
// ≥ 600 dp) la cuadrícula va en varias columnas; cerrado, en una.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common.dart';
import '../../common/er_update.dart';
import '../../common/formatter/id_formatter.dart';
import '../../common/widgets/login.dart';
import '../../common/widgets/peer_card.dart';
import '../../common/widgets/peers_view.dart';
import '../../consts.dart';
import '../../desktop/er/er_peer_card.dart';
import '../../desktop/er/er_properties.dart';
import '../../desktop/er/er_thumbs.dart';
import '../../models/ab_model.dart';
import '../../models/peer_model.dart';
import '../../models/peer_tab_model.dart';
import '../../models/platform_model.dart';
import '../../models/state_model.dart';
import '../../models/user_model.dart';
import '../../common/widgets/chat_page.dart';
import '../pages/home_page.dart';
import '../pages/server_page.dart';
import '../pages/settings_page.dart';
import 'er_m_session.dart';
import 'er_m_theme.dart';

class ErMobileShell extends StatefulWidget {
  final List<PageShape> pages;
  final int selectedIndex;
  final void Function(int) onSelect;
  final Widget Function(int) titleOf;
  final Widget navBar;
  const ErMobileShell({
    Key? key,
    required this.pages,
    required this.selectedIndex,
    required this.onSelect,
    required this.titleOf,
    required this.navBar,
  }) : super(key: key);

  @override
  State<ErMobileShell> createState() => _ErMobileShellState();
}

class _ErMobileShellState extends State<ErMobileShell>
    with WidgetsBindingObserver {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searching = false;
  StreamSubscription? _uniLinks;
  Timer? _autoRefresh;

  PeerTabModel get _tabs => gFFI.peerTabModel;

  @override
  void initState() {
    super.initState();
    // Lo mismo que hacía ConnectionPage (la vista que esta reemplaza).
    _uniLinks = listenUniLinks();
    erInstallErrorCapture();
    WidgetsBinding.instance.addObserver(this);
    _autoRefresh = Timer.periodic(
        const Duration(seconds: 60), (_) => _refreshSilently());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshSilently();
  }

  /// Al volver a la app y cada minuto con la lista a la vista: la sección
  /// actual y el estado en línea, sin avisos (sin red solo se queda la lista
  /// que ya había).
  void _refreshSilently() {
    if (!mounted || widget.selectedIndex != 0) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    // Al volver de una sesión con «atrás» se quedaba en false y también
    // detenía la consulta de en línea de la lista.
    stateGlobal.isInMainPage = true;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    _load(PeerTabIndex.values[_tabs.currentTab], force: true, quiet: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoRefresh?.cancel();
    _uniLinks?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  int _indexOf(bool Function(PageShape) test) => widget.pages.indexWhere(test);

  // ------------------------------------------------------------ secciones

  String _sectionTitle() {
    switch (PeerTabIndex.values[_tabs.currentTab]) {
      case PeerTabIndex.recent:
        return 'Recientes';
      case PeerTabIndex.fav:
        return 'Favoritos';
      case PeerTabIndex.lan:
        return 'Red local';
      case PeerTabIndex.ab:
        return erAbDisplayName(gFFI.abModel.currentName.value);
      case PeerTabIndex.group:
        final g = gFFI.groupModel.selectedAccessibleItemName.value;
        return g.isEmpty ? 'Electronics' : g;
    }
  }

  Future<void> _selectSection(PeerTabIndex t, {bool keepGroup = false}) async {
    if (t != PeerTabIndex.group || !keepGroup) {
      gFFI.groupModel.selectedAccessibleItemName.value = '';
    }
    if (t.index != _tabs.currentTab) {
      _tabs.setCurrentTabCachedPeers([]);
    }
    _tabs.setCurrentTab(t.index);
    // Las del panel se piden de nuevo al entrar: un equipo que se dio de
    // alta o de baja después del inicio de sesión aparece sin hacer nada.
    _load(t,
        force: t == PeerTabIndex.group || t == PeerTabIndex.ab, quiet: true);
    widget.onSelect(0);
    setState(() {});
    await bind.setLocalFlutterOption(
        k: kOptionPeerTabIndex, v: t.index.toString());
  }

  Future<void> _selectAddressBook(String name) async {
    await _selectSection(PeerTabIndex.ab);
    await gFFI.abModel.setCurrentName(name);
    await bind.setLocalFlutterOption(k: kOptionCurrentAbName, v: name);
    if (mounted) setState(() {});
  }

  void _selectGroupItem(String name, bool isDeviceGroup) {
    final group = gFFI.groupModel;
    group.isSelectedDeviceGroup.value = isDeviceGroup;
    group.selectedAccessibleItemName.value = name;
    _selectSection(PeerTabIndex.group, keepGroup: true);
  }

  Future<void> _load(PeerTabIndex t,
      {required bool force, bool quiet = false}) async {
    final user = gFFI.userModel;
    if (force &&
        (t == PeerTabIndex.group || t == PeerTabIndex.ab) &&
        user.isLogin &&
        user.networkError.isNotEmpty) {
      // Con un error de red anterior los modelos del panel no piden nada y
      // la lista se quedaba vieja para siempre; pedir de nuevo el usuario
      // borra el error y, al terminar, jala libreta y grupos.
      user.refreshCurrentUser();
      return;
    }
    switch (t) {
      case PeerTabIndex.recent:
        await bind.mainLoadRecentPeers();
        break;
      case PeerTabIndex.fav:
        await bind.mainLoadFavPeers();
        break;
      case PeerTabIndex.lan:
        bind.mainDiscover();
        await bind.mainLoadLanPeers();
        break;
      case PeerTabIndex.ab:
        await gFFI.abModel.pullAb(
            force: force ? ForcePullAb.listAndCurrent : null, quiet: quiet);
        await _erPickSharedAb();
        break;
      case PeerTabIndex.group:
        await gFFI.groupModel.pull(force: force, quiet: quiet);
        break;
    }
    final failed = (t == PeerTabIndex.group || t == PeerTabIndex.ab) &&
        (user.networkError.isNotEmpty ||
            (t == PeerTabIndex.group &&
                gFFI.groupModel.groupLoadError.isNotEmpty));
    if (!failed) ErMobileState.lastRefresh.value = DateTime.now();
    if (force) {
      ErState.thumbsVersion.value++;
      // Todos los de la sección, también los que «Solo en línea» esconde.
      final ids = _sectionPeers(t).map((e) => e.id).toList();
      if (ids.isNotEmpty) bind.queryOnlines(ids: ids);
    }
  }

  /// Sin una libreta elegida a mano, «Direcciones» abría «Mi libreta»
  /// vacía y no se veían las de la empresa: se pasa a la primera compartida.
  Future<void> _erPickSharedAb() async {
    final ab = gFFI.abModel;
    if (bind.getLocalFlutterOption(k: kOptionCurrentAbName).isNotEmpty) return;
    if (ab.currentName.value != ab.personalAddressBookName() ||
        ab.current.peers.isNotEmpty) {
      return;
    }
    final shared = ab.addressbooks.keys
        .where((n) => n != ab.personalAddressBookName());
    if (shared.isNotEmpty) await ab.setCurrentName(shared.first);
  }

  List<Peer> _sectionPeers(PeerTabIndex t) {
    switch (t) {
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

  void _closeSearch() {
    _search.clear();
    peerSearchText.value = '';
    setState(() => _searching = false);
  }

  // ---------------------------------------------------------------- vista

  @override
  Widget build(BuildContext context) {
    final idx = widget.selectedIndex;
    return erThemed(WillPopScope(
      onWillPop: () async {
        if (_searching) {
          _closeSearch();
          return false;
        }
        if (idx != 0) {
          widget.onSelect(0);
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: ErColors.night,
        drawer: _drawer(context),
        appBar: idx == 0 ? _peersAppBar(context) : _pageAppBar(context, idx),
        floatingActionButton: idx == 0
            ? FloatingActionButton(
                tooltip: 'Nueva conexión',
                backgroundColor: ErColors.blue,
                foregroundColor: Colors.white,
                onPressed: () => erNewConnectionDialog(context),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, gradient: ErColors.gradient),
                  child: const Icon(Icons.add_rounded, size: 30),
                ),
              )
            : null,
        body: erShellBody(
            idx == 0 ? _peersBody(context) : widget.pages[idx] as Widget,
            widget.navBar),
      ),
    ));
  }

  // Barra de arriba ----------------------------------------------------

  PreferredSizeWidget _pageAppBar(BuildContext context, int idx) {
    final page = widget.pages[idx];
    return AppBar(
      title: DefaultTextStyle.merge(
          style: erTitleStyle(context, size: 18, color: Colors.white),
          child: widget.titleOf(idx)),
      actions: page.appBarActions,
      bottom: erGradientLine(),
    );
  }

  PreferredSizeWidget _peersAppBar(BuildContext context) {
    if (_searching) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Cerrar búsqueda',
          onPressed: _closeSearch,
        ),
        title: TextField(
          controller: _search,
          focusNode: _searchFocus,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          style: erTextStyle(context, size: 16, color: Colors.white),
          decoration: InputDecoration(
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            hintText: 'Buscar conexiones',
            hintStyle: erTextStyle(context,
                size: 16, color: Colors.white.withOpacity(0.5)),
          ),
          onChanged: (v) => peerSearchText.value = v,
          onSubmitted: _submitSearch,
        ),
        actions: [
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _search,
            builder: (_, v, __) => v.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _search.clear();
                      peerSearchText.value = '';
                    },
                  ),
          ),
        ],
        bottom: erGradientLine(),
      );
    }
    return AppBar(
      title: ChangeNotifierProvider.value(
        value: gFFI.peerTabModel,
        child: Consumer<PeerTabModel>(
          builder: (context, _, __) => Obx(() {
            // Se lee para que el título cambie con el grupo elegido.
            gFFI.groupModel.selectedAccessibleItemName.value;
            return Text(_sectionTitle(), overflow: TextOverflow.ellipsis);
          }),
        ),
      ),
      actions: [
        _filterButton(context),
        IconButton(
          icon: const Icon(Icons.search_rounded),
          tooltip: 'Buscar',
          onPressed: () => setState(() => _searching = true),
        ),
      ],
      bottom: erGradientLine(),
    );
  }

  void _submitSearch(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    final visible = _tabs.currentTabCachedPeers;
    final tab = PeerTabIndex.values[_tabs.currentTab];
    if (visible.length == 1) {
      connectInPeerTab(context, visible.first, tab);
    } else if (visible.isEmpty && RegExp(r'^[0-9 ]{6,}$').hasMatch(t)) {
      connect(context, t.replaceAll(' ', ''));
    }
  }

  Widget _filterButton(BuildContext context) {
    PopupMenuItem<String> check(String value, String text, bool checked) =>
        CheckedPopupMenuItem<String>(
            value: value,
            checked: checked,
            child: Text(text, style: erTextStyle(context, size: 14)));
    return PopupMenuButton<String>(
      icon: const Icon(Icons.filter_alt_outlined),
      tooltip: 'Filtrar y ordenar',
      color: ErColors.surface,
      onSelected: (v) async {
        if (v == 'all' || v == 'online') {
          ErState.onlineOnly.value = v == 'online';
          await erSetOpt(kErOptOnlineOnly, v == 'online' ? 'Y' : 'N');
          if (v == 'online') {
            final ids = _tabs.currentTabCachedPeers.map((e) => e.id).toList();
            if (ids.isNotEmpty) bind.queryOnlines(ids: ids);
          }
        } else if (v == 'refresh') {
          _load(PeerTabIndex.values[_tabs.currentTab], force: true);
        } else if (v.startsWith('sort:')) {
          final s = v.substring(5);
          peerSort.value = s;
          await bind.setLocalFlutterOption(k: kOptionPeerSorting, v: s);
        }
        setState(() {});
      },
      itemBuilder: (context) {
        final online = ErState.onlineOnly.value;
        final sort = peerSort.value;
        return [
          check('all', 'Todos los equipos', !online),
          check('online', 'Solo en línea', online),
          const PopupMenuDivider(),
          check('sort:${PeerSortType.remoteHost}', 'Ordenar por nombre',
              sort == PeerSortType.remoteHost),
          check('sort:${PeerSortType.remoteId}', 'Ordenar por ID',
              sort == PeerSortType.remoteId),
          check('sort:${PeerSortType.status}', 'En línea primero',
              sort == PeerSortType.status),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
              value: 'refresh',
              child: Text('Actualizar', style: erTextStyle(context, size: 14))),
        ];
      },
    );
  }

  // Cuerpo: equipos -----------------------------------------------------

  Widget _peersBody(BuildContext context) {
    return Column(
      children: [
        Obx(() => stateGlobal.updateUrl.value.isEmpty
            ? const SizedBox.shrink()
            : InkWell(
                onTap: () => erUpdateApk(),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: const BoxDecoration(gradient: ErColors.gradient),
                  alignment: Alignment.center,
                  child: Text('Actualizar a la nueva versión',
                      style: erTextStyle(context,
                          size: 14,
                          weight: FontWeight.w600,
                          color: Colors.white)),
                ),
              )),
        Expanded(
          child: ChangeNotifierProvider.value(
            value: gFFI.peerTabModel,
            child: Consumer<PeerTabModel>(
              builder: (context, model, _) => Obx(() {
                final tab = PeerTabIndex.values[model.currentTab];
                final login = gFFI.userModel.userName.value.isNotEmpty;
                final online = ErState.onlineOnly.value;
                final g =
                    '${gFFI.groupModel.isSelectedDeviceGroup.value}/${gFFI.groupModel.selectedAccessibleItemName.value}';
                if ((tab == PeerTabIndex.group || tab == PeerTabIndex.ab) &&
                    !login) {
                  return _loginPrompt(context);
                }
                final list = RefreshIndicator(
                  color: ErColors.cyan,
                  backgroundColor: ErColors.surface,
                  onRefresh: () => _load(tab, force: true),
                  child: ErMobilePeersView(
                    key: ValueKey('${tab.index}/$online/$g'),
                    tab: tab,
                  ),
                );
                return Column(children: [
                  _statusBar(context, tab),
                  Expanded(child: list),
                ]);
              }),
            ),
          ),
        ),
      ],
    );
  }

  /// Una línea fija (no un aviso por intento): cuándo se actualizó, cuántos
  /// equipos se ven y un botón para actualizar sin depender del gesto. Si el
  /// panel no respondió lo dice ahí mismo.
  Widget _statusBar(BuildContext context, PeerTabIndex tab) {
    return Obx(() {
      final err = erMobilePanelError(tab);
      final at = ErMobileState.lastRefresh.value;
      final n = ErMobileState.shownCount.value;
      String two(int v) => v.toString().padLeft(2, '0');
      final when = at == null
          ? 'Sin actualizar'
          : 'Actualizado ${two(at.hour)}:${two(at.minute)}';
      final text = err.isNotEmpty
          ? 'No se pudo leer el panel'
          : '$when · $n ${n == 1 ? 'equipo' : 'equipos'}';
      return Container(
        width: double.infinity,
        color: ErColors.surface,
        padding: const EdgeInsets.only(left: 16, right: 4),
        child: Row(children: [
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: erTextStyle(context,
                    size: 13,
                    color: err.isNotEmpty
                        ? const Color(0xFFFFB4A9)
                        : Colors.white.withOpacity(0.75))),
          ),
          TextButton.icon(
            onPressed: () => _load(tab, force: true),
            icon: const Icon(Icons.refresh_rounded,
                size: 18, color: ErColors.cyan),
            label: Text('Actualizar',
                style: erTextStyle(context, size: 13, color: ErColors.cyan)),
          ),
        ]),
      );
    });
  }

  Widget _loginPrompt(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            erIsotipo(size: 64),
            const SizedBox(height: 16),
            Text('Inicia sesión con tu cuenta del panel para ver los equipos',
                textAlign: TextAlign.center,
                style: erTextStyle(context, size: 15)),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: ErColors.blue,
                  foregroundColor: Colors.white),
              onPressed: () => loginDialog(),
              child: Text('Iniciar sesión',
                  style: erTextStyle(context, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // Cajón ☰ -------------------------------------------------------------

  Widget _drawer(BuildContext context) {
    final serverIdx = _indexOf((p) => p is ServerPage);
    final chatIdx = _indexOf((p) => p is ChatPage);
    final settingsIdx = _indexOf((p) => p is SettingsPage);
    final idx = widget.selectedIndex;
    void go(int i) {
      Navigator.of(context).pop();
      widget.onSelect(i);
    }

    return Drawer(
      width: erIsWide(context) ? 320 : null,
      child: ChangeNotifierProvider.value(
        value: gFFI.peerTabModel,
        child: Consumer<PeerTabModel>(
          builder: (context, model, _) => Obx(() {
            final group = gFFI.groupModel;
            final cur = PeerTabIndex.values[model.currentTab];
            final onPeers = idx == 0;
            final selName = group.selectedAccessibleItemName.value;
            final isDevGroup = group.isSelectedDeviceGroup.value;
            final devGroups = group.deviceGroups.toList();
            final users = group.users.toList();
            final login = gFFI.userModel.userName.value.isNotEmpty;
            final abNames = gFFI.abModel.addressbooks.keys.toList();
            final abCur = gFFI.abModel.currentName.value;
            Widget section(PeerTabIndex t, IconData icon, String text) =>
                _navItem(context, icon, text, onPeers && cur == t, () {
                  Navigator.of(context).pop();
                  _selectSection(t);
                });
            return Column(
              children: [
                _accountHeader(context),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: erBrandTitle(context, size: 17)),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 12),
                    children: [
                      if (model.isEnabled[PeerTabIndex.recent.index])
                        section(PeerTabIndex.recent, Icons.history_rounded,
                            'Recientes'),
                      if (model.isEnabled[PeerTabIndex.fav.index])
                        section(PeerTabIndex.fav, Icons.star_border_rounded,
                            'Favoritos'),
                      if (model.isEnabled[PeerTabIndex.ab.index]) ...[
                        section(PeerTabIndex.ab, Icons.contacts_outlined,
                            'Direcciones'),
                        if (login && abNames.length > 1)
                          for (final name in abNames)
                            _navItem(
                                context,
                                Icons.menu_book_outlined,
                                erAbDisplayName(name),
                                onPeers &&
                                    cur == PeerTabIndex.ab &&
                                    abCur == name, () {
                              Navigator.of(context).pop();
                              _selectAddressBook(name);
                            }, indent: 22),
                      ],
                      if (model.isEnabled[PeerTabIndex.lan.index])
                        section(PeerTabIndex.lan, Icons.wifi_tethering_rounded,
                            'Red local'),
                      if (model.isEnabled[PeerTabIndex.group.index]) ...[
                        _navItem(
                            context,
                            Icons.groups_2_outlined,
                            'Electronics',
                            onPeers &&
                                cur == PeerTabIndex.group &&
                                selName.isEmpty, () {
                          Navigator.of(context).pop();
                          _selectSection(PeerTabIndex.group);
                        }, bold: true),
                        if (login)
                          for (final g in devGroups)
                            _navItem(
                                context,
                                Icons.desktop_windows_outlined,
                                g.name,
                                onPeers &&
                                    cur == PeerTabIndex.group &&
                                    isDevGroup &&
                                    selName == g.name, () {
                              Navigator.of(context).pop();
                              _selectGroupItem(g.name, true);
                            }, indent: 22),
                        if (login && devGroups.isEmpty)
                          for (final u in users)
                            _navItem(
                                context,
                                Icons.person_outline_rounded,
                                u.displayNameOrName,
                                onPeers &&
                                    cur == PeerTabIndex.group &&
                                    !isDevGroup &&
                                    selName == u.name, () {
                              Navigator.of(context).pop();
                              _selectGroupItem(u.name, false);
                            }, indent: 22),
                      ],
                      const Divider(height: 18),
                      if (serverIdx >= 0)
                        _navItem(
                            context,
                            Icons.screen_share_outlined,
                            'Compartir esta pantalla',
                            idx == serverIdx,
                            () => go(serverIdx)),
                      if (chatIdx >= 0)
                        _navItem(context, Icons.chat_bubble_outline_rounded,
                            'Chat', idx == chatIdx, () => go(chatIdx)),
                      if (settingsIdx >= 0)
                        _navItem(context, Icons.settings_outlined, 'Ajustes',
                            idx == settingsIdx, () => go(settingsIdx)),
                      _navItem(
                          context, Icons.help_outline_rounded, 'Ayuda', false,
                          () {
                        Navigator.of(context).pop();
                        erOpenHowToControl(context);
                      }),
                      _navItem(context, Icons.info_outline_rounded, 'Acerca de',
                          false, () {
                        Navigator.of(context).pop();
                        erAboutDialog(context);
                      }),
                      // RealVNC tiene «Enviar comentarios»; aquí no hay
                      // servicio para eso, se deja en gris.
                      _navItem(context, Icons.feedback_outlined,
                          'Enviar comentarios', false, null),
                    ],
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _accountHeader(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Obx(() {
      final user = gFFI.userModel;
      final login = user.userName.value.isNotEmpty;
      final email = (UserModel.getLocalUserInfo()?['email'] ?? '').toString();
      return Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(16, top + 16, 8, 14),
        decoration: const BoxDecoration(gradient: ErColors.gradient),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: login
                    ? [
                        Text(user.displayNameOrUserName,
                            overflow: TextOverflow.ellipsis,
                            style: erTitleStyle(context,
                                size: 17, color: Colors.white)),
                        if (email.isNotEmpty)
                          Text(email,
                              overflow: TextOverflow.ellipsis,
                              style: erTextStyle(context,
                                  size: 13,
                                  color: Colors.white.withOpacity(0.85))),
                      ]
                    : [
                        Text('Sin sesión',
                            style: erTitleStyle(context,
                                size: 17, color: Colors.white)),
                        InkWell(
                          onTap: () {
                            Navigator.of(context).pop();
                            loginDialog();
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                                'Iniciar sesión con la cuenta del panel',
                                style: erTextStyle(context,
                                        size: 13, color: Colors.white)
                                    .copyWith(
                                        decoration: TextDecoration.underline)),
                          ),
                        ),
                      ],
              ),
            ),
            if (login)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                color: ErColors.surface,
                onSelected: (v) {
                  if (v == 'panel') {
                    launchUrl(Uri.parse(kErPanelUrl),
                        mode: LaunchMode.externalApplication);
                  } else if (v == 'logout') {
                    user.logOut();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                      value: 'panel',
                      child: Text('Administrar cuenta',
                          style: erTextStyle(context, size: 14))),
                  PopupMenuItem(
                      value: 'logout',
                      child: Text('Cerrar sesión',
                          style: erTextStyle(context, size: 14))),
                ],
              ),
          ],
        ),
      );
    });
  }

  Widget _navItem(BuildContext context, IconData icon, String text,
      bool selected, VoidCallback? onTap,
      {double indent = 0, bool bold = false}) {
    final enabled = onTap != null;
    final color = !enabled
        ? Colors.white.withOpacity(0.35)
        : (selected ? ErColors.cyan : Colors.white.withOpacity(0.9));
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 46,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        padding: EdgeInsets.only(left: 12 + indent, right: 8),
        decoration: BoxDecoration(
          color: selected ? ErColors.selected : null,
          borderRadius: BorderRadius.circular(8),
          border: selected
              ? const Border(left: BorderSide(color: ErColors.cyan, width: 3))
              : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Text(text,
                  overflow: TextOverflow.ellipsis,
                  style: erTextStyle(context,
                      size: 14.5,
                      color: color,
                      weight: bold || selected
                          ? FontWeight.w600
                          : FontWeight.w400)),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ equipos

/// Vista de equipos de una sección con la cuadrícula tipo RealVNC.
class ErMobilePeersView extends BasePeersView {
  ErMobilePeersView({Key? key, required PeerTabIndex tab})
      : super(
          key: key,
          peerTabIndex: tab,
          erMobileGrid: true,
          peerFilter: tab == PeerTabIndex.group ? MyGroupPeerView.filter : null,
          peerCardBuilder: (Peer peer) =>
              ErMobilePeerCard(peer: peer, tab: tab),
        );

  @override
  Widget build(BuildContext context) {
    final w = super.build(context);
    switch (peerTabIndex) {
      case PeerTabIndex.recent:
        bind.mainLoadRecentPeers();
        break;
      case PeerTabIndex.fav:
        bind.mainLoadFavPeers();
        break;
      case PeerTabIndex.lan:
        bind.mainLoadLanPeers();
        bind.mainDiscover();
        break;
      default:
        break;
    }
    return w;
  }
}

/// Cuerpo de la pantalla con la barra inferior original oculta (el chat y
/// «Compartir pantalla» la usan para saber o cambiar la página actual).
/// `expand`: el Scaffold da al cuerpo un alto sin mínimo y, sin él, el Stack
/// tomaba el tamaño de su único hijo sin posición, el Offstage (0×0): la
/// lista medía 0 de alto y no se veía nada.
Widget erShellBody(Widget content, Widget navBar) => Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: content),
        Offstage(child: navBar),
      ],
    );

class ErMobileState {
  static final lastRefresh = Rxn<DateTime>();
  static final shownCount = 0.obs;
  static final List<String> errors = [];
}

String erAbDisplayName(String name) {
  if (name.isEmpty) return 'Direcciones';
  if (name == gFFI.abModel.personalAddressBookName()) return 'Mi libreta';
  return name;
}

bool _erErrorCaptureInstalled = false;

/// Guarda las últimas 5 excepciones de Flutter para el diagnóstico y hace
/// que un widget que truena muestre un texto en vez de quedar en blanco.
void erInstallErrorCapture() {
  if (_erErrorCaptureInstalled) return;
  _erErrorCaptureInstalled = true;
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final stack = (details.stack?.toString() ?? '')
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .take(6)
        .join('\n');
    final at = DateTime.now().toIso8601String().substring(11, 19);
    ErMobileState.errors.add('[$at] ${details.exceptionAsString()}\n$stack');
    while (ErMobileState.errors.length > 5) {
      ErMobileState.errors.removeAt(0);
    }
    previous?.call(details);
  };
  ErrorWidget.builder = (details) => Material(
        color: ErColors.night,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Error al mostrar la lista: ${details.exceptionAsString()}',
              style: const TextStyle(color: Color(0xFFFFB4A9), fontSize: 13)),
        ),
      );
}

PeerTabIndex _erCurrentTab() =>
    PeerTabIndex.values[gFFI.peerTabModel.currentTab];

/// El error del panel que aplica a la sección, o vacío.
String erMobilePanelError(PeerTabIndex tab) {
  if (tab != PeerTabIndex.group && tab != PeerTabIndex.ab) return '';
  final net = gFFI.userModel.networkError.value;
  if (net.isNotEmpty) return net;
  if (tab == PeerTabIndex.group) return gFFI.groupModel.groupLoadError.value;
  return '';
}

String erMobileEmptyText() {
  final tab = _erCurrentTab();
  final err = erMobilePanelError(tab);
  if (err.isNotEmpty) {
    return 'No se pudo leer el panel:\n$err\n\nJala hacia abajo para reintentar.';
  }
  final group = gFFI.groupModel;
  final where =
      tab == PeerTabIndex.group && group.selectedAccessibleItemName.isNotEmpty
          ? (group.isSelectedDeviceGroup.value
              ? 'en este grupo'
              : 'de este usuario')
          : 'en esta sección';
  if (ErState.onlineOnly.value) {
    return 'No hay equipos en línea $where (está activo «Solo en línea» '
        'en el filtro). Jala hacia abajo para actualizar.';
  }
  if (peerSearchText.value.trim().isNotEmpty) {
    return 'Ningún equipo $where coincide con la búsqueda.';
  }
  return 'No hay equipos $where. Jala hacia abajo para actualizar.';
}

/// Resumen para diagnosticar la lista (Acerca de › tocar la versión 5 veces).
String erMobileDiagnostics() {
  final user = gFFI.userModel;
  final group = gFFI.groupModel;
  final tab = _erCurrentTab();
  final token = bind.mainGetLocalOption(key: 'access_token');
  final peers = group.peers.toList();
  String or(String v, String empty) => v.isEmpty ? empty : v;
  final b = StringBuffer()
    ..writeln('Versión: ${erVersion()}')
    ..writeln('Usuario: ${or(user.userName.value, '(sin sesión)')}'
        ' · admin: ${user.isAdmin.value}')
    ..writeln('Token: ${token.isEmpty ? 'no' : 'sí'}')
    ..writeln('networkError: ${or(user.networkError.value, '(ninguno)')}')
    ..writeln('Grupo cargando: ${group.groupLoading.value}')
    ..writeln('Error del grupo: ${or(group.groupLoadError.value, '(ninguno)')}')
    ..writeln('Recibidos: ${group.users.length} usuarios, '
        '${peers.length} equipos, '
        '${group.deviceGroups.length} grupos de equipos')
    ..writeln('Grupos de equipos: '
        '${group.deviceGroups.map((e) => e.name).join(', ')}')
    ..writeln('Sección: ${tab.name}')
    ..writeln('Seleccionado: «${group.selectedAccessibleItemName.value}»'
        ' (${group.isSelectedDeviceGroup.value ? 'grupo de equipos' : 'usuario'})')
    ..writeln('Solo en línea: ${ErState.onlineOnly.value}'
        ' · búsqueda: «${peerSearchText.value}»')
    ..writeln('En el modelo de la vista: ${group.peersModel.peers.length}')
    ..writeln('Después del filtro (en pantalla): '
        '${ErMobileState.shownCount.value}')
    ..writeln('Última actualización: '
        '${ErMobileState.lastRefresh.value ?? '(nunca)'}');
  final ab = gFFI.abModel;
  final abPeers = ab.peersModel.peers;
  b
    ..writeln('Libretas: ${ab.addressbooks.entries.map((e) => '${erAbDisplayName(e.key)}'
        ' (${e.value.initialized ? e.value.peers.length : 'sin leer'})').join(', ')}')
    ..writeln('Libreta actual: ${erAbDisplayName(ab.currentName.value)}'
        ' · ${abPeers.length} entradas'
        '${abPeers.isEmpty ? '' : ': ${abPeers.take(30).map((e) => e.id).join(', ')}'}');
  if (ErMobileState.errors.isEmpty) {
    b.writeln('Excepciones: (ninguna)');
  } else {
    b.writeln('Excepciones (últimas ${ErMobileState.errors.length}):');
    for (final e in ErMobileState.errors) {
      b.writeln(e);
    }
  }
  for (final p in peers.take(30)) {
    final name = p.alias.isNotEmpty ? p.alias : p.hostname;
    b.writeln('- ${p.id} «$name» grupo=«${p.device_group_name}»'
        ' usuario=«${p.loginName}» en línea=${p.online}');
  }
  return b.toString();
}

void erDiagnosticsDialog(BuildContext context) {
  final text = erMobileDiagnostics();
  showDialog(
    context: context,
    builder: (ctx) => erThemed(AlertDialog(
      backgroundColor: ErColors.surface,
      title: Text('Diagnóstico',
          style: erTextStyle(ctx, size: 17, color: Colors.white)),
      content: SingleChildScrollView(
        child: SelectableText(text,
            style: erTextStyle(ctx, size: 12.5, color: Colors.white)),
      ),
      actions: [
        TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              showToast('Copiado');
            },
            child:
                Text('Copiar', style: erTextStyle(ctx, color: ErColors.cyan))),
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child:
                Text('Cerrar', style: erTextStyle(ctx, color: Colors.white70))),
      ],
    )),
  );
}

/// Cuadrícula: varias columnas con el celular abierto, una cerrado.
Widget erMobilePeerGrid(List<Peer> peers, Widget Function(Peer) item) {
  final n = peers.length;
  if (ErMobileState.shownCount.value != n) {
    Future.microtask(() => ErMobileState.shownCount.value = n);
  }
  return LayoutBuilder(builder: (context, c) {
    final w = c.maxWidth;
    if (peers.isEmpty) {
      // Siempre un texto y siempre desplazable: así «jalar hacia abajo»
      // funciona aunque no haya ningún equipo que pintar.
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: c.maxHeight,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(erMobileEmptyText(),
                    textAlign: TextAlign.center,
                    style: erTextStyle(context,
                        size: 15, color: Colors.white.withOpacity(0.8))),
              ),
            ),
          ),
        ],
      );
    }
    final cols = w >= kErWideWidth ? (w / 270).floor().clamp(2, 6) : 1;
    const gap = 10.0;
    const pad = 10.0;
    // Con ancho 0 daba una proporción negativa (aserción en debug).
    final cw = ((w - pad * 2 - gap * (cols - 1)) / cols).clamp(1.0, 1e6);
    final ch = cw * (cols == 1 ? 0.52 : 0.62) + 46;
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(pad, pad, pad, 96),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: gap,
        crossAxisSpacing: gap,
        childAspectRatio: cw / ch,
      ),
      itemCount: peers.length,
      itemBuilder: (context, i) => item(peers[i]),
    );
  });
}

class ErMobilePeerCard extends StatelessWidget {
  final Peer peer;
  final PeerTabIndex tab;
  const ErMobilePeerCard({Key? key, required this.peer, required this.tab})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final name = erPeerName(peer);
    return Material(
      color: ErColors.surface,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => connectInPeerTab(context, peer, tab),
        onLongPress: () => erPeerSheet(context, peer, tab),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _thumb()),
            SizedBox(
              height: 46,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: erTextStyle(context,
                            size: 14,
                            weight: FontWeight.w500,
                            color: Colors.white)),
                  ),
                  IconButton(
                    tooltip: 'Opciones del equipo',
                    icon: Icon(Icons.info_outline_rounded,
                        color: Colors.white.withOpacity(0.75)),
                    onPressed: () => erPeerSheet(context, peer, tab),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumb() {
    final fallback = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            ErColors.violet.withOpacity(0.35),
            ErColors.blue.withOpacity(0.25),
            ErColors.night,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: getPlatformImage(peer.platform, size: 44),
    );
    return Stack(
      children: [
        Positioned.fill(child: ErPeerThumb(id: peer.id, fallback: fallback)),
        Positioned(right: 8, bottom: 8, child: erOnlineBadge(peer.online)),
      ],
    );
  }
}

Widget erOnlineBadge(bool online, {double size = 24}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: online ? ErColors.online : ErColors.offline,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Icon(online ? Icons.check_rounded : Icons.close_rounded,
          size: size * 0.62, color: Colors.white),
    );

/// Hoja del botón (i) o de mantener presionado un equipo.
Future<void> erPeerSheet(
    BuildContext context, Peer peer, PeerTabIndex tab) async {
  final favs = (await bind.mainGetFav()).toList();
  final isFav = favs.contains(peer.id);
  final canEdit = tab != PeerTabIndex.ab || gFFI.abModel.current.canWrite();
  final canRemove = tab != PeerTabIndex.group && canEdit;
  final card = erCardFor(peer, tab);
  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      Widget tile(IconData icon, String text, VoidCallback? action,
              {bool bold = false, Color? color}) =>
          ListTile(
            leading: Icon(icon,
                color: action == null
                    ? Colors.white.withOpacity(0.3)
                    : (color ?? Colors.white.withOpacity(0.85))),
            title: Text(text,
                style: erTextStyle(ctx,
                    size: 15,
                    weight: bold ? FontWeight.w700 : FontWeight.w400,
                    color: action == null
                        ? Colors.white.withOpacity(0.35)
                        : (color ?? Colors.white))),
            enabled: action != null,
            onTap: action == null
                ? null
                : () {
                    Navigator.of(ctx).pop();
                    action();
                  },
          );
      return erThemed(SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2)),
                ),
                ListTile(
                  leading: SizedBox(
                    width: 64,
                    height: 40,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: ErPeerThumb(
                          id: peer.id,
                          fallback: Container(
                              color: ErColors.night,
                              alignment: Alignment.center,
                              child:
                                  getPlatformImage(peer.platform, size: 26))),
                    ),
                  ),
                  title: Text(erPeerName(peer),
                      overflow: TextOverflow.ellipsis,
                      style: erTitleStyle(ctx, size: 16, color: Colors.white)),
                  subtitle: Text(
                      'ID ${formatID(peer.id)} · ${peer.online ? 'En línea' : 'Apagado'}',
                      style: erTextStyle(ctx,
                          size: 12.5, color: Colors.white.withOpacity(0.6))),
                  trailing: erOnlineBadge(peer.online, size: 20),
                ),
                const Divider(height: 1),
                tile(Icons.play_arrow_rounded, 'Conectarse',
                    () => connectInPeerTab(context, peer, tab),
                    bold: true, color: ErColors.cyan),
                tile(
                    Icons.folder_open_outlined,
                    'Transferir archivos',
                    () => connectInPeerTab(context, peer, tab,
                        isFileTransfer: true)),
                const Divider(height: 1),
                tile(Icons.edit_outlined, 'Renombrar',
                    canEdit ? () => card.erRename() : null),
                tile(isFav ? Icons.star_rounded : Icons.star_border_rounded,
                    isFav ? 'Quitar de Favoritos' : 'Agregar a Favoritos',
                    () async {
                  final list = (await bind.mainGetFav()).toList();
                  if (isFav) {
                    list.remove(peer.id);
                  } else if (!list.contains(peer.id)) {
                    list.add(peer.id);
                  }
                  await bind.mainStoreFav(favs: list);
                  if (tab == PeerTabIndex.fav) await bind.mainLoadFavPeers();
                  showToast(
                      isFav ? 'Quitado de Favoritos' : 'Agregado a Favoritos');
                }),
                tile(Icons.tune_rounded, 'Propiedades',
                    () => erShowProperties(peer, tab)),
                tile(Icons.key_off_outlined, 'Olvidar contraseña',
                    () => card.erForgetPassword()),
                tile(Icons.delete_outline_rounded, 'Eliminar',
                    canRemove ? () => card.erRemove() : null),
                const Divider(height: 1),
                tile(Icons.more_horiz_rounded, 'Más opciones…', () {
                  final s = MediaQuery.of(context).size;
                  card.erShowFullMenu(
                      context,
                      RelativeRect.fromLTRB(s.width / 2, s.height / 3,
                          s.width / 2, s.height / 3));
                }),
              ],
            ),
          ),
        ),
      ));
    },
  );
}

/// «+»: como «New connection» de RealVNC (dirección y nombre).
void erNewConnectionDialog(BuildContext context) {
  final idCtl = TextEditingController();
  final nameCtl = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) {
      void submit() async {
        final id = idCtl.text.replaceAll(' ', '').trim();
        if (id.isEmpty) return;
        final name = nameCtl.text.trim();
        Navigator.of(ctx).pop();
        if (name.isNotEmpty) {
          await bind.mainSetPeerAlias(id: id, alias: name);
        }
        if (context.mounted) connect(context, id);
      }

      return erThemed(AlertDialog(
        backgroundColor: ErColors.surface,
        title: Text('Nueva conexión',
            style: erTitleStyle(ctx, size: 18, color: Colors.white)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: idCtl,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.visiblePassword,
                inputFormatters: [IDTextInputFormatter()],
                style: erTextStyle(ctx, size: 16, color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'ID del equipo',
                  hintText: 'Ej. 431 400 798',
                  labelStyle: erTextStyle(ctx, color: Colors.white70),
                ),
                onSubmitted: (_) => submit(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtl,
                style: erTextStyle(ctx, size: 16, color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Nombre (opcional)',
                  hintText: 'Ej. Laptop de Mostrador',
                  labelStyle: erTextStyle(ctx, color: Colors.white70),
                ),
                onSubmitted: (_) => submit(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancelar',
                  style: erTextStyle(ctx, color: Colors.white70))),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: idCtl,
            builder: (_, v, __) => TextButton(
              onPressed: v.text.trim().isEmpty ? null : submit,
              child: Text('Conectar',
                  style: erTextStyle(ctx,
                      weight: FontWeight.w600,
                      color: v.text.trim().isEmpty
                          ? Colors.white30
                          : ErColors.cyan)),
            ),
          ),
        ],
      ));
    },
  );
}

void erAboutDialog(BuildContext context) {
  var taps = 0;
  showDialog(
    context: context,
    builder: (ctx) => erThemed(AlertDialog(
      backgroundColor: ErColors.surface,
      title: erBrandTitle(ctx, size: 17),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (++taps < 5) return;
              taps = 0;
              erDiagnosticsDialog(ctx);
            },
            child: Text('Versión ${erVersion()}',
                style: erTextStyle(ctx, size: 14, color: Colors.white)),
          ),
          const SizedBox(height: 6),
          Text('Basado en RustDesk (AGPL-3.0)',
              style: erTextStyle(ctx, size: 12.5, color: Colors.white60)),
          const SizedBox(height: 10),
          InkWell(
            onTap: () => launchUrl(Uri.parse(kErPanelUrl),
                mode: LaunchMode.externalApplication),
            child: Text(kErPanelUrl,
                style: erTextStyle(ctx, size: 13, color: ErColors.cyan)
                    .copyWith(decoration: TextDecoration.underline)),
          ),
          const SizedBox(height: 4),
          Text('Electronics México',
              style: erTextStyle(ctx, size: 12.5, color: Colors.white60)),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              erCheckForUpdatesManually();
            },
            child: Text('Buscar actualizaciones',
                style: erTextStyle(ctx, color: ErColors.cyan))),
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child:
                Text('Cerrar', style: erTextStyle(ctx, color: Colors.white70))),
      ],
    )),
  );
}
