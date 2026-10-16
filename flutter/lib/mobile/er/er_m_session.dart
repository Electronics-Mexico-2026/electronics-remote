// Electronics Remote para Android: la sesión con el acomodo de RealVNC
// Viewer. Barra flotante tipo píldora arriba (fijar · teclado · mouse ·
// información · ayuda · cerrar), fila de teclas especiales deslizable sobre
// el teclado, «modo mouse» con botones y barra de desplazamiento, panel de
// información a la derecha y la página «Cómo controlar». También la pantalla
// de «Conectando…» y el cuadro «Autenticación». Todo llama a funciones que
// RustDesk ya tiene.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../common/er_update.dart';
import '../../common/formatter/id_formatter.dart';
import '../../consts.dart';
import '../../models/input_model.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import '../widgets/gesture_help.dart';
import 'er_m_theme.dart';

const String _kErOptToolbarPin = 'er-mobile-toolbar-pin';

// ------------------------------------------------------- valores de inicio

const String _kErOptMouseDefault = 'er-mobile-mouse-default-v1';

/// Como RealVNC: el dedo mueve el cursor como touchpad (modo mouse de
/// RustDesk). Una sola vez por instalación se regresa a modo mouse por si
/// quedó en «táctil»; después se respeta lo que el usuario elija.
void erMobileApplyMouseDefault() {
  if (erGetOpt(_kErOptMouseDefault) == 'Y') return;
  bind.mainSetLocalOption(key: kOptionTouchMode, value: 'N');
  erSetOpt(_kErOptMouseDefault, 'Y');
}

/// Al abrir la sesión, la pantalla del equipo entra ajustada al celular.
Future<void> erMobileFitOnOpen(FFI ffi) async {
  await bind.sessionSetViewStyle(
      sessionId: ffi.sessionId, value: kRemoteViewStyleAdaptive);
  await ffi.canvasModel.updateViewStyle();
}

// --------------------------------------------------------------- conectando

