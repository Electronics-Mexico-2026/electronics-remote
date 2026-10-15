// «Propiedades» del equipo (Alt+Enter) con pestañas General / Opciones /
// Experto, como en RealVNC. Solo usa opciones que RustDesk ya guarda por
// equipo (alias, relay, RDP, favoritos, contraseña recordada).

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../common/formatter/id_formatter.dart';
import '../../common/widgets/dialog.dart';
import '../../consts.dart';
import '../../models/peer_model.dart';
import '../../models/peer_tab_model.dart';
import '../../models/platform_model.dart';
import 'er_peer_card.dart';
import 'er_theme.dart';
import 'er_thumbs.dart';

String _sectionName(PeerTabIndex tab, Peer peer) {
  if (peer.device_group_name.isNotEmpty) return peer.device_group_name;
  switch (tab) {
    case PeerTabIndex.recent:
      return 'Recientes';
    case PeerTabIndex.fav:
      return 'Favoritos';
    case PeerTabIndex.lan:
      return 'Red local';
    case PeerTabIndex.ab:
      return 'Direcciones (${gFFI.abModel.currentName.value})';
    case PeerTabIndex.group:
      return 'Electronics';
  }
}

String _platformName(String p) {
  switch (p) {
    case kPeerPlatformWindows:
      return 'Windows';
    case kPeerPlatformLinux:
      return 'Linux';
    case kPeerPlatformMacOS:
      return 'macOS';
    case kPeerPlatformAndroid:
      return 'Android';
  }
  return p;
}

