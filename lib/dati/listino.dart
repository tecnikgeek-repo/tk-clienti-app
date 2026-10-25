// Listino prodotti da file Excel (.xlsx) o CSV, e riscrittura del file Excel con anche gli articoli
// aggiunti a mano. Stesse regole della versione Kotlin (XlsxImporter, CsvImporter, XlsxWriter, XlsxAutoSync).
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

import 'formati.dart';
import 'json_android.dart';
import 'modelli.dart';

class LetturaListino {
  LetturaListino(this.articoli, this.codiciVisti, this.totali, this.errori);

  /// Articoli da scrivere (id > 0 = aggiorna quello che c'è); quelli «manuali» sono già esclusi.
  final List<Articolo> articoli;

  /// Tutti i codici presenti nel file (servono a togliere quelli spariti).
  final Set<String> codiciVisti;
  final int totali;
  final List<String> errori;
}

/// Legge il file del listino in base all'estensione. [esistenti] = articoli attuali per codice.
LetturaListino leggiListino(Uint8List dati, String nomeFile, Map<String, Articolo> esistenti) {
  final nome = nomeFile.toLowerCase();
  if (nome.endsWith('.xlsx')) return leggiXlsx(dati, esistenti);
  if (nome.endsWith('.csv')) return leggiCsv(dati, esistenti);
  return LetturaListino(const [], const {}, 0, ['Estensione non riconosciuta (serve .xlsx o .csv)']);
}

double _numero(String s, double predefinito) {
  if (s.trim().isEmpty) return predefinito;
  final t = s.trim().replaceAll('€', '').replaceAll(' ', '');
  // nel foglio Excel i numeri sono già col punto («12.5», «1.2E-3»); a mano possono avere la virgola
  return double.tryParse(t) ?? (RegExp(r'\d').hasMatch(t) ? leggiNumero(t) : predefinito);
}

Articolo _componi({
  required String codice,
  required Articolo? e,
  required String descrizione,
  required double listino,
  required double rivenditore,
  required String ean,
  required int? pagina,
  required double giacenza,
}) =>
    Articolo(
      id: e?.id ?? 0,
      codice: codice,
      descrizione: descrizione,
      prezzoListino: listino,
      prezzoRivenditore: rivenditore,
      ean13: ean,
      pagina: pagina,
      giacenza: giacenza,
      unitaMisura: e?.unitaMisura ?? 'PZ',
      categoria: e?.categoria ?? '',
      note: e?.note ?? '',
      origine: origineListino,
      createdAt: e?.createdAt ?? adesso(),
      updatedAt: adesso(),
    );

// ───────────────────────── Excel ─────────────────────────

/// «A1» → 0, «B7» → 1, «AA3» → 26
int _colonna(String? rif) {
  if (rif == null || rif.isEmpty) return -1;
  var n = 0;
  for (final c in rif.codeUnits) {
    if (c >= 65 && c <= 90) {
      n = n * 26 + (c - 64);
    } else {
      break;
    }
  }
  return n - 1;
}