/// Pantalla completa de «Conectando…» (como RealVNC) en lugar del cuadro
/// chico de RustDesk. Se cierra sola cuando RustDesk cierra los diálogos.
void erShowConnecting(OverlayDialogManager dm, String id) {
  var name = '';
  try {
    name = bind.mainGetPeerOptionSync(id: id, key: 'alias').trim();
  } catch (_) {}
  if (name.isEmpty) name = formatID(id);
  dm.show((setState, close, context) {
    cancel() {
      dm.dismissAll();
      closeConnection();
    }

    return _ErFullDialog(
        onCancel: cancel,
        child: erThemed(Builder(
          builder: (context) => Material(
            color: ErColors.night,
            child: SafeArea(
              child: SizedBox.expand(
                child: Column(
                  children: [
                    const Spacer(flex: 3),
                    erIsotipo(size: 96),
                    const SizedBox(height: 18),
                    Text(name,
                        textAlign: TextAlign.center,
                        style: erTitleStyle(context,
                            size: 20, color: Colors.white)),
                    const SizedBox(height: 10),
                    Text('Conectando…',
                        style: erTextStyle(context,
                            size: 15, color: Colors.white.withOpacity(0.7))),
                    const SizedBox(height: 22),
                    const SizedBox(
                      width: 160,
                      child: LinearProgressIndicator(
                        color: ErColors.cyan,
                        backgroundColor: ErColors.line,
                      ),
                    ),
                    const Spacer(flex: 4),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE5484D),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 12),
                      ),
                      onPressed: cancel,
                      child: Text('Cancelar',
                          style: erTextStyle(context,
                              weight: FontWeight.w600, color: Colors.white)),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        )));
  }, tag: 'er-connecting');
}

// ----------------------------------------------------------- autenticación

/// Cuadro «Autenticación» como RealVNC Android: barra con ✕ y «Continuar»,
/// contraseña con ojo, «¿Olvidó su contraseña?», «Recordar contraseña» y el
/// equipo al que se entra.
Future<void> erMobilePasswordDialog(
  SessionID sessionId,
  OverlayDialogManager dialogManager,
  TextEditingController passwordController,
  bool rememberInit,
) async {
  final askRemember = erOptOn(kErOptAskRemember);
  var remember =
      askRemember && (rememberInit || erOptOn(kErOptRememberDefault));
  var obscure = true;
  final id = gFFI.id;
  var alias = '';
  try {
    alias =
        (await bind.sessionGetPeerOption(sessionId: sessionId, name: 'alias'))
            .trim();
  } catch (_) {}
  final showHelp = false.obs;

  dialogManager.dismissAll();
  dialogManager.show((setState, close, context) {
    cancel() {
      close();
      closeConnection();
    }

    submit() {
      final password = passwordController.text.trim();
      if (password.isEmpty) return;
      if (askRemember) erSetOpt(kErOptRememberDefault, remember ? 'Y' : 'N');
      gFFI.login('', '', sessionId, password, remember);
      close();
      dialogManager.showLoading(translate('Logging in...'),
          onCancel: closeConnection);
    }

    if (isAndroid) gFFI.invokeMethod("enable_soft_keyboard", true);
    return _ErFullDialog(
        onCancel: cancel,
        onSubmit: submit,
        child: erThemed(Builder(builder: (context) {
          final wide = erIsWide(context);
          final card = Material(
            color: ErColors.surface,
            elevation: 8,
            borderRadius: wide ? BorderRadius.circular(6) : null,
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 56,
                  decoration: const BoxDecoration(gradient: ErColors.gradient),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Cancelar',
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white),
                        onPressed: cancel,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('Autenticación',
                            style: erTitleStyle(context,
                                size: 19, color: Colors.white)),
                      ),
                      TextButton(
                        onPressed: submit,
                        child: Text('Continuar',
                            style: erTextStyle(context,
                                size: 14.5,
                                weight: FontWeight.w700,
                                color: Colors.white)),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: TextField(
                    controller: passwordController,
                    autofocus: true,
                    obscureText: obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.visiblePassword,
                    style: erTextStyle(context, size: 16, color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      labelStyle: erTextStyle(context, color: Colors.white70),
                      suffixIcon: IconButton(
                        icon: Icon(
                            obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: Colors.white70),
                        onPressed: () => setState(() => obscure = !obscure),
                      ),
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                ),
                Center(
                  child: TextButton(
                    onPressed: () => showHelp.value = !showHelp.value,
                    child: Text('¿Olvidó su contraseña?',
                        style: erTextStyle(context,
                                size: 13, color: ErColors.cyan)
                            .copyWith(decoration: TextDecoration.underline)),
                  ),
                ),
                Obx(() => showHelp.value
                    ? Container(
                        margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: ErColors.selected,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                            'La contraseña permanente la ve quien está en ese '
                            'equipo, en Electronics Remote › «Este equipo», o el '
                            'administrador en el panel $kErPanelUrl.',
                            style: erTextStyle(context,
                                size: 12.5, color: Colors.white)),
                      )
                    : const SizedBox.shrink()),
                if (askRemember)
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    value: remember,
                    onChanged: (v) => setState(() => remember = v),
                    title: Text('Recordar contraseña',
                        style: erTextStyle(context,
                            size: 15, color: Colors.white)),
                    subtitle: Text(
                        'Se guarda cifrada solo en este dispositivo y nunca se '
                        'sincroniza con otros.',
                        style: erTextStyle(context,
                            size: 12, color: Colors.white.withOpacity(0.6))),
                  ),
                Container(height: 8, color: ErColors.night),
                ListTile(
                  leading: const Icon(Icons.desktop_windows_outlined,
                      color: ErColors.cyan),
                  title: Text(alias.isEmpty ? formatID(id) : alias,
                      overflow: TextOverflow.ellipsis,
                      style:
                          erTextStyle(context, size: 15, color: Colors.white)),
                  subtitle: Text('Electronics Remote',
                      style: erTextStyle(context,
                          size: 12.5, color: Colors.white.withOpacity(0.6))),
                ),
                if (alias.isNotEmpty)
                  ListTile(
                    leading: Icon(Icons.tag_rounded,
                        color: Colors.white.withOpacity(0.7)),
                    title: Text(formatID(id),
                        style: erTextStyle(context,
                            size: 15, color: Colors.white)),
                    subtitle: Text('ID del equipo',
                        style: erTextStyle(context,
                            size: 12.5, color: Colors.white.withOpacity(0.6))),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          );
          return Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                    top: wide ? 24 : 0,
                    bottom: MediaQuery.of(context).viewInsets.bottom),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: wide ? 560 : 10000),
                  child: card,
                ),
              ),
            ),
          );
        })));
  });
}

