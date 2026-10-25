// Anteprime delle schermate (caratteri veri) in build/anteprime/, per controllarle senza telefono.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tkclienti/app.dart';
import 'package:tkclienti/dati/archivio.dart';
import 'package:tkclienti/dati/database.dart';
import 'package:tkclienti/dati/file_collegati.dart';
import 'package:tkclienti/dati/impostazioni.dart';
import 'package:tkclienti/dati/modelli.dart';
import 'package:tkclienti/dati/sincronia.dart';
import 'package:tkclienti/schermate/andamento.dart';
import 'package:tkclienti/schermate/articoli.dart';
import 'package:tkclienti/schermate/clienti.dart';
import 'package:tkclienti/schermate/home.dart';
import 'package:tkclienti/schermate/impostazioni.dart';
import 'package:tkclienti/schermate/preventivi.dart';
import 'package:tkclienti/schermate/preventivo_modulo.dart';
import 'package:tkclienti/tema.dart';

import 'caratteri.dart';

Future<void> _scatta(WidgetTester t, Widget w, String nome, {double alto = 1700}) async {
  t.view.physicalSize = Size(412 * 2, alto);
  t.view.devicePixelRatio = 2;
  final k = GlobalKey();
  await t.pumpWidget(RepaintBoundary(
    key: k,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: temaKit().copyWith(
          textTheme: temaKit().textTheme.apply(fontFamily: 'Roboto'),
          primaryTextTheme: temaKit().primaryTextTheme.apply(fontFamily: 'Roboto')),
      locale: const Locale('it'),
      supportedLocales: const [Locale('it')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: DefaultTextStyle.merge(style: const TextStyle(fontFamily: 'Roboto'), child: w),
    ),
  ));
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await t.pump(const Duration(seconds: 1));
  await t.runAsync(() async {
    final img = await (k.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio: 1);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/anteprime').createSync(recursive: true);
    File('build/anteprime/$nome.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 2));
}

void main() {
  sqfliteFfiInit();

  testWidgets('anteprime', (t) async {
    configTk = configClienti;
    provaCollegabili = true;
    late int idCliente, idPrev;
    await t.runAsync(() async {
      await caricaCaratteri();
      SharedPreferences.setMockInitialValues({'cifre_nascoste': false});
      impostazioni = await Impostazioni.carica();
      await impostazioni.salvaCommissione(const ConfigCommissione(percentualeDefault: 5));
      await impostazioni.salvaFile(
          Dominio.listino,
          ConfigFile(uri: 'content://prova', nome: 'listino-2026.xlsx', abilitato: true, ultimo: DateTime.now().millisecondsSinceEpoch));
      final f = '${Directory.systemTemp.path}/tkclienti_anteprima_${DateTime.now().microsecondsSinceEpoch}.db';
      archivio = Archivio(await apriDatabase(percorso: f, fabbrica: databaseFactoryFfiNoIsolate));
      await archivio.ricarica();
      sincronia = Sincronia(archivio, impostazioni);
      idCliente = await archivio.salvaCliente(Cliente(
          nome: 'Mario', cognome: 'Rossi', telefono: '333 1234567', email: 'mario@rossi.it', citta: 'Napoli',
          provincia: 'NA', indirizzo: 'Via Roma 1', cap: '80100', piva: '01234567890', tag: 'AZIENDA'));
      await archivio.salvaCliente(Cliente(nome: 'Anna', cognome: 'Bianchi', telefono: '347 7654321', citta: 'Salerno'));
      await archivio.salvaCliente(Cliente(cognome: 'Idraulica Esposito srl', email: 'info@esposito.it', commissionePerc: 8));
      await archivio.salvaArticolo(Articolo(
          codice: 'VAL-12', descrizione: 'Valvola a sfera ottone 1/2"', prezzoListino: 12.5, giacenza: 14, origine: 'listino'));
      await archivio.salvaArticolo(Articolo(codice: 'CALD-24', descrizione: 'Caldaia a condensazione 24 kW', prezzoListino: 1290));
      final ora = DateTime.now();
      idPrev = await archivio.salvaPreventivo(
          Preventivo(clienteId: idCliente, totaleImponibile: 1340, totaleIva: 294.8, totale: 1634.8, commissionePerc: 5,
              note: 'Consegna entro 10 giorni lavorativi.'),
          [
            RigaPreventivo(codice: 'CALD-24', descrizione: 'Caldaia a condensazione 24 kW', prezzoUnitario: 1290),
            RigaPreventivo(descrizione: 'Montaggio e collaudo', prezzoUnitario: 50),
          ]);
      for (var m = 1; m <= 6; m++) {
        await archivio.salvaPreventivo(
            Preventivo(clienteId: idCliente, data: DateTime(ora.year, m, 10).millisecondsSinceEpoch, totaleImponibile: 300.0 * m, totale: 366.0 * m),
            [RigaPreventivo(descrizione: 'Manutenzione', prezzoUnitario: 300.0 * m)]);
      }
    });

    await _scatta(t, const SchermataHome(), 'home');
    await _scatta(t, const SchermataClienti(), 'clienti');
    await _scatta(t, SchermataCliente(idCliente), 'cliente');
    await _scatta(t, const SchermataModificaCliente(), 'cliente-modulo');
    await _scatta(t, const SchermataArticoli(), 'articoli');
    await _scatta(t, const SchermataArticolo(), 'articolo');
    await _scatta(t, SchermataPreventivo(idPrev), 'preventivo', alto: 2300);
    await _scatta(t, SchermataModuloPreventivo(preventivoId: idPrev), 'preventivo-modulo', alto: 2400);
    await _scatta(t, const SchermataPreventivi(), 'preventivi');
    await _scatta(t, const SchermataAndamento(), 'andamento', alto: 1900);
    await _scatta(t, const SchermataImpostazioni(), 'impostazioni', alto: 3600);
  });
}