Future<void> erShowProperties(Peer peer, PeerTabIndex tab) async {
  final id = peer.id;
  final isAb = tab == PeerTabIndex.ab;
  final canWrite = !isAb || gFFI.abModel.current.canWrite();
  final oldAlias = isAb
      ? (gFFI.abModel.find(id)?.alias ?? '')
      : await bind.mainGetPeerOption(id: id, key: 'alias');
  final aliasCtl = TextEditingController(text: oldAlias);
  final rdpPortCtl = TextEditingController(
      text: await bind.mainGetPeerOption(id: id, key: 'rdp_port'));
  final rdpUserCtl = TextEditingController(
      text: await bind.mainGetPeerOption(id: id, key: 'rdp_username'));
  final hasPassword =
      (await bind.mainPeerHasPassword(id: id) || peer.hash.isNotEmpty).obs;
  final forceRelay = option2bool(kOptionForceAlwaysRelay,
          await bind.mainGetPeerOption(id: id, key: kOptionForceAlwaysRelay))
      .obs;
  final favs = (await bind.mainGetFav()).toList();
  final isFav = favs.contains(id).obs;
  final title = erPeerName(peer);

  gFFI.dialogManager.show((setState, close, context) {
    Future<void> submit() async {
      final newAlias = aliasCtl.text.trim();
      if (canWrite && newAlias != oldAlias) {
        if (isAb) {
          await gFFI.abModel.changeAlias(id: id, alias: newAlias);
        }
        await bind.mainSetPeerAlias(id: id, alias: newAlias);
        if (tab == PeerTabIndex.recent) bind.mainLoadRecentPeers();
        if (tab == PeerTabIndex.fav) bind.mainLoadFavPeers();
        if (tab == PeerTabIndex.lan) bind.mainLoadLanPeers();
        if (tab == PeerTabIndex.group) gFFI.groupModel.pull();
      }
      await bind.mainSetPeerOption(
          id: id, key: 'rdp_port', value: rdpPortCtl.text.trim());
      await bind.mainSetPeerOption(
          id: id, key: 'rdp_username', value: rdpUserCtl.text);
      close();
    }

    Widget row(String label, Widget value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 150,
                child: Text(label,
                    style: erTextStyle(context,
                        size: 13, color: Theme.of(context).hintColor)),
              ),
              Expanded(child: value),
            ],
          ),
        );
    Widget txt(String s) =>
        SelectableText(s.isEmpty ? '—' : s, style: erTextStyle(context));
    Widget box(String title, List<Widget> children) => Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          decoration: BoxDecoration(
            border: Border.all(color: ErColors.line),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: erTitleStyle(context, size: 14)),
              const SizedBox(height: 6),
              ...children,
            ],
          ),
        );

    final details = [
      if (peer.hostname.isNotEmpty) peer.hostname,
      if (peer.platform.isNotEmpty) _platformName(peer.platform),
      if (peer.username.isNotEmpty) 'usuario ${peer.username}',
    ].join(' | ');

    final general = ListView(
      padding: const EdgeInsets.only(right: 8, top: 8),
      children: [
        Center(
          child: Container(
            width: 256,
            height: 144,
            decoration: BoxDecoration(
              border: Border.all(color: ErColors.line),
              borderRadius: BorderRadius.circular(6),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: ErPeerThumb(
                id: id,
                fallback:
                    Center(child: getPlatformImage(peer.platform, size: 56)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        row('ID del equipo:', txt(formatID(id))),
        row(
            'Nombre:',
            TextField(
              controller: aliasCtl,
              enabled: canWrite,
              style: erTextStyle(context),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Identificador amistoso',
              ),
            )),
        row('Nombre en el equipo:', txt(peer.hostname)),
        row('Grupo:', txt(_sectionName(tab, peer))),
        row('Detalles:', txt(details)),
        row(
            'Visto por última vez:',
            Text(peer.online ? 'En línea' : 'Desconectado',
                style: erTextStyle(context,
                    color: peer.online ? ErColors.online : null))),
        box('Etiquetas', [
          Text(peer.tags.isEmpty ? 'Sin etiquetas' : peer.tags.join(', '),
              style: erTextStyle(context)),
          if (isAb && canWrite && gFFI.abModel.currentAbTags.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  editAbTagDialog(gFFI.abModel.getPeerTags(id),
                      (selected) async {
                    await gFFI.abModel.changeTagForPeers([id], selected);
                  });
                },
                child: const Text('Editar etiquetas…'),
              ),
            ),
          if (peer.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Nota: ${peer.note}', style: erTextStyle(context)),
          ],
        ]),
        box('Seguridad', [
          Obx(() => Row(
                children: [
                  Icon(
                      hasPassword.value
                          ? Icons.lock_rounded
                          : Icons.lock_open_rounded,
                      size: 16,
                      color: hasPassword.value
                          ? ErColors.online
                          : Theme.of(context).hintColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        hasPassword.value
                            ? 'Contraseña recordada: conecta sin pedirla'
                            : 'Sin contraseña recordada: la pedirá al conectar',
                        style: erTextStyle(context)),
                  ),
                ],
              )),
          const SizedBox(height: 6),
          Obx(() => OutlinedButton(
                onPressed: hasPassword.value
                    ? () {
                        erCardFor(peer, tab).erForgetPassword();
                        hasPassword.value = false;
                      }
                    : null,
                child: const Text('Olvidar contraseña guardada'),
              )),
        ]),
      ],
    );

    final options = ListView(
      padding: const EdgeInsets.only(right: 8, top: 8),
      children: [
        Obx(() => CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: forceRelay.value,
              title: Text('Conectar siempre por el servidor (relay)',
                  style: erTextStyle(context)),
              onChanged: (v) async {
                if (v == null) return;
                await bind.mainSetPeerOption(
                    id: id,
                    key: kOptionForceAlwaysRelay,
                    value: bool2option(kOptionForceAlwaysRelay, v));
                forceRelay.value = v;
              },
            )),
        Obx(() => CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: isFav.value,
              title: Text('Mostrar en Favoritos', style: erTextStyle(context)),
              onChanged: (v) async {
                if (v == null) return;
                final list = (await bind.mainGetFav()).toList();
                if (v && !list.contains(id)) list.add(id);
                if (!v) list.remove(id);
                await bind.mainStoreFav(favs: list);
                bind.mainLoadFavPeers();
                isFav.value = v;
              },
            )),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (isWindows)
              OutlinedButton.icon(
                onPressed: () {
                  bind.mainCreateShortcut(id: id);
                  showToast('Acceso directo creado en el escritorio');
                },
                icon: const Icon(Icons.shortcut_rounded, size: 16),
                label: const Text('Crear acceso directo'),
              ),
            OutlinedButton.icon(
              onPressed: () {
                bind.mainWol(id: id);
                showToast('Señal para encender enviada (WOL)');
              },
              icon: const Icon(Icons.power_settings_new_rounded, size: 16),
              label: const Text('Encender por red (WOL)'),
            ),
          ],
        ),
      ],
    );

    final expert = ListView(
      padding: const EdgeInsets.only(right: 8, top: 8),
      children: [
        Text('Escritorio remoto de Windows (RDP) por túnel',
            style: erTitleStyle(context, size: 14)),
        const SizedBox(height: 6),
        row(
            'Puerto RDP:',
            TextField(
              controller: rdpPortCtl,
              style: erTextStyle(context),
              decoration:
                  const InputDecoration(isDense: true, hintText: '3389'),
            )),
        row(
            'Usuario RDP:',
            TextField(
              controller: rdpUserCtl,
              style: erTextStyle(context),
              decoration: const InputDecoration(isDense: true),
            )),
        const SizedBox(height: 12),
        Text('Datos del equipo', style: erTitleStyle(context, size: 14)),
        const SizedBox(height: 6),
        row('ID:', txt(id)),
        row('Plataforma:', txt(_platformName(peer.platform))),
        row('Usuario del sistema:', txt(peer.username)),
        row('Cuenta del panel:', txt(peer.loginName)),
        row('Grupo del panel:', txt(peer.device_group_name)),
      ],
    );

    return CustomAlertDialog(
      title:
          Text('$title : Propiedades', style: erTitleStyle(context, size: 17)),
      contentBoxConstraints: const BoxConstraints(maxWidth: 560, minWidth: 520),
      content: SizedBox(
        width: 520,
        height: 470,
        child: DefaultTabController(
          length: 3,
          child: Column(
            children: [
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelStyle: erTextStyle(context, weight: FontWeight.w600),
                unselectedLabelStyle: erTextStyle(context),
                indicatorColor: ErColors.cyan,
                tabs: const [
                  Tab(text: 'General', height: 34),
                  Tab(text: 'Opciones', height: 34),
                  Tab(text: 'Experto', height: 34),
                ],
              ),
              Expanded(
                child: TabBarView(children: [general, options, expert]),
              ),
            ],
          ),
        ),
      ),
      actions: [
        dialogButton('Cancelar', onPressed: close, isOutline: true),
        dialogButton('Aceptar', onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}
