// «Preferencias de la aplicación» con las secciones de RealVNC (Privacidad,
// Aspecto, Impresión, Servidor proxy, Grabando, Resolución de problemas,
// Experto). Cada opción es una opción que RustDesk ya tiene; lo que no cabe
// aquí abre la página de ajustes completa en la sección que corresponde.

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../common/er_update.dart';
import '../../common/widgets/peer_card.dart';
import '../../common/widgets/setting_widgets.dart';
import '../../consts.dart';
import '../../models/platform_model.dart';
import '../pages/connection_page.dart';
import '../pages/desktop_setting_page.dart';
import 'er_theme.dart';
import 'er_thumbs.dart';

const _sections = [
  'Privacidad',
  'Aspecto',
  'Impresión',
  'Servidor proxy',
  'Grabando',
  'Resolución de problemas',
  'Experto',
];

void _openSettings(SettingsTabKey key, VoidCallback close) {
  close();
  if (DesktopSettingPage.tabKeys.contains(key)) {
    DesktopSettingPage.switch2page(key);
  } else if (DesktopSettingPage.tabKeys.isNotEmpty) {
    DesktopSettingPage.switch2page(DesktopSettingPage.tabKeys.first);
  }
}

Future<void> _forgetAll() async {
  final ids = <String>{};
  for (final p in gFFI.recentPeersModel.peers) {
    ids.add(p.id);
  }
  for (final p in gFFI.favoritePeersModel.peers) {
    ids.add(p.id);
  }
  for (final p in gFFI.lanPeersModel.peers) {
    ids.add(p.id);
  }
  for (final p in gFFI.abModel.peersModel.peers) {
    ids.add(p.id);
  }
  for (final p in gFFI.groupModel.peersModel.peers) {
    ids.add(p.id);
  }
  for (final id in ids) {
    await bind.mainForgetPassword(id: id);
  }
  await ErThumbs.deleteAll();
  showToast('Se olvidaron las contraseñas guardadas y las capturas');
}

