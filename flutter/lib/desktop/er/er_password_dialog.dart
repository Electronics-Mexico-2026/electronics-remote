// Cuadro «Autenticación» al conectar (como RealVNC): ícono de PC + nombre del
// equipo, contraseña con ojo, «Recordar contraseña» y «¿Olvidó la
// contraseña?». La contraseña se guarda igual que en RustDesk (cifrada en la
// configuración de ese equipo) cuando la casilla está marcada.

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../common/widgets/dialog.dart';
import '../../models/platform_model.dart';
import 'er_theme.dart';

Future<void> erPasswordDialog(
  SessionID sessionId,
  OverlayDialogManager dialogManager,
  TextEditingController passwordController,
  bool rememberInit,
) async {
  final askRemember = erOptOn(kErOptAskRemember);
  // Regla del dueño: apagado de fábrica; la persona decide.
  var remember = askRemember && rememberInit;
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
      gFFI.login('', '', sessionId, password, remember);
      close();
      dialogManager.showLoading(translate('Logging in...'),
          onCancel: closeConnection);
    }

    final hint = Theme.of(context).hintColor;
    return CustomAlertDialog(
      title: Row(
        children: [
          erIsotipo(size: 20),
          const SizedBox(width: 8),
          Text('Autenticación', style: erTitleStyle(context, size: 16)),
        ],
      ),
      contentBoxConstraints: const BoxConstraints(maxWidth: 420, minWidth: 380),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.desktop_windows_outlined,
                  size: 34, color: ErColors.cyan),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Autentíquese en el equipo remoto',
                        style: erTextStyle(context,
                            size: 14, weight: FontWeight.w600)),
                    Text(alias.isEmpty ? 'Escribe su contraseña' : alias,
                        overflow: TextOverflow.ellipsis,
                        style: erTextStyle(context, size: 13, color: hint)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          PasswordWidget(
            controller: passwordController,
            title: 'Contraseña',
            hintText: 'Contraseña del equipo',
          ),
          Row(
            children: [
              if (askRemember)
                Expanded(
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text('Recordar contraseña',
                        style: erTextStyle(context)),
                    value: remember,
                    onChanged: (v) {
                      if (v != null) setState(() => remember = v);
                    },
                  ),
                )
              else
                const Spacer(),
              InkWell(
                onTap: () => showHelp.value = !showHelp.value,
                child: Text('¿Olvidó la contraseña?',
                    style:
                        erTextStyle(context, size: 12.5, color: ErColors.cyan)
                            .copyWith(decoration: TextDecoration.underline)),
              ),
            ],
          ),
          Obx(() => showHelp.value
              ? Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: ErColors.selected,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                      'La contraseña permanente la ve quien está en ese '
                      'equipo, en Electronics Remote › «Este equipo», o el '
                      'administrador en el panel $kErPanelUrl.',
                      style: erTextStyle(context, size: 12)),
                )
              : const SizedBox.shrink()),
        ],
      ),
      actions: [
        dialogButton('Cancelar', onPressed: cancel, isOutline: true),
        dialogButton('Aceptar', onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: cancel,
    );
  });
}
