// Menú de la ventana de sesión en el orden de RealVNC (su menú F8). Cada
// opción llama a algo que la barra de RustDesk ya hace; solo cambia el
// acomodo y los nombres.

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../common/widgets/dialog.dart';
import '../../consts.dart';
import '../../models/chat_model.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import '../../models/state_model.dart';
import '../widgets/remote_toolbar.dart';
import '../widgets/tabbar_widget.dart';
import '../../common/er_update.dart';

const String kErAppTitle = 'Electronics Remote';

/// «NOMBRE (HOSTNAME) - Electronics Remote»
String erSessionWindowTitle(String id, FFI? ffi) {
  final name = DesktopTab.tablabelGetter(id).value;
  final host = ffi?.ffiModel.pi.hostname ?? '';
  if (host.isNotEmpty && host.toLowerCase() != name.toLowerCase()) {
    return '$name ($host) - $kErAppTitle';
  }
  return '$name - $kErAppTitle';
}

void erSetSessionWindowTitle(String id, FFI ffi) {
  try {
    WindowController.fromWindowId(stateGlobal.windowId)
        .setTitle(erSessionWindowTitle(id, ffi));
  } catch (_) {}
}

// Teclas Ctrl / Alt sostenidas desde el menú (por sesión).
final Map<String, bool> _heldCtrl = {};
final Map<String, bool> _heldAlt = {};

Widget _label(String text, {bool bold = false}) => Text(text,
    style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null);

Widget _shortcut(String text) =>
    Text(text, style: const TextStyle(fontSize: 12, color: Colors.grey));