LetturaListino leggiXlsx(Uint8List dati, Map<String, Articolo> esistenti) {
  final List<List<String>> righe;
  try {
    final zip = ZipDecoder().decodeBytes(dati);
    String? testo(String nome) {
      final f = zip.findFile(nome);
      return f == null ? null : utf8.decode(f.content, allowMalformed: true);
    }

    final condivise = <String>[];
    final ss = testo('xl/sharedStrings.xml');
    if (ss != null) {
      for (final si in XmlDocument.parse(ss).findAllElements('si')) {
        condivise.add(si.findAllElements('t').map((t) => t.innerText).join());
      }
    }
    final foglio = testo('xl/worksheets/sheet1.xml');
    if (foglio == null) {
      return LetturaListino(const [], const {}, 0, ['File XLSX non valido: foglio principale non trovato']);
    }
    righe = [];
    for (final row in XmlDocument.parse(foglio).findAllElements('row')) {
      final riga = <String>[];
      for (final c in row.findElements('c')) {
        final tipo = c.getAttribute('t');
        String valore;
        if (tipo == 'inlineStr') {
          valore = c.findAllElements('t').map((t) => t.innerText).join();
        } else {
          final v = c.getElement('v')?.innerText ?? '';
          valore = switch (tipo) {
            's' => () {
                final i = int.tryParse(v);
                return i != null && i >= 0 && i < condivise.length ? condivise[i] : '';
              }(),
            'b' => v == '1' ? 'TRUE' : 'FALSE',
            _ => v,
          };
        }
        final col = _colonna(c.getAttribute('r'));
        if (col >= 0) {
          while (riga.length <= col) {
            riga.add('');
          }
          riga[col] = valore;
        } else {
          riga.add(valore);
        }
      }
      righe.add(riga);
    }
  } catch (e) {
    return LetturaListino(const [], const {}, 0, ['Errore lettura XLSX: $e']);
  }
  if (righe.isEmpty) return LetturaListino(const [], const {}, 0, ['Foglio vuoto']);

  final intestazione = [for (final h in righe.first) h.toLowerCase().trim()];
  int indice(List<String> nomi) {
    for (final n in nomi) {
      final i = intestazione.indexOf(n);
      if (i >= 0) return i;
    }
    return -1;
  }

  final iCodice = indice(['codice']);
  final iDescr = indice(['descrizione', 'denominazione']);
  final iListino = indice(['prezzo_listino', 'listino', 'prezzo listino', 'listino €', 'listino euro', 'prezzo']);
  final iRiv = indice(['prezzo_rivenditore', 'rivenditore', 'prezzo rivenditore', 'netto']);
  final iEan = indice(['ean13', 'ean', 'barcode']);
  final iPag = indice(['pagina', 'pagina_catalogo', 'pagina catalogo', 'pag.']);
  final iGia = indice(['giacenza', 'stock', 'qta', 'quantita']);
  if (iCodice < 0) {
    return LetturaListino(const [], const {}, righe.length - 1, ["Colonna 'codice' non trovata nell'intestazione"]);
  }

  String cella(List<String> r, int i) => i < 0 || i >= r.length ? '' : r[i];
  final perCodice = <String, Articolo>{};
  final visti = <String>{};
  for (final r in righe.skip(1)) {
    final codice = cella(r, iCodice).trim();
    if (codice.isEmpty) continue;
    visti.add(codice);
    final e = esistenti[codice];
    if (e != null && e.origine == origineManuale) continue; // aggiunto a mano: resta il suo
    final listino = iListino >= 0 ? _numero(cella(r, iListino), e?.prezzoListino ?? 0) : (e?.prezzoListino ?? 0);
    perCodice[codice] = _componi(
      codice: codice,
      e: e,
      descrizione: iDescr >= 0 ? cella(r, iDescr).trim() : (e?.descrizione ?? ''),
      listino: listino,
      rivenditore: iRiv >= 0 ? _numero(cella(r, iRiv), listino) : listino,
      ean: iEan >= 0 ? cella(r, iEan).trim() : (e?.ean13 ?? ''),
      pagina: iPag >= 0 ? int.tryParse(cella(r, iPag).trim()) : e?.pagina,
      giacenza: iGia >= 0 ? _numero(cella(r, iGia), e?.giacenza ?? 0) : (e?.giacenza ?? 0),
    );
  }
  return LetturaListino(perCodice.values.toList(), visti, righe.length - 1, const []);
}

// ───────────────────────── CSV ─────────────────────────

/// Riga CSV con le virgolette («"a;b"» è un campo solo, «""» è una virgoletta).
List<String> _campiCsv(String riga, String sep) {
  final out = <String>[];
  final b = StringBuffer();
  var tra = false;
  for (var i = 0; i < riga.length; i++) {
    final c = riga[i];
    if (c == '"' && tra && i + 1 < riga.length && riga[i + 1] == '"') {
      b.write('"');
      i++;
    } else if (c == '"') {
      tra = !tra;
    } else if (c == sep && !tra) {
      out.add(b.toString());
      b.clear();
    } else {
      b.write(c);
    }
  }
  out.add(b.toString());
  return out;
}

/// CSV con intestazione: codice;descrizione;prezzo_listino;prezzo_rivenditore;ean13;pagina;giacenza
/// (punto e virgola come Excel italiano, oppure virgola).
LetturaListino leggiCsv(Uint8List dati, Map<String, Articolo> esistenti) {
  var testo = utf8.decode(dati, allowMalformed: true);
  if (testo.startsWith('﻿')) testo = testo.substring(1);
  final errori = <String>[];
  final perCodice = <String, Articolo>{};
  final visti = <String>{};
  List<String>? intestazione;
  var totali = 0;
  final righe = const LineSplitter().convert(testo);
  for (var n = 0; n < righe.length; n++) {
    final riga = righe[n].trim();
    if (riga.isEmpty) continue;
    final campi = _campiCsv(riga, riga.contains(';') ? ';' : ',');
    if (intestazione == null) {
      intestazione = [for (final c in campi) c.trim().toLowerCase()];
      continue;
    }
    totali++;
    final h = intestazione;
    String cella(String nome) {
      final i = h.indexOf(nome);
      return i < 0 || i >= campi.length ? '' : campi[i];
    }

    final codice = cella('codice').trim();
    if (codice.isEmpty) {
      errori.add('Riga ${n + 1}: codice mancante');
      continue;
    }
    visti.add(codice);
    final e = esistenti[codice];
    if (e != null && e.origine == origineManuale) continue;
    String oppure(String v, String altro) => v.trim().isEmpty ? altro : v;
    perCodice[codice] = _componi(
      codice: codice,
      e: e,
      descrizione: oppure(cella('descrizione'), e?.descrizione ?? ''),
      listino: _numero(cella('prezzo_listino'), e?.prezzoListino ?? 0),
      rivenditore: _numero(cella('prezzo_rivenditore'), e?.prezzoRivenditore ?? 0),
      ean: oppure(cella('ean13'), e?.ean13 ?? ''),
      pagina: int.tryParse(cella('pagina').trim()) ?? e?.pagina,
      giacenza: _numero(cella('giacenza'), e?.giacenza ?? 0),
    );
  }
  return LetturaListino(perCodice.values.toList(), visti, totali, errori);
}

