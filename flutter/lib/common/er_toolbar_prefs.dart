// Electronics Remote: estado de la barra de la sesión remota que se recuerda
// entre sesiones (para todas las PCs): fijada (pin), escondida, borde y
// posición a lo largo del borde. Vive en la opción local de Flutter
// «remoteMenubarState» (la misma donde RustDesk ya guardaba solo el pin).
//
// Este archivo no depende del bridge de Rust: recibe y regresa el texto JSON
// para poder probarlo con `flutter test`.

import 'dart:convert';

/// Tiempo sin el mouse encima antes de que la barra se esconda sola.
const Duration kErToolbarAutoHide = Duration(milliseconds: 3000);

/// Tiempo con el mouse sobre la pestañita antes de que se abra sola
/// (evita que se abra al pasar de largo hacia los menús de la PC remota).
const Duration kErToolbarHoverOpen = Duration(milliseconds: 350);

/// Medidas de la pestañita escondida (lado largo × lado corto).
const double kErToolbarTabLong = 48;
const double kErToolbarTabShort = 16;

/// Opacidad de la pestañita en reposo (con el mouse encima es 1).
const double kErToolbarTabOpacity = 0.55;

/// En Electronics Remote la barra siempre se puede llevar a cualquier borde.
bool erToolbarMultiEdge() => true;

const _kEdges = {'top', 'right', 'bottom', 'left'};

class ErToolbarPrefs {
  final bool? pin;
  final bool? collapsed;
  final String? edge;
  final double? fraction;

  const ErToolbarPrefs({this.pin, this.collapsed, this.edge, this.fraction});

  /// Lee el JSON guardado; cualquier valor raro se ignora (queda en null).
  static ErToolbarPrefs parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const ErToolbarPrefs();
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return const ErToolbarPrefs();
      final pin = m['pin'];
      final collapsed = m['collapsed'];
      final edge = m['edge'];
      final fraction = m['fraction'];
      double? f;
      if (fraction is num && fraction.isFinite) {
        f = fraction.toDouble().clamp(0.0, 1.0).toDouble();
      }
      return ErToolbarPrefs(
        pin: pin is bool ? pin : null,
        collapsed: collapsed is bool ? collapsed : null,
        edge: (edge is String && _kEdges.contains(edge)) ? edge : null,
        fraction: f,
      );
    } catch (_) {
      return const ErToolbarPrefs();
    }
  }

  /// Regresa el JSON con los campos dados cambiados y los demás intactos
  /// (incluidas llaves que no conocemos).
  static String merge(
    String? raw, {
    bool? pin,
    bool? collapsed,
    String? edge,
    double? fraction,
  }) {
    Map<String, dynamic> m = {};
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is Map) m = Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    if (pin != null) m['pin'] = pin;
    if (collapsed != null) m['collapsed'] = collapsed;
    if (edge != null && _kEdges.contains(edge)) m['edge'] = edge;
    if (fraction != null && fraction.isFinite) {
      m['fraction'] = fraction.clamp(0.0, 1.0).toDouble();
    }
    return jsonEncode(m);
  }
}