/// Los diálogos de RustDesk deben ser CustomAlertDialog; este pinta su
/// propio contenido a pantalla completa.
class _ErFullDialog extends CustomAlertDialog {
  final Widget child;
  const _ErFullDialog(
      {required this.child, Function()? onCancel, Function()? onSubmit})
      : super(
            content: const SizedBox.shrink(),
            onCancel: onCancel,
            onSubmit: onSubmit);

  @override
  Widget build(BuildContext context) => child;
}

// ------------------------------------------------------------ modificadores

/// Modificadores «fijos» (doble toque). Los de un solo toque se sueltan
/// después de la siguiente tecla, como en RealVNC.
final Set<String> erLockedMods = <String>{};
final ValueNotifier<int> erModsTick = ValueNotifier<int>(0);

bool _modGet(InputModel m, String k) {
  switch (k) {
    case 'shift':
      return m.shift;
    case 'ctrl':
      return m.ctrl;
    case 'alt':
      return m.alt;
    default:
      return m.command;
  }
}

void _modSet(InputModel m, String k, bool v) {
  switch (k) {
    case 'shift':
      m.shift = v;
      break;
    case 'ctrl':
      m.ctrl = v;
      break;
    case 'alt':
      m.alt = v;
      break;
    default:
      m.command = v;
  }
  erModsTick.value++;
}

/// Se llama después de mandar una tecla: suelta los modificadores de un
/// solo toque.
void erAfterRemoteKey() {
  final m = gFFI.inputModel;
  for (final k in const ['shift', 'ctrl', 'alt', 'command']) {
    if (_modGet(m, k) && !erLockedMods.contains(k)) _modSet(m, k, false);
  }
}

// ------------------------------------------------------------- la sesión

class ErSessionActions {
  final VoidCallback openKeyboard;
  final VoidCallback hideKeyboard;
  final bool Function() keyboardVisible;
  final VoidCallback showOptions;
  final VoidCallback showActions;
  final VoidCallback chat;
  final VoidCallback close;
  const ErSessionActions({
    required this.openKeyboard,
    required this.hideKeyboard,
    required this.keyboardVisible,
    required this.showOptions,
    required this.showActions,
    required this.chat,
    required this.close,
  });
}

class ErSessionOverlay extends StatefulWidget {
  final String id;
  final ErSessionActions actions;
  const ErSessionOverlay({Key? key, required this.id, required this.actions})
      : super(key: key);

  @override
  State<ErSessionOverlay> createState() => _ErSessionOverlayState();
}

class _ErSessionOverlayState extends State<ErSessionOverlay> {
  bool _pinned = false;
  bool _barVisible = true;
  bool _keysOn = false;
  bool _mouseOn = false;
  bool _infoOn = false;
  double _barDx = 0;
  Timer? _hideTimer;
  double _scrollAcc = 0;
  bool _kbWasVisible = false;

  FFI get _ffi => gFFI;
  InputModel get _input => _ffi.inputModel;

  @override
  void initState() {
    super.initState();
    _pinned = erGetOpt(_kErOptToolbarPin) == 'Y';
    _bumpHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    erLockedMods.clear();
    _input.resetModifiers();
    super.dispose();
  }

  /// Sin fijar, la barra se oculta a los 20 s sin usarla (como RealVNC).
  void _bumpHide() {
    _hideTimer?.cancel();
    if (_pinned) return;
    _hideTimer = Timer(const Duration(seconds: 20), () {
      if (mounted && !_pinned) setState(() => _barVisible = false);
    });
  }

  void _touch(VoidCallback f) {
    f();
    if (mounted) setState(() {});
    _bumpHide();
  }

