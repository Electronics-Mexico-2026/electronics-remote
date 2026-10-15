// Electronics Remote para Android: tema oscuro de la marca para las pantallas
// con el acomodo de RealVNC Viewer. Reúsa colores y letras de escritorio
// (lib/desktop/er/er_theme.dart).

import 'package:flutter/material.dart';

import '../../common.dart';
import '../../desktop/er/er_theme.dart';

export '../../desktop/er/er_theme.dart';

/// Ancho a partir del cual se usa el acomodo de tableta (Fold abierto).
const double kErWideWidth = 600;

bool erIsWide(BuildContext context) =>
    MediaQuery.of(context).size.width >= kErWideWidth;

ThemeData erMobileTheme() {
  final base = MyTheme.darkTheme;
  return base.copyWith(
    scaffoldBackgroundColor: ErColors.night,
    canvasColor: ErColors.night,
    cardColor: ErColors.surface,
    dialogBackgroundColor: ErColors.surface,
    dividerColor: ErColors.line,
    hintColor: const Color(0xFF8B95A7),
    colorScheme: base.colorScheme.copyWith(
      primary: ErColors.blue,
      secondary: ErColors.cyan,
      surface: ErColors.surface,
      background: ErColors.night,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: ErColors.night,
      foregroundColor: Colors.white,
      elevation: 0,
      titleTextStyle: TextStyle(
          fontFamily: kErFontTitle,
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: Colors.white),
    ),
    drawerTheme: const DrawerThemeData(backgroundColor: ErColors.panel),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: ErColors.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: MaterialStateProperty.resolveWith(
          (s) => s.contains(MaterialState.selected) ? ErColors.cyan : null),
      trackColor: MaterialStateProperty.resolveWith((s) =>
          s.contains(MaterialState.selected)
              ? ErColors.blue.withOpacity(0.6)
              : null),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: ErColors.cyan,
      selectionHandleColor: ErColors.cyan,
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: ErColors.cyan, width: 2)),
      floatingLabelStyle: const TextStyle(color: ErColors.cyan),
    ),
    textTheme: base.textTheme.apply(
        fontFamily: kErFontText,
        bodyColor: Colors.white,
        displayColor: Colors.white),
  );
}

/// Envuelve un widget (diálogo, hoja, página) con el tema de la marca.
Widget erThemed(Widget child) => Theme(data: erMobileTheme(), child: child);

/// Línea de degradado bajo la barra de arriba (en lugar del azul de RealVNC).
PreferredSizeWidget erGradientLine() => PreferredSize(
      preferredSize: const Size.fromHeight(2),
      child: Container(
          height: 2,
          decoration: const BoxDecoration(gradient: ErColors.gradient)),
    );

/// «e» + «Electronics Remote» con el degradado.
Widget erBrandTitle(BuildContext context, {double size = 18}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        erIsotipo(size: size + 10),
        const SizedBox(width: 8),
        ShaderMask(
          shaderCallback: (r) => ErColors.gradient.createShader(r),
          child: Text('Electronics Remote',
              style: erTitleStyle(context,
                  size: size, weight: FontWeight.w700, color: Colors.white)),
        ),
      ],
    );