List<Widget> erSessionMenuChildren(BuildContext context, String id, FFI ffi,
    void Function(bool) setFullscreen) {
  final sessionId = ffi.sessionId;
  final pi = ffi.ffiModel.pi;
  final perms = ffi.ffiModel.permissions;
  final isDefaultConn = ffi.connType == ConnType.defaultConn;
  final wc = WindowController.fromWindowId(stateGlobal.windowId);
  final fullscreen = stateGlobal.fullscreen.isTrue;
  final viewStyle = ffi.canvasModel.viewStyle.style;
  final muted = bind.sessionGetToggleOptionSync(
      sessionId: sessionId, arg: 'disable-audio');
  final canKeyboard = ffi.ffiModel.keyboard && !ffi.ffiModel.viewOnly;
  final key = sessionId.toString();

  return [
    MenuButton(
        ffi: ffi,
        onPressed: () {
          if (fullscreen) {
            setFullscreen(false);
          } else {
            wc.unmaximize();
          }
        },
        child: _label('Restaurar')),
    MenuButton(
        ffi: ffi, onPressed: () => wc.minimize(), child: _label('Minimizar')),
    MenuButton(
        ffi: ffi, onPressed: () => wc.maximize(), child: _label('Maximizar')),
    const Divider(),
    MenuButton(
        ffi: ffi,
        trailingIcon: _shortcut('Alt+F4'),
        onPressed: () async {
          if (await showConnEndAuditDialogCloseCanceled(ffi: ffi)) return;
          closeConnection(id: id);
        },
        child: _label('Cerrar', bold: true)),
    const Divider(),
    CkbMenuButton(
        ffi: ffi,
        value: fullscreen,
        onChanged: (_) => setFullscreen(!fullscreen),
        child: _label('Pantalla completa')),
    if (isDefaultConn &&
        canKeyboard &&
        ffi.inputModel.isRelativeMouseModeSupported)
      CkbMenuButton(
          ffi: ffi,
          value: ffi.inputModel.relativeMouseMode.value,
          onChanged: (v) {
            if (v == null) return;
            final prev = ffi.inputModel.relativeMouseMode.value;
            if (!ffi.inputModel.setRelativeMouseMode(v)) {
              ffi.inputModel.relativeMouseMode.value = prev;
            }
          },
          child: _label('Movimiento relativo del puntero')),
    const Divider(),
    if (isDefaultConn && canKeyboard) ...[
      MenuButton(
          ffi: ffi,
          trailingIcon: _shortcut('F8'),
          onPressed: () => ffi.inputModel.inputKey('VK_F8'),
          child: _label('Enviar F8')),
      if (pi.platform == kPeerPlatformWindows ||
          pi.platform == kPeerPlatformLinux)
        MenuButton(
            ffi: ffi,
            onPressed: () => bind.sessionCtrlAltDel(sessionId: sessionId),
            child: _label('Enviar Ctrl+Alt+Supr', bold: true)),
      CkbMenuButton(
          ffi: ffi,
          value: _heldCtrl[key] ?? false,
          onChanged: (v) {
            final down = !(_heldCtrl[key] ?? false);
            _heldCtrl[key] = down;
            ffi.inputModel.inputKey('VK_CONTROL', down: down, press: false);
          },
          child: _label('Tecla Ctrl')),
      CkbMenuButton(
          ffi: ffi,
          value: _heldAlt[key] ?? false,
          onChanged: (v) {
            final down = !(_heldAlt[key] ?? false);
            _heldAlt[key] = down;
            ffi.inputModel.inputKey('VK_MENU', down: down, press: false);
          },
          child: _label('Tecla Alt')),
      const Divider(),
    ],
    CkbMenuButton(
        ffi: ffi,
        value: viewStyle == kRemoteViewStyleAdaptive,
        onChanged: (v) {
          final value = viewStyle == kRemoteViewStyleAdaptive
              ? kRemoteViewStyleOriginal
              : kRemoteViewStyleAdaptive;
          bind
              .sessionSetViewStyle(sessionId: sessionId, value: value)
              .then((_) => ffi.canvasModel.updateViewStyle());
        },
        child: _label('Redimensionar automáticamente')),
    if (isDefaultConn && perms['audio'] != false)
      CkbMenuButton(
          ffi: ffi,
          value: muted,
          onChanged: (_) => bind.sessionToggleOption(
              sessionId: sessionId, value: 'disable-audio'),
          child: _label('Silenciar audio')),
    if (pi.version.isNotEmpty)
      MenuButton(
          ffi: ffi,
          onPressed: () => sessionRefreshVideo(sessionId, pi),
          child: _label('Actualizar pantalla')),
    if (isDefaultConn &&
        (ffi.recordingModel.start || perms['recording'] != false))
      CkbMenuButton(
          ffi: ffi,
          value: ffi.recordingModel.start,
          onChanged: (_) => ffi.recordingModel.toggle(),
          child: _label('Grabar sesión', bold: true)),
    const Divider(),
    MenuButton(
        ffi: ffi,
        onPressed: () => _sessionInfoDialog(id, ffi),
        child: _label('Información de la sesión…')),
    MenuButton(
        ffi: ffi,
        onPressed: () => _aboutDialog(ffi),
        child: _label('Acerca de Electronics Remote…')),
    MenuButton(
        ffi: ffi,
        onPressed: () => _sessionPropertiesDialog(ffi),
        child: _label('Propiedades…')),
    const Divider(),
    if (isDefaultConn && isDesktop)
      MenuButton(
          ffi: ffi,
          onPressed: () => connect(context, id,
              isFileTransfer: true,
              connToken: bind.sessionGetConnToken(sessionId: sessionId)),
          child: _label('Transferir archivos…', bold: true)),
    MenuButton(
        ffi: ffi,
        onPressed: () {
          ffi.chatModel
              .changeCurrentKey(MessageKey(ffi.id, ChatModel.clientModeID));
          ffi.chatModel.toggleChatOverlay();
        },
        child: _label('Chat…', bold: true)),
  ];
}

