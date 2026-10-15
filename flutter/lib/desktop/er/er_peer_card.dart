// Cuadro de equipo y menú de clic derecho con el acomodo de RealVNC Viewer:
// miniatura grande, insignia ✓ verde (en línea) / ✕ gris (apagado), nombre
// abajo; menú «Conectarse» en negrita, Renombrar, Eliminar, Duplicar y
// Propiedades, y debajo todo lo que RustDesk ya ofrecía.

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../common/formatter/id_formatter.dart';
import '../../common/widgets/peer_card.dart';
import '../../models/peer_model.dart';
import '../../models/peer_tab_model.dart';
import '../widgets/popup_menu.dart';
import 'er_properties.dart';
import 'er_theme.dart';
import 'er_thumbs.dart';

/// Tamaño del cuadro en la cuadrícula (lo usa peers_view).
const double kErGridCardWidth = 176;
const double kErGridCardHeight = 146;

class ErGridCard extends StatefulWidget {
  final Peer peer;
  final PeerTabIndex tab;
  final Widget? trailing;
  const ErGridCard(
      {Key? key, required this.peer, required this.tab, this.trailing})
      : super(key: key);

  @override
  State<ErGridCard> createState() => _ErGridCardState();
}

class _ErGridCardState extends State<ErGridCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final peer = widget.peer;
    final name = erPeerName(peer);
    final details = <String>[
      'ID: ${formatID(peer.id)}',
      if (peer.hostname.isNotEmpty) 'Equipo: ${peer.hostname}',
      if (peer.username.isNotEmpty) 'Usuario: ${peer.username}',
      if (peer.device_group_name.isNotEmpty) 'Grupo: ${peer.device_group_name}',
      if (peer.tags.isNotEmpty) 'Etiquetas: ${peer.tags.join(', ')}',
      if (peer.note.isNotEmpty) 'Nota: ${peer.note}',
    ].join('\n');
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Obx(() {
        final selected = ErState.selectedId.value == peer.id;
        return Tooltip(
          message: details,
          waitDuration: const Duration(milliseconds: 900),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            decoration: BoxDecoration(
              color: selected
                  ? ErColors.selected
                  : (_hover
                      ? Theme.of(context).hoverColor
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? ErColors.blue : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Stack(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Expanded(child: _thumb(context, peer)),
                    const SizedBox(height: 6),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: erTextStyle(context,
                          size: 12.5, weight: FontWeight.w500),
                    ),
                  ],
                ),
                if (widget.trailing != null)
                  Positioned(top: 2, right: 2, child: widget.trailing!),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _thumb(BuildContext context, Peer peer) {
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
      child: getPlatformImage(peer.platform, size: 40),
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: ErColors.line, width: 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: ErPeerThumb(id: peer.id, fallback: fallback),
            ),
          ),
        ),
        Positioned(
          right: -4,
          bottom: -4,
          child: _badge(peer.online),
        ),
      ],
    );
  }

  Widget _badge(bool online) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: online ? ErColors.online : ErColors.offline,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Icon(online ? Icons.check_rounded : Icons.close_rounded,
          size: 14, color: Colors.white),
    );
  }
}

/// Menú de clic derecho: primero el acomodo de RealVNC y luego lo demás.
List<MenuEntryBase<String>> erArrangeMenu(
    BuildContext context,
    BasePeerCard card,
    List<MenuEntryBase<String>> original,
    Expando<bool> builtIn) {
  final peer = card.peer;
  final tab = card.tab;
  final padding = card.menuPadding;
  final canEdit = tab != PeerTabIndex.ab || gFFI.abModel.current.canWrite();
  final canRemove = tab != PeerTabIndex.group && canEdit;

  MenuEntryButton<String> item(String text,
      {String? shortcut,
      bool bold = false,
      bool enabled = true,
      required Function() proc}) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Row(
        children: [
          Text(text,
              style:
                  bold ? style?.copyWith(fontWeight: FontWeight.w700) : style),
          const Spacer(),
          if (shortcut != null)
            Text(shortcut,
                style: style?.copyWith(
                    color: (style.color ?? Colors.grey).withOpacity(0.6),
                    fontSize: 12)),
        ],
      ),
      proc: proc,
      padding: padding,
      dismissOnClicked: true,
      enabled: enabled.obs,
    );
  }

  final head = <MenuEntryBase<String>>[
    item('Conectarse',
        bold: true, proc: () => connectInPeerTab(context, peer, tab)),
    MenuEntryDivider<String>(),
    item('Renombrar',
        shortcut: 'F2', enabled: canEdit, proc: () => card.erRename()),
    item('Eliminar',
        shortcut: 'Supr', enabled: canRemove, proc: () => card.erRemove()),
    // RustDesk no tiene «duplicar conexión»; se deja gris como en RealVNC.
    item('Duplicar', shortcut: 'Ctrl+D', enabled: false, proc: () {}),
    item('Propiedades…',
        shortcut: 'Alt+Enter', proc: () => erShowProperties(peer, tab)),
    MenuEntryDivider<String>(),
  ];
  final rest = original.where((e) => builtIn[e] != true).toList();
  // Quitar divisores que queden al inicio, al final o repetidos.
  final cleaned = <MenuEntryBase<String>>[];
  for (final e in rest) {
    final isDiv = e is MenuEntryDivider;
    if (isDiv && (cleaned.isEmpty || cleaned.last is MenuEntryDivider)) {
      continue;
    }
    cleaned.add(e);
  }
  while (cleaned.isNotEmpty && cleaned.last is MenuEntryDivider) {
    cleaned.removeLast();
  }
  return [...head, ...cleaned];
}

/// Tarjeta «virtual» para correr las acciones de RustDesk sobre un equipo
/// desde la barra de menú (sin que exista el widget en pantalla).
BasePeerCard erCardFor(Peer peer, PeerTabIndex tab) {
  switch (tab) {
    case PeerTabIndex.recent:
      return RecentPeerCard(peer: peer);
    case PeerTabIndex.fav:
      return FavoritePeerCard(peer: peer);
    case PeerTabIndex.lan:
      return DiscoveredPeerCard(peer: peer);
    case PeerTabIndex.ab:
      return AddressBookPeerCard(peer: peer);
    case PeerTabIndex.group:
      return MyGroupPeerCard(peer: peer);
  }
}