  bool get _canInput {
    final m = _ffi.ffiModel;
    return !m.viewOnly && m.keyboard;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final kb = MediaQuery.of(context).viewInsets.bottom > 0;
    // Como RealVNC: las teclas extra viven con el teclado. Si el teclado del
    // celular se cierra (atrás, gesto), la fila también se va y el campo
    // oculto suelta el foco para que el teclado no vuelva a salir solo.
    if (_kbWasVisible && !kb && _keysOn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || MediaQuery.of(context).viewInsets.bottom > 0) return;
        setState(() => _keysOn = false);
        widget.actions.hideKeyboard();
      });
    }
    _kbWasVisible = kb;
    final keysH = _keysOn ? 48.0 : 0.0;
    return erThemed(Stack(
      children: [
        if (_mouseOn && _canInput && !_ffi.ffiModel.isPeerAndroid)
          ..._mouseMode(context, keysH),
        if (_keysOn && _canInput)
          Positioned(
              left: 0, right: 0, bottom: 0, child: _keysBar(context, kb)),
        _toolbar(context, size),
        if (_infoOn) ..._infoPanel(context, size),
      ],
    ));
  }

  // Barra flotante ------------------------------------------------------

  Widget _toolbar(BuildContext context, Size size) {
    const barW = 6 * 44.0 + 16;
    final maxDx = (size.width - barW) / 2 - 8;
    final dx = _barDx.clamp(-maxDx.abs(), maxDx.abs());
    if (!_barVisible) {
      // Pestañita para volver a mostrar la barra.
      return Positioned(
        top: MediaQuery.of(context).padding.top,
        left: size.width / 2 - 32 + dx,
        child: GestureDetector(
          onTap: () => _touch(() => _barVisible = true),
          child: Container(
            width: 64,
            height: 22,
            decoration: BoxDecoration(
              color: ErColors.night.withOpacity(0.85),
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(12)),
              border: Border.all(color: ErColors.blue.withOpacity(0.7)),
            ),
            child: const Icon(Icons.keyboard_arrow_down_rounded,
                size: 20, color: Colors.white),
          ),
        ),
      );
    }
    Widget btn(IconData icon, String tip, VoidCallback? onTap,
            {bool active = false}) =>
        Tooltip(
          message: tip,
          child: InkResponse(
            onTap: onTap == null ? null : () => _touch(onTap),
            radius: 22,
            child: SizedBox(
              width: 44,
              height: 40,
              child: Icon(icon,
                  size: 22,
                  color: onTap == null
                      ? Colors.white24
                      : (active ? ErColors.cyan : Colors.white)),
            ),
          ),
        );
    return Positioned(
      top: 10 + MediaQuery.of(context).padding.top,
      left: size.width / 2 - barW / 2 + dx,
      child: GestureDetector(
        onHorizontalDragUpdate: (d) => setState(() =>
            _barDx = (_barDx + d.delta.dx).clamp(-maxDx.abs(), maxDx.abs())),
        onHorizontalDragEnd: (_) => _bumpHide(),
        child: Container(
          width: barW,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: ErColors.night.withOpacity(0.88),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: ErColors.blue.withOpacity(0.75)),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 10),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              btn(_pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  _pinned ? 'Desfijar la barra' : 'Fijar la barra', () {
                _pinned = !_pinned;
                erSetOpt(_kErOptToolbarPin, _pinned ? 'Y' : 'N');
              }, active: _pinned),
              btn(Icons.keyboard_outlined, 'Teclado',
                  _canInput ? _toggleKeyboard : null,
                  active: _keysOn),
              btn(
                  Icons.mouse_outlined,
                  'Modo mouse',
                  _canInput && !_ffi.ffiModel.isPeerAndroid
                      ? () => _mouseOn = !_mouseOn
                      : null,
                  active: _mouseOn),
              btn(Icons.info_outline_rounded, 'Información',
                  () => _infoOn = true,
                  active: _infoOn),
              btn(Icons.help_outline_rounded, 'Cómo controlar',
                  () => erOpenHowToControl(context, inSession: true)),
              btn(Icons.close_rounded, 'Desconectar', widget.actions.close),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleKeyboard() {
    if (_keysOn) {
      _keysOn = false;
      widget.actions.hideKeyboard();
    } else {
      _keysOn = true;
      widget.actions.openKeyboard();
    }
  }

  // Fila de teclas especiales -------------------------------------------

  Widget _keysBar(BuildContext context, bool kbVisible) {
    final pi = _ffi.ffiModel.pi;
    final isMac = pi.platform == kPeerPlatformMacOS;
    final isWinOrLinux = pi.platform == kPeerPlatformWindows ||
        pi.platform == kPeerPlatformLinux;
    void key(String vk) {
      _input.inputKey(vk);
      erAfterRemoteKey();
    }

    Widget sep() => Container(
        width: 1,
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: Colors.white24);
    Widget k(String label, VoidCallback onTap, {double? fontSize}) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            constraints: const BoxConstraints(minWidth: 40),
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            child: Text(label,
                style: erTextStyle(context,
                    size: fontSize ?? 14,
                    weight: FontWeight.w500,
                    color: Colors.white)),
          ),
        );
    Widget mod(String label, String name) => ValueListenableBuilder<int>(
          valueListenable: erModsTick,
          builder: (context, _, __) {
            final on = _modGet(_input, name);
            final locked = erLockedMods.contains(name);
            return GestureDetector(
              onTap: () {
                if (on) {
                  erLockedMods.remove(name);
                  _modSet(_input, name, false);
                } else {
                  _modSet(_input, name, true);
                }
              },
              onDoubleTap: () {
                erLockedMods.add(name);
                _modSet(_input, name, true);
              },
              child: Container(
                constraints: const BoxConstraints(minWidth: 42),
                height: 36,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(horizontal: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on
                      ? (locked ? ErColors.cyan : ErColors.blue)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(label,
                    style: erTextStyle(context,
                        size: 14,
                        weight: FontWeight.w600,
                        color: Colors.white)),
              ),
            );
          },
        );
    final items = <Widget>[
      mod('⇧', 'shift'),
      mod('Ctrl', 'ctrl'),
      mod('Alt', 'alt'),
      mod(isMac ? '⌘' : '⊞', 'command'),
      sep(),
      k('⌫', () => key('VK_BACK'), fontSize: 17),
      k('Supr', () => key('VK_DELETE')),
      k('Esc', () => key('VK_ESCAPE')),
      k('Tab', () => key('VK_TAB')),
      k('Ins', () => key('VK_INSERT')),
      k('↵', () => key('VK_RETURN'), fontSize: 17),
      sep(),
      k('↑', () => key('VK_UP'), fontSize: 17),
      k('↓', () => key('VK_DOWN'), fontSize: 17),
      k('←', () => key('VK_LEFT'), fontSize: 17),
      k('→', () => key('VK_RIGHT'), fontSize: 17),
      sep(),
      k('Inicio', () => key('VK_HOME')),
      k('Fin', () => key('VK_END')),
      k('RePág', () => key('VK_PRIOR')),
      k('AvPág', () => key('VK_NEXT')),
      sep(),
      for (var i = 1; i <= 12; i++) k('F$i', () => key('VK_F$i')),
      if (isWinOrLinux) ...[
        sep(),
        k('ImpPant', () => key('VK_SNAPSHOT')),
        k('Ctrl+Alt+Supr',
            () => bind.sessionCtrlAltDel(sessionId: _ffi.sessionId)),
      ],
      const SizedBox(width: 8),
    ];
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: ErColors.surface.withOpacity(0.97),
        border: const Border(top: BorderSide(color: ErColors.blue, width: 1)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: kbVisible ? 'Ocultar teclado' : 'Mostrar teclado',
            icon: Icon(
                kbVisible
                    ? Icons.keyboard_hide_outlined
                    : Icons.keyboard_outlined,
                color: ErColors.cyan),
            onPressed: () {
              if (widget.actions.keyboardVisible()) {
                widget.actions.hideKeyboard();
              } else {
                widget.actions.openKeyboard();
              }
              setState(() {});
            },
          ),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: items),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Modo mouse ----------------------------------------------------------

  List<Widget> _mouseMode(BuildContext context, double bottomOffset) {
    Widget button(String label, MouseButtons b) => Expanded(
          child: Listener(
            onPointerDown: (_) => _input.tapDown(b),
            onPointerUp: (_) => _input.tapUp(b),
            onPointerCancel: (_) => _input.tapUp(b),
            child: Container(
              height: 58,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
                border: Border.all(color: Colors.white38),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(label,
                  style: erTextStyle(context,
                      size: 13, color: Colors.white.withOpacity(0.85))),
            ),
          ),
        );
    return [
      Positioned(
        left: 6,
        right: 64,
        bottom: bottomOffset + 6,
        child: Row(children: [
          button('Izquierdo', MouseButtons.left),
          button('Central', MouseButtons.wheel),
          button('Derecho', MouseButtons.right),
        ]),
      ),
      Positioned(
        right: 8,
        top: 90,
        bottom: bottomOffset + 76,
        child: GestureDetector(
          onVerticalDragUpdate: (d) {
            _scrollAcc += d.delta.dy / 12;
            if (_scrollAcc >= 1) {
              _input.scroll(1);
              _scrollAcc = 0;
            } else if (_scrollAcc <= -1) {
              _input.scroll(-1);
              _scrollAcc = 0;
            }
          },
          child: Container(
            width: 48,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.35),
              border: Border.all(color: Colors.white38),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Center(
                child: Icon(Icons.drag_handle_rounded,
                    size: 30, color: Colors.white70)),
          ),
        ),
      ),
      Positioned(
        right: 8,
        bottom: bottomOffset + 6,
        child: InkWell(
          onTap: () => setState(() => _mouseOn = false),
          child: Container(
            width: 48,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              border: Border.all(color: Colors.white38),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ),
      ),
    ];
  }

  // Panel de información ------------------------------------------------

  List<Widget> _infoPanel(BuildContext context, Size size) {
    final w = size.width < 420 ? size.width * 0.9 : 380.0;
    final ffiModel = _ffi.ffiModel;
    final pi = ffiModel.pi;
    var name = '';
    try {
      name = bind.mainGetPeerOptionSync(id: widget.id, key: 'alias').trim();
    } catch (_) {}
    if (name.isEmpty)
      name = pi.hostname.isNotEmpty ? pi.hostname : formatID(widget.id);
    Widget row(IconData icon, String value, String label) => ListTile(
          dense: true,
          leading: Icon(icon, color: ErColors.cyan),
          title: Text(value,
              style: erTextStyle(context, size: 14.5, color: Colors.white)),
          subtitle: Text(label,
              style: erTextStyle(context,
                  size: 12, color: Colors.white.withOpacity(0.6))),
        );
    void closePanel() => setState(() => _infoOn = false);
    return [
      Positioned.fill(
        child: GestureDetector(
          onTap: closePanel,
          child: Container(color: Colors.black38),
        ),
      ),
      Positioned(
        top: 0,
        bottom: 0,
        right: 0,
        width: w,
        child: Material(
          color: ErColors.surface,
          elevation: 12,
          child: SafeArea(
            left: false,
            child: Column(
              children: [
                Container(
                  height: 56,
                  decoration: const BoxDecoration(gradient: ErColors.gradient),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                        tooltip: 'Cerrar',
                        onPressed: closePanel,
                      ),
                      Expanded(
                        child: Text(name,
                            overflow: TextOverflow.ellipsis,
                            style: erTitleStyle(context,
                                size: 17, color: Colors.white)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.more_vert_rounded,
                            color: Colors.white),
                        tooltip: 'Más acciones',
                        onPressed: () {
                          closePanel();
                          widget.actions.showActions();
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: AnimatedBuilder(
                    animation: _ffi.qualityMonitorModel,
                    builder: (context, _) {
                      final q = _ffi.qualityMonitorModel.data;
                      final displays = pi.getCurDisplays();
                      final sizeText = displays.isEmpty
                          ? '—'
                          : displays
                              .map((d) => '${d.width} × ${d.height}')
                              .join(', ');
                      final speed = [
                        if ((q.speed ?? '').isNotEmpty) q.speed!,
                        if ((q.delay ?? '').isNotEmpty) 'retraso ${q.delay} ms',
                        if ((q.fps ?? '').isNotEmpty) '${q.fps} fps',
                      ].join(' · ');
                      return ListView(
                        children: [
                          row(Icons.desktop_windows_outlined, sizeText,
                              'Tamaño del escritorio'),
                          row(
                              Icons.build_outlined,
                              pi.version.isEmpty ? '—' : pi.version,
                              'Versión del equipo remoto'),
                          row(
                              Icons.shield_outlined,
                              ffiModel.secure == true
                                  ? 'Cifrada de extremo a extremo'
                                  : 'Sin cifrar',
                              'Cifrado'),
                          row(
                              Icons.contrast_rounded,
                              (q.codecFormat ?? '').isEmpty
                                  ? '—'
                                  : q.codecFormat!,
                              'Codificación'),
                          row(Icons.speed_rounded, speed.isEmpty ? '—' : speed,
                              'Velocidad estimada'),
                          row(
                              Icons.alt_route_rounded,
                              ffiModel.direct == null
                                  ? '—'
                                  : (ffiModel.direct == true
                                      ? 'Directa (P2P)'
                                      : 'Por relevo (servidor)'),
                              'Tipo de conexión'),
                          const Divider(height: 16),
                          ListTile(
                            leading: const Icon(Icons.high_quality_outlined,
                                color: Colors.white70),
                            title: Text('Calidad de imagen y pantalla',
                                style: erTextStyle(context,
                                    size: 14.5, color: Colors.white)),
                            subtitle: Text(
                                'Calidad, escala, códec, cursor y monitores',
                                style: erTextStyle(context,
                                    size: 12,
                                    color: Colors.white.withOpacity(0.6))),
                            onTap: () {
                              closePanel();
                              widget.actions.showOptions();
                            },
                          ),
                          if (versionCmp(pi.version, '1.2.0') >= 0)
                            SwitchListTile(
                              value: ffiModel.viewOnly,
                              onChanged: (v) async {
                                await bind.sessionToggleOption(
                                    sessionId: _ffi.sessionId,
                                    value: kOptionToggleViewOnly);
                                ffiModel.setViewOnly(widget.id, v);
                                setState(() {});
                              },
                              title: Text('Solo ver',
                                  style: erTextStyle(context,
                                      size: 14.5, color: Colors.white)),
                              subtitle: Text(
                                  'Prende para mirar sin controlar el equipo',
                                  style: erTextStyle(context,
                                      size: 12,
                                      color: Colors.white.withOpacity(0.6))),
                            ),
                          ListTile(
                            leading: const Icon(
                                Icons.chat_bubble_outline_rounded,
                                color: Colors.white70),
                            title: Text('Chat y llamada de voz',
                                style: erTextStyle(context,
                                    size: 14.5, color: Colors.white)),
                            onTap: () {
                              closePanel();
                              widget.actions.chat();
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.bolt_outlined,
                                color: Colors.white70),
                            title: Text('Más acciones',
                                style: erTextStyle(context,
                                    size: 14.5, color: Colors.white)),
                            subtitle: Text(
                                'Ctrl+Alt+Supr, bloquear, reiniciar, grabar…',
                                style: erTextStyle(context,
                                    size: 12,
                                    color: Colors.white.withOpacity(0.6))),
                            onTap: () {
                              closePanel();
                              widget.actions.showActions();
                            },
                          ),
                          if (ffiModel.isPeerAndroid && ffiModel.keyboard)
                            ListTile(
                              leading: const Icon(Icons.smartphone_rounded,
                                  color: Colors.white70),
                              title: Text('Botones de Android',
                                  style: erTextStyle(context,
                                      size: 14.5, color: Colors.white)),
                              subtitle: Text(
                                  'Mostrar u ocultar Atrás, Inicio y Recientes',
                                  style: erTextStyle(context,
                                      size: 12,
                                      color: Colors.white.withOpacity(0.6))),
                              onTap: () {
                                closePanel();
                                _ffi.dialogManager
                                    .toggleMobileActionsOverlay(ffi: _ffi);
                              },
                            ),
                          const Divider(height: 16),
                          row(
                              Icons.phone_android_rounded,
                              erVersion().isEmpty ? '—' : erVersion(),
                              'Versión de Electronics Remote'),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }
}

// ------------------------------------------------------- cómo controlar

void erOpenHowToControl(BuildContext context, {bool inSession = false}) {
  Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ErHowToControlPage(inSession: inSession)));
}

class ErHowToControlPage extends StatefulWidget {
  final bool inSession;
  const ErHowToControlPage({Key? key, this.inSession = false})
      : super(key: key);

  @override
  State<ErHowToControlPage> createState() => _ErHowToControlPageState();
}

class _ErHowToControlPageState extends State<ErHowToControlPage> {
  @override
  Widget build(BuildContext context) {
    final touch = widget.inSession && gFFI.ffiModel.touchMode;
    final rows = touch
        ? const [
            (Icons.pinch_outlined, 'Zoom', 'Junta o separa dos dedos.'),
            (
              Icons.touch_app_outlined,
              'Clic izquierdo',
              'Toca con un dedo donde quieres hacer clic.'
            ),
            (
              Icons.back_hand_outlined,
              'Clic derecho',
              'Mantén presionado un dedo.'
            ),
            (
              Icons.swipe_outlined,
              'Arrastrar',
              'Desliza un dedo para arrastrar con el botón izquierdo.'
            ),
            (
              Icons.unfold_more_rounded,
              'Desplazar',
              'Desliza tres dedos hacia arriba o hacia abajo.'
            ),
            (
              Icons.open_with_rounded,
              'Mover la vista',
              'Desliza dos dedos para mover la pantalla ampliada.'
            ),
          ]
        : const [
            (Icons.pinch_outlined, 'Zoom', 'Junta o separa dos dedos.'),
            (
              Icons.mouse_outlined,
              'Mover el mouse',
              'Desliza un dedo: el cursor se mueve con tu dedo (no salta a donde tocas), así siempre lo ves.'
            ),
            (
              Icons.touch_app_outlined,
              'Clic izquierdo',
              'Toca con un dedo: hace clic donde está el cursor, no donde tocas.'
            ),
            (
              Icons.ads_click_rounded,
              'Doble clic',
              'Toca dos veces con un dedo.'
            ),
            (
              Icons.back_hand_outlined,
              'Clic derecho',
              'Toca con dos dedos o mantén presionado un dedo.'
            ),
            (
              Icons.unfold_more_rounded,
              'Desplazar (rueda)',
              'Desliza dos dedos juntos hacia arriba o hacia abajo.'
            ),
            (
              Icons.open_with_rounded,
              'Mover la vista',
              'Con zoom, la vista sigue al cursor; también puedes separar un poco los dedos y moverlos.'
            ),
            (
              Icons.drag_indicator_rounded,
              'Arrastrar o seleccionar',
              'Toca dos veces, deja el dedo en la segunda y arrastra.'
            ),
          ];
    return erThemed(Builder(
      builder: (context) => Scaffold(
        backgroundColor: ErColors.night,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Cómo controlar'),
          bottom: erGradientLine(),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text('Usar Electronics Remote',
                style: erTitleStyle(context, size: 18, color: Colors.white)),
            const SizedBox(height: 6),
            Text(
                touch
                    ? 'Estás en modo táctil: tocas directo donde quieres hacer clic.'
                    : 'Tu dedo mueve el cursor en lugar de hacer clic donde tocas. '
                        'Así controlas con más precisión una pantalla grande de computadora.',
                style: erTextStyle(context,
                    size: 13.5, color: Colors.white.withOpacity(0.8))),
            const SizedBox(height: 14),
            Row(children: [
              SizedBox(
                  width: 44,
                  child: Text('Gesto',
                      style: erTextStyle(context,
                          size: 12, weight: FontWeight.w600))),
              SizedBox(
                  width: 110,
                  child: Text('Acción',
                      style: erTextStyle(context,
                          size: 12, weight: FontWeight.w600))),
              Expanded(
                  child: Text('Explicación',
                      style: erTextStyle(context,
                          size: 12, weight: FontWeight.w600))),
            ]),
            const Divider(),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                        width: 44,
                        child: Icon(r.$1, color: ErColors.cyan, size: 28)),
                    SizedBox(
                        width: 110,
                        child: Text(r.$2,
                            style: erTextStyle(context,
                                size: 13.5, color: Colors.white))),
                    Expanded(
                        child: Text(r.$3,
                            style: erTextStyle(context,
                                size: 13,
                                color: Colors.white.withOpacity(0.8)))),
                  ],
                ),
              ),
            const Divider(),
            Text('Notas',
                style: erTitleStyle(context, size: 16, color: Colors.white)),
            const SizedBox(height: 8),
            for (final n in const [
              'Toca el alfiler para fijar la barra de arriba. Sin fijar, se oculta a los 20 segundos; toca la pestañita de arriba para verla otra vez. Puedes arrastrarla a los lados.',
              'Toca el teclado para abrirlo junto con una fila de teclas especiales que se desliza de lado (Ctrl, Alt, Win, flechas, F1–F12, etc.). Un toque a Ctrl, Alt, ⇧ o ⊞ los deja presionados para la siguiente tecla; dos toques los dejan fijos hasta que los vuelvas a tocar.',
              'Toca el mouse para el modo mouse: botones izquierdo, central y derecho abajo, y una barra a la derecha para desplazar.',
              'Toca la i para ver la información de la conexión, la calidad de imagen, «Solo ver», el chat y más acciones.',
              'Lo que copias en el celular se pega en la computadora y al revés (si el equipo lo permite).',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ',
                        style: erTextStyle(context, color: ErColors.cyan)),
                    Expanded(
                        child: Text(n,
                            style: erTextStyle(context,
                                size: 13,
                                color: Colors.white.withOpacity(0.85)))),
                  ],
                ),
              ),
            if (widget.inSession) ...[
              const Divider(),
              Text('Opciones del mouse',
                  style: erTitleStyle(context, size: 16, color: Colors.white)),
              // Las opciones de RustDesk (modo mouse / táctil, mouse virtual).
              GestureHelp(
                touchMode: gFFI.ffiModel.touchMode,
                onTouchModeChange: (t) {
                  gFFI.ffiModel.toggleTouchMode();
                  final v = gFFI.ffiModel.touchMode ? 'Y' : 'N';
                  bind.mainSetLocalOption(key: kOptionTouchMode, value: v);
                  setState(() {});
                },
                virtualMouseMode: gFFI.ffiModel.virtualMouseMode,
                inputModel: gFFI.inputModel,
              ),
            ],
          ],
        ),
      ),
    ));
  }
}