void _sessionInfoDialog(String id, FFI ffi) {
  final pi = ffi.ffiModel.pi;
  ffi.dialogManager.show((setState, close, context) {
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 170, child: Text(k)),
              Expanded(child: SelectableText(v.isEmpty ? '—' : v)),
            ],
          ),
        );
    final d = pi.displays;
    final cur = pi.currentDisplay;
    final disp = (cur >= 0 && cur < d.length)
        ? '${d[cur].width} × ${d[cur].height}'
        : '';
    return CustomAlertDialog(
      title: const Text('Información de la sesión'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row('Equipo:', DesktopTab.tablabelGetter(id).value),
          row('ID:', id),
          row('Nombre en el equipo:', pi.hostname),
          row('Usuario de Windows:', pi.username),
          row('Sistema:', pi.platform),
          row('Versión remota:', pi.version),
          row('Pantallas:', '${pi.displays.length}'),
          row('Resolución:', disp),
          row('Grabando:', ffi.recordingModel.start ? 'Sí' : 'No'),
        ],
      ),
      actions: [dialogButton('Cerrar', onPressed: close)],
      onSubmit: close,
      onCancel: close,
    );
  });
}

void _aboutDialog(FFI ffi) {
  ffi.dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
      title: const Text('Acerca de Electronics Remote'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Electronics Remote ${erVersion()}'),
          const SizedBox(height: 6),
          const Text('Electronics México — basado en RustDesk (AGPL-3.0).'),
        ],
      ),
      actions: [dialogButton('Cerrar', onPressed: close)],
      onSubmit: close,
      onCancel: close,
    );
  });
}

void _sessionPropertiesDialog(FFI ffi) async {
  final sessionId = ffi.sessionId;
  final quality = (await bind.sessionGetImageQuality(sessionId: sessionId) ??
          kRemoteImageQualityBalanced)
      .obs;
  ffi.dialogManager.show((setState, close, context) {
    Widget opt(String label, String value) => Obx(() => RadioListTile<String>(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: value,
          groupValue: quality.value,
          title: Text(label),
          onChanged: (v) async {
            if (v == null) return;
            await bind.sessionSetImageQuality(sessionId: sessionId, value: v);
            quality.value = v;
          },
        ));
    return CustomAlertDialog(
      title: const Text('Propiedades de la sesión'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Calidad de imagen',
              style: TextStyle(fontWeight: FontWeight.w600)),
          opt('Mejor imagen', kRemoteImageQualityBest),
          opt('Equilibrada', kRemoteImageQualityBalanced),
          opt('Más rápida (poca red)', kRemoteImageQualityLow),
          const SizedBox(height: 6),
          const Text(
              'Más opciones (códec, FPS, cursor, privacidad) en el botón de '
              'pantalla de la barra.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
      actions: [dialogButton('Aceptar', onPressed: close)],
      onSubmit: close,
      onCancel: close,
    );
  });
}

/// Botón ☰ de la barra de la sesión con el menú de arriba. F8 lo abre.
class ErSessionMenuButton extends StatefulWidget {
  final String id;
  final FFI ffi;
  final MenuController controller;
  final void Function(bool) setFullscreen;
  const ErSessionMenuButton(
      {Key? key,
      required this.id,
      required this.ffi,
      required this.controller,
      required this.setFullscreen})
      : super(key: key);

  @override
  State<ErSessionMenuButton> createState() => _ErSessionMenuButtonState();
}

class _ErSessionMenuButtonState extends State<ErSessionMenuButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: widget.controller,
      // Se arma al abrir para que las palomitas (pantalla completa, audio,
      // grabación...) muestren el estado de ese momento.
      onOpen: () => setState(() {}),
      menuChildren: erSessionMenuChildren(
          context, widget.id, widget.ffi, widget.setFullscreen),
      builder: (context, controller, _) => Tooltip(
        message: 'Menú de sesión (F8)',
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: _hover ? MyTheme.accent : MyTheme.button,
              ),
              child:
                  const Icon(Icons.menu_rounded, color: Colors.white, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}
