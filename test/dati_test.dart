// Prove dello strato dati su un database vero (sqflite ffi): schema e migrazioni della versione Kotlin,
// JSON identico a org.json di Android, file clienti/preventivi, listino Excel/CSV, numerazione, PDF.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tkclienti/dati/archivio.dart';
import 'package:tkclienti/dati/backup.dart';
import 'package:tkclienti/dati/database.dart';
import 'package:tkclienti/dati/formati.dart';
import 'package:tkclienti/dati/impostazioni.dart';
import 'package:tkclienti/dati/json_android.dart';
import 'package:tkclienti/dati/listino.dart';
import 'package:tkclienti/dati/modelli.dart';
import 'package:tkclienti/dati/pdf_preventivo.dart';

var _n = 0;

Future<Archivio> nuovo() async {
  final f = '${Directory.systemTemp.path}/tkclienti_prova_${DateTime.now().microsecondsSinceEpoch}_${_n++}.db';
  final db = await apriDatabase(percorso: f, fabbrica: databaseFactoryFfiNoIsolate);
  final a = Archivio(db);
  await a.ricarica();
  return a;
}

Cliente mario() => Cliente(
      nome: 'Mario',
      cognome: 'Rossi',
      telefono: '333 1234567',
      email: 'mario@rossi.it',
      piva: '01234567890',
      indirizzo: 'Via Roma 1',
      cap: '80100',
      citta: 'Napoli',
      provincia: 'NA',
      createdAt: 1700000000000,
      updatedAt: 1700000000000,
    );