void erShowPreferences() {
  final section = 0.obs;
  gFFI.dialogManager.show((setState, close, context) {
    Widget check(String label, bool value, Future<void> Function(bool) onSet,
        {bool enabled = true}) {
      return CheckboxListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: value,
        enabled: enabled,
        title: Text(label, style: erTextStyle(context)),
        onChanged: (v) async {
          if (v == null) return;
          await onSet(v);
          setState(() {});
        },
      );
    }

    Widget group(String title, List<Widget> children) => Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            border: Border.all(color: ErColors.line),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: erTitleStyle(context, size: 14)),
              ...children,
            ],
          ),
        );

    Widget button(String text, VoidCallback onPressed) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
                onPressed: onPressed,
                child: Text(text, style: erTextStyle(context))),
          ),
        );

    Widget note(String text) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(text,
              style: erTextStyle(context,
                  size: 12, color: Theme.of(context).hintColor)),
        );

    bool userDefault(String key) => getOtherDefaultSettingOption(key) == 'Y';
    Future<void> setUserDefault(String key, bool v) =>
        setOtherDefaultSettingOption(key, v ? 'Y' : defaultOptionNo);

    List<Widget> privacy() => [
          check(
              'Escuchar audio desde el equipo remoto',
              !userDefault(kOptionDisableAudio),
              (v) => setUserDefault(kOptionDisableAudio, !v)),
          check(
              'Permitir copiar y pegar texto a y desde el equipo remoto',
              !userDefault(kOptionDisableClipboard),
              (v) => setUserDefault(kOptionDisableClipboard, !v)),
          group('Contraseñas de los equipos', [
            check(
                'Preguntar si se recuerdan las contraseñas al conectarse',
                erOptOn(kErOptAskRemember),
                (v) => erSetOpt(kErOptAskRemember, v ? 'Y' : 'N')),
            note('Si lo apagas, el cuadro de contraseña ya no ofrece '
                '«Recordar contraseña» y no se guarda ninguna nueva.'),
            button('Proteger las preferencias con PIN…',
                () => _openSettings(SettingsTabKey.safety, close)),
          ]),
          group('Vistas previas del escritorio', [
            check('Ocultar capturas de pantalla para los equipos',
                ErState.hideThumbs.value, (v) async {
              ErState.hideThumbs.value = v;
              await erSetOpt(kErOptHideThumbs, v ? 'Y' : 'N');
            }),
          ]),
          button('Olvidar todos los datos confidenciales', () {
            gFFI.dialogManager.show((setState2, close2, context2) {
              Future<void> ok() async {
                close2();
                await _forgetAll();
              }

              return CustomAlertDialog(
                title: Text('Olvidar datos confidenciales',
                    style: erTitleStyle(context2, size: 16)),
                content: Text(
                    'Se borran las contraseñas recordadas de todos los '
                    'equipos y las capturas guardadas. La próxima vez que '
                    'te conectes te pedirá la contraseña.',
                    style: erTextStyle(context2)),
                actions: [
                  dialogButton('Cancelar', onPressed: close2, isOutline: true),
                  dialogButton('Olvidar', onPressed: ok),
                ],
                onSubmit: ok,
                onCancel: close2,
              );
            });
          }),
        ];

    List<Widget> appearance() {
      final mode = MyTheme.getThemeModePreference();
      Widget radio(String label, ThemeMode m) => RadioListTile<ThemeMode>(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: m,
            groupValue: mode,
            title: Text(label, style: erTextStyle(context)),
            onChanged: (v) async {
              if (v == null) return;
              await MyTheme.changeDarkMode(v);
              setState(() {});
            },
          );
      return [
        group('Tema', [
          radio('Oscuro (Electronics México)', ThemeMode.dark),
          radio('Claro', ThemeMode.light),
          radio('Igual que Windows', ThemeMode.system),
        ]),
        group('Equipos', [
          Obx(() => check('Ver como iconos grandes (con captura)',
                  peerCardUiType.value == PeerUiType.grid, (v) async {
                peerCardUiType.value = v ? PeerUiType.grid : PeerUiType.list;
                await bind.setLocalFlutterOption(
                    k: kOptionPeerCardUiType,
                    v: peerCardUiType.value.index.toString());
              })),
          Obx(() => check('Mostrar barra lateral', ErState.showSidebar.value,
              (v) => ErState.toggle(ErState.showSidebar, kErOptShowSidebar))),
          Obx(() => check(
              'Mostrar barra de estado',
              ErState.showStatusbar.value,
              (v) =>
                  ErState.toggle(ErState.showStatusbar, kErOptShowStatusbar))),
        ]),
        button('Idioma y más opciones de aspecto…',
            () => _openSettings(SettingsTabKey.general, close)),
      ];
    }

    List<Widget> printing() => [
          note('La impresora remota deja imprimir en esta PC lo que mandes '
              'a imprimir en el equipo remoto (solo Windows).'),
          if (DesktopSettingPage.tabKeys.contains(SettingsTabKey.printer))
            button('Configurar impresión remota…',
                () => _openSettings(SettingsTabKey.printer, close))
          else
            note('No disponible en este equipo.'),
        ];

    List<Widget> proxy() => [
          note('Úsalo solo si la red de la oficina obliga a salir por un '
              'proxy (Socks5 o HTTP).'),
          button('Configurar servidor proxy…', () {
            close();
            changeSocks5Proxy();
          }),
          button('Servidor de ID, relay y API…',
              () => _openSettings(SettingsTabKey.network, close)),
        ];

    List<Widget> recording() => [
          if (!bind.isIncomingOnly())
            check(
                'Grabar automáticamente las sesiones que yo inicio',
                mainGetLocalBoolOptionSync(kOptionAllowAutoRecordOutgoing),
                (v) =>
                    mainSetLocalBoolOption(kOptionAllowAutoRecordOutgoing, v)),
          if (!bind.isOutgoingOnly())
            check(
                'Grabar automáticamente las sesiones entrantes',
                mainGetBoolOptionSync(kOptionAllowAutoRecordIncoming),
                (v) => mainSetBoolOption(kOptionAllowAutoRecordIncoming, v)),
          note('En una sesión también puedes usar «Grabar sesión» del menú '
              '(F8 o el botón ☰ de la barra).'),
          button('Carpeta de grabaciones y más…',
              () => _openSettings(SettingsTabKey.general, close)),
        ];

    List<Widget> troubleshooting() => [
          group('Versión', [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SelectableText(
                  'Electronics Remote ${erVersion().isEmpty ? bind.mainGetVersion() : erVersion()}',
                  style: erTextStyle(context)),
            ),
            button('Buscar actualizaciones', () => erCheckForUpdatesManually()),
          ]),
          group('Servicio de esta PC', [
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: OnlineStatusWidget(),
            ),
          ]),
          button('Acerca de y registros…',
              () => _openSettings(SettingsTabKey.about, close)),
        ];

    List<Widget> expert() => [
          note('Todas las opciones avanzadas de RustDesk siguen disponibles '
              'en la página de ajustes completa.'),
          button('General', () => _openSettings(SettingsTabKey.general, close)),
          button(
              'Seguridad', () => _openSettings(SettingsTabKey.safety, close)),
          button('Red', () => _openSettings(SettingsTabKey.network, close)),
          button(
              'Pantalla', () => _openSettings(SettingsTabKey.display, close)),
          button('Cuenta', () => _openSettings(SettingsTabKey.account, close)),
        ];

    List<Widget> body(int i) {
      switch (i) {
        case 0:
          return privacy();
        case 1:
          return appearance();
        case 2:
          return printing();
        case 3:
          return proxy();
        case 4:
          return recording();
        case 5:
          return troubleshooting();
        default:
          return expert();
      }
    }

    return CustomAlertDialog(
      title: Row(
        children: [
          erIsotipo(size: 22),
          const SizedBox(width: 8),
          Text('Preferencias de la aplicación',
              style: erTitleStyle(context, size: 17)),
        ],
      ),
      contentBoxConstraints: const BoxConstraints(maxWidth: 700, minWidth: 640),
      content: SizedBox(
        width: 660,
        height: 440,
        child: Obx(() => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 190,
                  decoration: BoxDecoration(
                    border: Border.all(color: ErColors.line),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.all(4),
                    children: [
                      for (var i = 0; i < _sections.length; i++)
                        InkWell(
                          onTap: () => section.value = i,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: section.value == i
                                  ? ErColors.blue
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(_sections[i],
                                style: erTextStyle(context,
                                    color: section.value == i
                                        ? Colors.white
                                        : null)),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: ErColors.line),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: body(section.value),
                    ),
                  ),
                ),
              ],
            )),
      ),
      actions: [
        dialogButton('Aceptar', onPressed: close),
      ],
      onSubmit: close,
      onCancel: close,
    );
  });
}