// ───────────────────────── riscrittura Excel ─────────────────────────

String _xml(String s) {
  final b = StringBuffer();
  for (final c in s.codeUnits) {
    switch (c) {
      case 0x26:
        b.write('&amp;');
      case 0x3C:
        b.write('&lt;');
      case 0x3E:
        b.write('&gt;');
      case 0x22:
        b.write('&quot;');
      case 0x27:
        b.write('&apos;');
      default:
        // i caratteri di controllo non sono ammessi in XML 1.0 (tranne tab, a capo)
        b.writeCharCode(c < 0x20 && c != 0x09 && c != 0x0A && c != 0x0D ? 0x20 : c);
    }
  }
  return b.toString();
}

String _lettera(int i) {
  var n = i;
  var s = '';
  while (n >= 0) {
    s = String.fromCharCode(65 + n % 26) + s;
    n = n ~/ 26 - 1;
  }
  return s;
}

String _foglio(List<Articolo> articoli) {
  final b = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>');
  void testo(int col, int riga, String v) =>
      b.write('<c r="${_lettera(col)}$riga" t="inlineStr"><is><t xml:space="preserve">${_xml(v)}</t></is></c>');
  void num(int col, int riga, double v) =>
      b.write('<c r="${_lettera(col)}$riga"><v>${v == v.truncateToDouble() ? v.toInt() : doubleJava(v)}</v></c>');

  b.write('<row r="1">');
  const titoli = ['codice', 'descrizione', 'prezzo_listino', 'prezzo_rivenditore', 'ean13', 'pagina', 'giacenza', 'origine'];
  for (var i = 0; i < titoli.length; i++) {
    testo(i, 1, titoli[i]);
  }
  b.write('</row>');
  for (var i = 0; i < articoli.length; i++) {
    final a = articoli[i];
    final r = i + 2;
    b.write('<row r="$r">');
    testo(0, r, a.codice);
    testo(1, r, a.descrizione);
    num(2, r, a.prezzoListino);
    num(3, r, a.prezzoRivenditore);
    testo(4, r, a.ean13);
    if (a.pagina != null) {
      num(5, r, a.pagina!.toDouble());
    } else {
      testo(5, r, '');
    }
    num(6, r, a.giacenza);
    testo(7, r, a.origine);
    b.write('</row>');
  }
  b.write('</sheetData></worksheet>');
  return b.toString();
}

const _tipi = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
    '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
    '</Types>';
const _relRadice = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
    '</Relationships>';
const _relCartella = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
    '</Relationships>';
const _cartella = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
    '<sheets><sheet name="Listino" sheetId="1" r:id="rId1"/></sheets></workbook>';
const _stili = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>'
    '<fills count="1"><fill><patternFill patternType="none"/></fill></fills>'
    '<borders count="1"><border/></borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>'
    '</styleSheet>';

/// File Excel del listino: codice | descrizione | prezzo_listino | prezzo_rivenditore | ean13 | pagina | giacenza | origine
List<int> scriviXlsx(List<Articolo> articoli) {
  final a = Archive();
  void aggiungi(String nome, String testo) {
    final b = utf8.encode(testo);
    a.addFile(ArchiveFile(nome, b.length, b));
  }

  aggiungi('[Content_Types].xml', _tipi);
  aggiungi('_rels/.rels', _relRadice);
  aggiungi('xl/_rels/workbook.xml.rels', _relCartella);
  aggiungi('xl/workbook.xml', _cartella);
  aggiungi('xl/styles.xml', _stili);
  aggiungi('xl/worksheets/sheet1.xml', _foglio(articoli));
  return ZipEncoder().encode(a);
}

/// Impronta degli articoli come la calcolava la versione Kotlin (stessa stringa, stesso SHA-256):
/// così il file scritto dalla versione precedente risulta già aggiornato.
String hashArticoli(List<Articolo> articoli) {
  final b = StringBuffer();
  for (final a in articoli) {
    b
      ..write(a.codice)
      ..write('|')
      ..write(a.descrizione)
      ..write('|')
      ..write(doubleJava(a.prezzoListino))
      ..write('|')
      ..write(doubleJava(a.prezzoRivenditore))
      ..write('|')
      ..write(a.ean13)
      ..write('|')
      ..write(a.pagina ?? '')
      ..write('|')
      ..write(doubleJava(a.giacenza))
      ..write('|')
      ..write(a.origine)
      ..write('\n');
  }
  return sha256.convert(utf8.encode(b.toString())).toString();
}
