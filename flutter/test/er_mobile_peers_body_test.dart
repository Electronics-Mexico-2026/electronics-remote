import 'package:flutter/material.dart';
import 'package:flutter_hbb/mobile/er/er_m_home.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_test/flutter_test.dart';

Peer _peer(String id) => Peer(
    id: id,
    hash: '',
    password: '',
    username: '',
    hostname: 'equipo-$id',
    platform: 'Windows',
    alias: '',
    tags: [],
    forceAlwaysRelay: false,
    rdpPort: '',
    rdpUsername: '',
    loginName: '',
    device_group_name: '',
    note: '');

void main() {
  for (final size in [const Size(840, 760), const Size(400, 800)]) {
    testWidgets('la lista se ve y se actualiza al jalar a $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var refreshed = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Electronics')),
          floatingActionButton: FloatingActionButton(
              onPressed: () {}, child: const Icon(Icons.add)),
          body: erShellBody(
            Column(children: [
              const SizedBox(height: 40, child: Text('Actualizado 18:00')),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => refreshed++,
                  child: erMobilePeerGrid([_peer('431400798')],
                      (p) => Text(p.hostname)),
                ),
              ),
            ]),
            BottomNavigationBar(items: const [
              BottomNavigationBarItem(icon: Icon(Icons.add), label: 'a'),
              BottomNavigationBarItem(icon: Icon(Icons.abc), label: 'b'),
            ]),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final bar = find.text('Actualizado 18:00');
      final card = find.text('equipo-431400798');
      expect(bar, findsOneWidget);
      expect(card, findsOneWidget);
      expect(tester.getSize(bar).height, greaterThan(0));
      expect(tester.getRect(card).bottom, lessThan(size.height));
      expect(tester.getRect(card).height, greaterThan(0));

      await tester.fling(card, const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(refreshed, 1);
    });
  }
}
