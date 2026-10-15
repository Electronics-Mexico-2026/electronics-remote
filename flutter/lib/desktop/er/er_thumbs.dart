// Miniaturas de la última pantalla vista de cada equipo (como RealVNC).
// La ventana de sesión guarda un PNG chico cada minuto y al cerrar; la
// ventana principal lo muestra en el cuadro del equipo.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/model.dart';
import 'er_theme.dart';

class ErThumbs {
  static String? _dir;
  static final Map<String, (DateTime, Uint8List)> _cache = {};

  static Future<String> dir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}er_thumbs');
    if (!d.existsSync()) {
      d.createSync(recursive: true);
    }
    _dir = d.path;
    return _dir!;
  }

  static String _safe(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');

  static Future<File> file(String id) async =>
      File('${await dir()}${Platform.pathSeparator}${_safe(id)}.png');

  /// Reduce la imagen actual a 320 px de ancho y la guarda.
  static Future<void> save(String id, ui.Image? image) async {
    if (image == null || id.isEmpty) return;
    if (erOptYes(kErOptHideThumbs)) return;
    try {
      if (image.width <= 0 || image.height <= 0) return;
      const targetW = 320.0;
      final scale = targetW / image.width;
      final h = (image.height * scale).clamp(1.0, 480.0);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(scale);
      canvas.drawImage(
          image, Offset.zero, Paint()..filterQuality = FilterQuality.medium);
      final picture = recorder.endRecording();
      final small = await picture.toImage(targetW.round(), h.round());
      picture.dispose();
      final data = await small.toByteData(format: ui.ImageByteFormat.png);
      small.dispose();
      if (data == null) return;
      final f = await file(id);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsBytes(data.buffer.asUint8List(), flush: true);
      if (f.existsSync()) {
        await f.delete();
      }
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('er thumbs: no se pudo guardar $id: $e');
    }
  }

  /// Arranca el guardado periódico para una sesión remota. [boundary] es
  /// el RepaintBoundary que envuelve la pantalla remota: con el render por
  /// textura (el normal en Windows 10/11) no hay ui.Image en Dart y se toma
  /// la foto del widget.
  static Timer startCapture(FFI ffi, String id, GlobalKey boundary) {
    Future.delayed(const Duration(seconds: 6), () {
      capture(ffi, id, boundary);
    });
    return Timer.periodic(const Duration(seconds: 20), (_) {
      capture(ffi, id, boundary);
    });
  }

  /// Última captura al cerrar la sesión (si todavía hay imagen).
  static void stopCapture(Timer? timer, FFI ffi, String id) {
    timer?.cancel();
    final img = ffi.imageModel.image;
    if (img != null) save(id, img);
  }

  static Future<void> capture(FFI ffi, String id, GlobalKey boundary) async {
    if (erOptYes(kErOptHideThumbs)) return;
    final img = ffi.imageModel.image;
    if (img != null) {
      await save(id, img);
      return;
    }
    try {
      final ro = boundary.currentContext?.findRenderObject();
      if (ro is! RenderRepaintBoundary || !ro.hasSize) return;
      if (ro.size.width < 50 || ro.size.height < 50) return;
      final small = await ro.toImage(pixelRatio: 320 / ro.size.width);
      if (await _looksBlank(small)) {
        small.dispose();
        return;
      }
      await save(id, small);
      small.dispose();
    } catch (e) {
      debugPrint('er thumbs: captura fallida $id: $e');
    }
  }

  /// Una foto toda negra o transparente no sirve de miniatura.
  static Future<bool> _looksBlank(ui.Image img) async {
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return true;
    final len = data.lengthInBytes ~/ 4;
    if (len == 0) return true;
    final step = (len ~/ 400).clamp(1, len);
    int? first;
    for (var i = 0; i < len; i += step) {
      final px = data.getUint32(i * 4);
      final a = px & 0xFF;
      if (a == 0) continue;
      final rgb = px >> 8;
      first ??= rgb;
      if (rgb != first) return false;
    }
    return true;
  }

  /// Lee la miniatura; si el archivo no cambió devuelve los mismos bytes
  /// (misma instancia) para no redibujar.
  static Future<Uint8List?> load(String id) async {
    try {
      final f = await file(id);
      if (!f.existsSync()) {
        _cache.remove(id);
        return null;
      }
      final mtime = f.lastModifiedSync();
      final hit = _cache[id];
      if (hit != null && hit.$1 == mtime) return hit.$2;
      final bytes = await f.readAsBytes();
      _cache[id] = (mtime, bytes);
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static Future<void> delete(String id) async {
    try {
      final f = await file(id);
      if (f.existsSync()) await f.delete();
    } catch (_) {}
    ErState.thumbsVersion.value++;
  }

  static Future<void> deleteAll() async {
    try {
      final d = Directory(await dir());
      for (final e in d.listSync()) {
        if (e is File) await e.delete();
      }
    } catch (_) {}
    ErState.thumbsVersion.value++;
  }
}

/// Miniatura del equipo; si no hay, el ícono de la plataforma.
class ErPeerThumb extends StatefulWidget {
  final String id;
  final Widget fallback;
  const ErPeerThumb({Key? key, required this.id, required this.fallback})
      : super(key: key);

  @override
  State<ErPeerThumb> createState() => _ErPeerThumbState();
}

class _ErPeerThumbState extends State<ErPeerThumb> {
  Uint8List? _bytes;
  Worker? _worker;

  @override
  void initState() {
    super.initState();
    _load();
    _worker = ever(ErState.thumbsVersion, (_) => _load());
  }

  @override
  void didUpdateWidget(covariant ErPeerThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) _load();
  }

  @override
  void dispose() {
    _worker?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final b = await ErThumbs.load(widget.id);
    if (!mounted) return;
    if (!identical(b, _bytes)) setState(() => _bytes = b);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final bytes = _bytes;
      if (ErState.hideThumbs.value || bytes == null) return widget.fallback;
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => widget.fallback,
      );
    });
  }
}