void main() {
  sqfliteFfiInit();

  test('JSON come org.json di Android', () {
    expect(numeroJson(22.0), '22');
    expect(numeroJson(-1.0), '-1');
    expect(numeroJson(12.5), '12.5');
    expect(numeroJson(0.1 + 0.2), '0.30000000000000004');
    expect(numeroJson(12345678.5), '1.23456785E7');
    expect(numeroJson(0.0001), '1.0E-4');
    expect(numeroJson(1700000000000), '1700000000000');
    expect(doubleJava(10.0), '10.0');
    expect(doubleJava(1e7), '1.0E7');
    final s = jsonAndroid({
      'a': 1,
      'b': 'x/y "z"\n',
      'c': null,
      'd': [],
      'e': [
        {'f': 2.0}
      ],
      'g': {},
    });
    expect(
        s,
        '{\n'
        '  "a": 1,\n'
        '  "b": "x\\/y \\"z\\"\\n",\n'
        '  "c": null,\n'
        '  "d": [],\n'
        '  "e": [\n'
        '    {\n'
        '      "f": 2\n'
        '    }\n'
        '  ],\n'
        '  "g": {}\n'
        '}');
    expect(jsonAndroid({'u': 'à€\u0001'}), '{\n  "u": "à€\\u0001"\n}');
  });

  test('file dei clienti: formato, impronta e ritorno', () async {
    final it = Intestazione(ragioneSociale: 'TecnikGeek', iban: 'IT00X', sito: 'https://pietrodefilippis.it');
    final c = mario()
      ..id = 7
      ..commissionePerc = 5.5;
    final cont = serializzaClienti([c], it);
    final testo = utf8.decode(cont.byte);
    expect(testo, startsWith('{\n  "version": 1,\n  "tipo": "clienti",\n  "intestazione": {\n    "ragioneSociale": "TecnikGeek",'));
    expect(testo, contains('"sito": "https:\\/\\/pietrodefilippis.it"'));
    expect(testo, contains('      "id": 7,\n      "nome": "Mario",'));
    expect(testo, contains('"commissionePerc": 5.5,'));
    expect(cont.hash, sha256.convert(cont.byte).toString());
    final letto = leggiFileClienti(cont.byte);
    expect(letto.clienti.single.nominativo, 'Mario Rossi');
    expect(letto.clienti.single.commissionePerc, 5.5);
    expect(letto.intestazione!.iban, 'IT00X');
    // stesso contenuto → stessa impronta (niente riscritture inutili)
    expect(serializzaClienti(letto.clienti, letto.intestazione!).hash, cont.hash);
    expect(() => leggiFilePreventivi(cont.byte), throwsA(isA<String>()));
  });

  test('database: creazione, clienti, preventivi numerati, blocchi', () async {
    final a = await nuovo();
    final idC = await a.salvaCliente(mario());
    expect(a.clienti.single.id, idC);
    final anno = DateTime.now().year;
    final righe = [
      RigaPreventivo(codice: 'A1', descrizione: 'Caldaia', quantita: 2, prezzoUnitario: 100, scontoPercentuale: 10),
      RigaPreventivo(descrizione: 'Montaggio', quantita: 1, prezzoUnitario: 50),
    ];
    final (imp, iva, tot) = calcolaTotali(righe, 22, 0);
    expect(imp, 230);
    expect(iva, closeTo(50.6, 1e-9));
    expect(tot, closeTo(280.6, 1e-9));
    final p1 = await a.salvaPreventivo(Preventivo(clienteId: idC, totale: tot), righe);
    final p2 = await a.salvaPreventivo(Preventivo(clienteId: idC), [righe.first]);
    final pcr = await a.preventivoConRighe(p1);
    expect(pcr!.preventivo.numero, '$anno-001');
    expect(pcr.righe.map((r) => r.ordine), [0, 1]);
    expect((await a.preventivoConRighe(p2))!.preventivo.numero, '$anno-002');
    // un buco nella numerazione non fa ripetere un numero
    await a.eliminaPreventivo(pcr.preventivo);
    final p3 = await a.salvaPreventivo(Preventivo(clienteId: idC), [righe.first]);
    expect((await a.preventivoConRighe(p3))!.preventivo.numero, '$anno-003');
    // il cliente con preventivi non si elimina
    expect(await a.eliminaCliente(a.cliente(idC)!), isFalse);
    expect(a.clienti, hasLength(1));
  });

  test('file dei preventivi: sostituzione e controlli', () async {
    final a = await nuovo();
    final idC = await a.salvaCliente(mario());
    final idArt = await a.salvaArticolo(Articolo(codice: 'X1', descrizione: 'Pezzo', giacenza: 5));
    await a.movimentaGiacenza((await a.articolo(idArt!))!, -2, 'SCARICO', 'vendita');
    await a.salvaPreventivo(Preventivo(clienteId: idC, totale: 10), [RigaPreventivo(descrizione: 'x', prezzoUnitario: 10)]);
    final cont = serializzaPreventivi(await a.tuttiPreventivi(), await a.tutteRighe(), await a.tuttiMovimenti());
    expect(cont.conteggi, {'preventivi': 1, 'righe': 1, 'movimenti': 1});
    final f = leggiFilePreventivi(cont.byte);
    expect(await a.sostituisciPreventivi(f.preventivi, f.righe, f.movimenti), 0);
    expect(
        serializzaPreventivi(await a.tuttiPreventivi(), await a.tutteRighe(), await a.tuttiMovimenti()).hash, cont.hash);
    // preventivi di un cliente che qui non c'è: non si tocca niente
    final altro = Preventivo(id: 99, numero: '2020-001', clienteId: 4242);
    expect(() => a.sostituisciPreventivi([altro], const [], const []), throwsA(isA<String>()));
    expect(a.preventivi, hasLength(1));
    // clienti dal file: chi ha preventivi resta anche se il file non lo ha
    final tenuti = await a.sostituisciClienti([Cliente(id: 50, nome: 'Nuovo')]);
    expect(tenuti, 1);
    expect(a.clienti.map((c) => c.id).toSet(), {idC, 50});
  });

  test('migrazioni della versione Kotlin (schema 1 → 3)', () async {
    final f = '${Directory.systemTemp.path}/tkclienti_migra_${DateTime.now().microsecondsSinceEpoch}.db';
    final vecchio = await databaseFactoryFfiNoIsolate.openDatabase(f,
        options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, _) async {
              await db.execute('CREATE TABLE clienti (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, nome TEXT NOT NULL, '
                  'cognome TEXT NOT NULL, telefono TEXT NOT NULL, email TEXT NOT NULL, piva TEXT NOT NULL, '
                  'codiceFiscale TEXT NOT NULL, codiceSdi TEXT NOT NULL, pec TEXT NOT NULL, indirizzo TEXT NOT NULL, '
                  'cap TEXT NOT NULL, citta TEXT NOT NULL, provincia TEXT NOT NULL, note TEXT NOT NULL, tag TEXT NOT NULL, '
                  'createdAt INTEGER NOT NULL, updatedAt INTEGER NOT NULL)');
              await db.execute('CREATE TABLE articoli (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, codice TEXT NOT NULL, '
                  'descrizione TEXT NOT NULL, prezzoListino REAL NOT NULL, prezzoRivenditore REAL NOT NULL, pagina INTEGER, '
                  'ean13 TEXT NOT NULL, giacenza REAL NOT NULL, unitaMisura TEXT NOT NULL, categoria TEXT NOT NULL, '
                  'note TEXT NOT NULL, createdAt INTEGER NOT NULL, updatedAt INTEGER NOT NULL)');
              await db.execute('CREATE TABLE preventivi (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, numero TEXT NOT NULL, '
                  'clienteId INTEGER NOT NULL, data INTEGER NOT NULL, validita INTEGER NOT NULL, ivaPercentuale REAL NOT NULL, '
                  'scontoGlobale REAL NOT NULL, totaleImponibile REAL NOT NULL, totaleIva REAL NOT NULL, totale REAL NOT NULL, '
                  'note TEXT NOT NULL, stato TEXT NOT NULL, createdAt INTEGER NOT NULL, updatedAt INTEGER NOT NULL)');
              await db.execute('CREATE TABLE righe_preventivo (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
                  'preventivoId INTEGER NOT NULL, ordine INTEGER NOT NULL, codice TEXT NOT NULL, descrizione TEXT NOT NULL, '
                  'quantita REAL NOT NULL, unitaMisura TEXT NOT NULL, prezzoUnitario REAL NOT NULL, '
                  'scontoPercentuale REAL NOT NULL, articoloId INTEGER)');
              await db.execute('CREATE TABLE movimenti_magazzino (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
                  'articoloId INTEGER NOT NULL, tipo TEXT NOT NULL, quantita REAL NOT NULL, giacenzaPrecedente REAL NOT NULL, '
                  'giacenzaNuova REAL NOT NULL, causale TEXT NOT NULL, riferimento TEXT NOT NULL, data INTEGER NOT NULL)');
              await db.insert('clienti', {
                'nome': 'Anna', 'cognome': 'Verdi', 'telefono': '', 'email': '', 'piva': '', 'codiceFiscale': '',
                'codiceSdi': '', 'pec': '', 'indirizzo': '', 'cap': '', 'citta': '', 'provincia': '', 'note': '', 'tag': '',
                'createdAt': 1, 'updatedAt': 1,
              });
              await db.insert('articoli', {
                'codice': 'L1', 'descrizione': 'Dal listino', 'prezzoListino': 9.9, 'prezzoRivenditore': 0, 'ean13': '',
                'giacenza': 0, 'unitaMisura': 'PZ', 'categoria': '', 'note': '', 'createdAt': 1, 'updatedAt': 1,
              });
            }));
    await vecchio.close();
    final db = await apriDatabase(percorso: f, fabbrica: databaseFactoryFfiNoIsolate);
    final a = Archivio(db);
    await a.ricarica();
    expect(a.clienti.single.commissionePerc, -1);
    expect((await a.articoloPerCodice('L1'))!.origine, origineListino);
    await db.close();
    File(f).deleteSync();
  });

  test('listino: CSV, Excel, articoli a mano protetti, impronta', () async {
    final a = await nuovo();
    await a.salvaArticolo(Articolo(codice: 'MAN', descrizione: 'Aggiunto a mano', prezzoListino: 1));
    final csv = utf8.encode('\uFEFFcodice;descrizione;prezzo_listino;prezzo_rivenditore;ean13;pagina;giacenza\n'
        'A1;"Valvola; ottone";12,50;10;800123;4;3\n'
        'MAN;Dal file;99;;;;\n'
        ';senza codice;1;;;;\n'
        'B2;Tubo 1/2 pollice;1.250,00;;;;\n');
    final l = leggiListino(Uint8List.fromList(csv), 'listino.csv', await a.articoliPerCodice());
    expect(l.totali, 4);
    expect(l.errori, hasLength(1));
    expect(l.codiciVisti, {'A1', 'MAN', 'B2'});
    expect(l.articoli.map((x) => x.codice), ['A1', 'B2']); // MAN è manuale: non si tocca
    await a.scriviListino(l.articoli);
    final a1 = (await a.articoloPerCodice('A1'))!;
    expect(a1.descrizione, 'Valvola; ottone');
    expect(a1.prezzoListino, 12.5);
    expect(a1.prezzoRivenditore, 10);
    expect(a1.pagina, 4);
    expect((await a.articoloPerCodice('B2'))!.prezzoListino, 1250);
    expect((await a.articoloPerCodice('MAN'))!.descrizione, 'Aggiunto a mano');

    // Excel scritto dall'app → riletto uguale (anche i manuali, che restano manuali)
    final tutti = await a.tuttiArticoli();
    final xlsx = Uint8List.fromList(scriviXlsx(tutti));
    final r = leggiXlsx(xlsx, {});
    expect(r.errori, isEmpty);
    expect(r.codiciVisti, {'A1', 'B2', 'MAN'});
    final rA1 = r.articoli.firstWhere((x) => x.codice == 'A1');
    expect(rA1.prezzoListino, 12.5);
    expect(rA1.pagina, 4);
    expect(rA1.ean13, '800123');

    // il file non ha più B2: si toglie solo lui (A1 c'è, MAN è manuale)
    expect(await a.togliListinoAssenti({'A1'}), 1);
    expect(a.nArticoli, 2);

    // impronta come la versione Kotlin
    final h = hashArticoli([Articolo(codice: 'A', descrizione: 'd', prezzoListino: 12.5, prezzoRivenditore: 10, giacenza: 3)]);
    expect(h, sha256.convert(utf8.encode('A|d|12.5|10.0|||3.0|manuale\n')).toString());
  });

  test('impostazioni della versione Kotlin (DataStore)', () {
    List<int> varint(int v) {
      final out = <int>[];
      var x = v;
      while (true) {
        if (x < 0x80) {
          out.add(x);
          return out;
        }
        out.add((x & 0x7f) | 0x80);
        x >>= 7;
      }
    }

    List<int> lungo(int campo, List<int> dati) => [...varint(campo << 3 | 2), ...varint(dati.length), ...dati];
    List<int> voce(String k, List<int> valore) => lungo(1, [...lungo(1, utf8.encode(k)), ...lungo(2, valore)]);
    final dbl = ByteData(8)..setFloat64(0, 7.5, Endian.little);
    final file = Uint8List.fromList([
      ...voce('uri', lungo(5, utf8.encode('content://x/listino.xlsx'))),
      ...voce('ultimo_import', [...varint(4 << 3), ...varint(1760000000000)]),
      ...voce('abilitato', [...varint(1 << 3), 0]),
      ...voce('percentuale_default', [...varint(7 << 3 | 1), ...dbl.buffer.asUint8List()]),
    ]);
    final m = leggiDataStore(file);
    expect(m['uri'], 'content://x/listino.xlsx');
    expect(m['ultimo_import'], 1760000000000);
    expect(m['abilitato'], false);
    expect(m['percentuale_default'], 7.5);
  });

  test('formati italiani', () {
    expect(euro(1234.5), '1.234,50 €');
    expect(euro(-3), '-3,00 €');
    expect(percentuale(5), '5');
    expect(percentuale(5.25), '5,25');
    expect(leggiNumero('1.234,56'), 1234.56);
    expect(leggiNumero('12.5'), 12.5);
    expect(leggiNumero('1.500'), 1500);
    expect(leggiNumero('22 %'), 22);
    expect(perCampo(3), '3');
    expect(perCampo(2.5), '2,5');
  });

  test('PDF del preventivo (più pagine)', () async {
    final dir = '${Platform.environment['FLUTTER_ROOT'] ?? r'C:\dev\flutter'}/bin/cache/artifacts/material_fonts';
    ByteData font(String n) {
      final f = File('assets/font/$n');
      final b = f.existsSync() ? f.readAsBytesSync() : File('$dir/${n.toLowerCase()}').readAsBytesSync();
      return ByteData.view(Uint8List.fromList(b).buffer);
    }

    final p = Preventivo(numero: '2026-007', validita: 30, ivaPercentuale: 22, totale: 1234.56, scontoGlobale: 5,
        note: 'Consegna in 10 giorni.\nPagamento a 30 giorni.');
    final righe = [
      for (var i = 0; i < 40; i++)
        RigaPreventivo(codice: 'C$i', descrizione: 'Articolo numero $i con una descrizione abbastanza lunga da andare a capo',
            quantita: 2, prezzoUnitario: 15.5, scontoPercentuale: i.isEven ? 10 : 0)
    ];
    final pdf = await creaPdfPreventivo(p, mario(), righe,
        Intestazione(ragioneSociale: 'Ditta Esempio', iban: 'IT60X0542811101000000123456', noteFooter: 'Grazie'),
        fontNormale: font('Roboto-Regular.ttf'), fontGrassetto: font('Roboto-Bold.ttf'));
    expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
    expect(RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(pdf)).length, greaterThan(1));
    expect(nomeFilePdf(p, mario()), 'Preventivo_2026-007_Rossi.pdf');
    Directory('build/anteprime').createSync(recursive: true);
    File('build/anteprime/preventivo.pdf').writeAsBytesSync(pdf);
  });

  test('file collegato: configurazione salvata e riletta', () {
    final c = ConfigFile(uri: 'content://a', nome: 'clienti.json', abilitato: true, ultimo: 5, hash: 'abc');
    final r = ConfigFile.daJson(jsonDecode(jsonEncode(c.perJson())) as Map<String, Object?>);
    expect(r.uri, 'content://a');
    expect(r.abilitato, isTrue);
    expect(r.hash, 'abc');
    expect(r.collegato, isTrue);
  });
}
