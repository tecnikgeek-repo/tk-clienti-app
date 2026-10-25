// PDF del preventivo, uguale a quello della versione Kotlin (PreventivoPdfGenerator): A4, intestazione con
// logo valigetta, box destinatario, tabella righe a righe alterne, box totali, note, pagamento, piè di pagina.
// Pensato per la stampa: niente fondi pieni di colore, solo righe e bordi blu.
import 'dart:typed_data';

import 'package:pdf/pdf.dart';

import 'formati.dart';
import 'modelli.dart';

/// Nome del file: «Preventivo_2026-007_Rossi.pdf»
String nomeFilePdf(Preventivo p, Cliente c) {
  final chi = (c.cognome.trim().isEmpty ? c.nome : c.cognome).trim().replaceAll(' ', '_');
  final pulito = chi.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
  return 'Preventivo_${p.numero.replaceAll('/', '-')}_$pulito.pdf';
}

const _pagW = 595.0, _pagH = 842.0;
const _margX = 40.0, _margSu = 36.0, _margGiu = 56.0;
const _contW = _pagW - 2 * _margX;

const _navy = PdfColor.fromInt(0xFF0F172A);
const _accento = PdfColor.fromInt(0xFF1D4ED8);
const _testo = PdfColor.fromInt(0xFF0F172A);
const _testo2 = PdfColor.fromInt(0xFF475569);
const _tenue = PdfColor.fromInt(0xFF94A3B8);
const _bordo = PdfColor.fromInt(0xFFE2E8F0);
const _zebra = PdfColor.fromInt(0xFFF8FAFC);

// colonne della tabella
const _col1 = _margX + 8, _col2 = _margX + 100;
const _col3 = _margX + _contW - 230, _col4 = _margX + _contW - 150;
const _col5 = _margX + _contW - 70, _col6 = _margX + _contW - 8;

enum _Alline { sx, dx, centro }

/// Disegno con le coordinate dall'alto come su Android (il PDF le conta dal basso).
class _Tela {
  _Tela(this.g, this.normale, this.grassetto);

  final PdfGraphics g;
  final PdfFont normale, grassetto;

  double _y(double y) => _pagH - y;

  void testo(String s, double x, double y, double dim,
      {bool bold = false, PdfColor colore = _testo, _Alline a = _Alline.sx, double spaziatura = 0}) {
    if (s.isEmpty) return;
    final f = bold ? grassetto : normale;
    final larg = f.stringMetrics(s, letterSpacing: spaziatura).advanceWidth * dim;
    final x0 = switch (a) { _Alline.sx => x, _Alline.dx => x - larg, _Alline.centro => x - larg / 2 };
    g
      ..setFillColor(colore)
      ..drawString(f, dim, s, x0, _y(y), charSpace: spaziatura * dim);
  }

  void linea(double x1, double y1, double x2, double y2, double spessore, PdfColor colore) {
    g
      ..setStrokeColor(colore)
      ..setLineWidth(spessore)
      ..drawLine(x1, _y(y1), x2, _y(y2))
      ..strokePath();
  }

  void rett(double x, double y, double w, double h, PdfColor colore) {
    g
      ..setFillColor(colore)
      ..drawRect(x, _y(y + h), w, h)
      ..fillPath();
  }

  void rettTondo(double x, double y, double w, double h, double r, PdfColor colore,
      {bool pieno = true, double spessore = 1}) {
    g.drawRRect(x, _y(y + h), w, h, r, r);
    if (pieno) {
      g
        ..setFillColor(colore)
        ..fillPath();
    } else {
      g
        ..setStrokeColor(colore)
        ..setLineWidth(spessore)
        ..strokePath();
    }
  }

  /// Logo valigetta (lo stesso della versione Kotlin): quadrato navy, valigetta di cuoio, fibbie dorate.
  void logo(double x, double y, double lato) {
    rettTondo(x, y, lato, lato, lato * .18, _navy);
    final s = lato / 108;
    double px(double v) => v * s + x;
    double py(double v) => _y(v * s + y);
    // manico
    g
      ..setFillColor(const PdfColor.fromInt(0xFF7B4A1F))
      ..moveTo(px(38), py(40))
      ..lineTo(px(38), py(33))
      ..curveTo(px(38), py(29.13), px(41.13), py(26), px(45), py(26))
      ..lineTo(px(63), py(26))
      ..curveTo(px(66.87), py(26), px(70), py(29.13), px(70), py(33))
      ..lineTo(px(70), py(40))
      ..lineTo(px(64), py(40))
      ..lineTo(px(64), py(33))
      ..curveTo(px(64), py(32.45), px(63.55), py(32), px(63), py(32))
      ..lineTo(px(45), py(32))
      ..curveTo(px(44.45), py(32), px(44), py(32.45), px(44), py(33))
      ..lineTo(px(44), py(40))
      ..closePath()
      ..fillPath();
    rettTondo(px(24), 40 * s + y, 60 * s, 40 * s, s * 4, const PdfColor.fromInt(0xFFC9A66B)); // corpo
    rett(px(28), 42 * s + y, 52 * s, 2 * s, const PdfColor.fromInt(0xFFD8B884)); // luce
    rett(px(24), 57 * s + y, 60 * s, 4 * s, const PdfColor.fromInt(0xFF8B5A2B)); // banda
    const oro = PdfColor.fromInt(0xFFE8B923);
    rettTondo(px(49), 53 * s + y, 11 * s, 14 * s, s, oro); // lucchetto
    rett(px(53), 57 * s + y, 3 * s, 6 * s, const PdfColor.fromInt(0xFF3B2410));
    rettTondo(px(30), 55 * s + y, 8 * s, 8 * s, s, oro); // fibbie
    rettTondo(px(70), 55 * s + y, 8 * s, 8 * s, s, oro);
  }
}

/// A capo per numero di caratteri, come la versione Kotlin (in più rispetta gli a capo scritti).
List<String> _aCapo(String testo, int massimo) {
  if (testo.trim().isEmpty) return [''];
  final righe = <String>[];
  for (final paragrafo in testo.split('\n')) {
    final b = StringBuffer();
    for (final parola in paragrafo.split(' ')) {
      if (b.isEmpty) {
        b.write(parola);
      } else if (b.length + 1 + parola.length <= massimo) {
        b.write(' $parola');
      } else {
        righe.add(b.toString());
        b
          ..clear()
          ..write(parola);
      }
    }
    righe.add(b.toString());
  }
  return righe;
}

double _altezzaRiga(RigaPreventivo r) => 14 + _aCapo(r.descrizione, 28).length * 12 + 6;

String _intero(double v) => v.round().toString();

/// Crea il PDF; i font (Roboto) arrivano dagli asset dell'app o, nei test, dal disco.
Future<Uint8List> creaPdfPreventivo(
  Preventivo p,
  Cliente c,
  List<RigaPreventivo> righe,
  Intestazione it, {
  required ByteData fontNormale,
  required ByteData fontGrassetto,
}) async {
  final doc = PdfDocument();
  final normale = PdfTtfFont(doc, fontNormale);
  final grassetto = PdfTtfFont(doc, fontGrassetto);
  const formato = PdfPageFormat(_pagW, _pagH);

  // pagine totali per «PAG. 1 / 2»: stesso calcolo dell'impaginazione qui sotto
  // (prima pagina: le righe partono a 282; le altre, con la testata ridotta, a 130)
  var totPagine = 1;
  var yStima = 282.0;
  for (final r in righe) {
    final h = _altezzaRiga(r);
    if (yStima + h > _pagH - _margGiu - 200) {
      totPagine++;
      yStima = 130;
    }
    yStima += h;
  }

  var numPagina = 1;
  var t = _Tela(PdfPage(doc, pageFormat: formato).getGraphics(), normale, grassetto);
  var y = _testata(t, it, p, ridotta: false);
  y = _destinatario(t, y, c);
  y = _intestazioneTabella(t, y + 18);
  for (var i = 0; i < righe.length; i++) {
    final h = _altezzaRiga(righe[i]);
    if (y + h > _pagH - _margGiu - 200) {
      _piede(t, numPagina, totPagine, it);
      numPagina++;
      t = _Tela(PdfPage(doc, pageFormat: formato).getGraphics(), normale, grassetto);
      y = _testata(t, it, p, ridotta: true);
      y = _intestazioneTabella(t, y + 12);
    }
    _riga(t, y, i + 1, righe[i]);
    y += h;
  }
  y += 24;
  y = _totali(t, y, p, righe);
  if (p.note.trim().isNotEmpty) y = _note(t, y + 16, p.note);
  _pagamento(t, y + 12, it);
  _piede(t, numPagina, totPagine, it);
  return doc.save();
}

double _testata(_Tela t, Intestazione it, Preventivo p, {required bool ridotta}) {
  // la riga blu sta sotto «N° …» anche nelle pagine seguenti (a 50 tagliava il titolo)
  const banda = 80.0;
  t.logo(_margX, _margSu, 28);
  t.testo(it.ragioneSociale.trim().isEmpty ? 'La tua attività' : it.ragioneSociale, _margX + 38, _margSu + 13, 13,
      bold: true, spaziatura: .02);
  if (!ridotta) {
    final info = [
      it.indirizzo,
      '${it.cap} ${it.citta} ${it.provincia}'.trim(),
      if (it.telefono.trim().isNotEmpty) 'T ${it.telefono}',
      it.email,
    ].where((s) => s.trim().isNotEmpty).join(' · ');
    t.testo(info, _margX + 38, _margSu + 26, 9, colore: _testo2);
    if (it.piva.trim().isNotEmpty) t.testo('P.IVA ${it.piva}', _margX + 38, _margSu + 38, 9, colore: _testo2);
  }
  t.testo('PREVENTIVO', _pagW - _margX, _margSu + 16, 22, bold: true, colore: _navy, a: _Alline.dx, spaziatura: .08);
  t.testo('N° ${p.numero}', _pagW - _margX, _margSu + 34, 13, bold: true, colore: _accento, a: _Alline.dx);
  t.linea(_margX, banda, _pagW - _margX, banda, 2, _accento);
  if (ridotta) return banda + 16;
  final base = banda + 26;
  _blocchetto(t, _margX, base, 'DATA EMISSIONE', dataLunga(p.data));
  _blocchetto(t, _margX + 170, base, 'VALIDITÀ', '${p.validita} giorni');
  _blocchetto(t, _margX + 340, base, 'TOTALE', euro(p.totale), accento: true);
  return base + 46;
}

void _blocchetto(_Tela t, double x, double y, String etichetta, String valore, {bool accento = false}) {
  t.testo(etichetta, x, y, 8, bold: true, colore: _tenue, spaziatura: .12);
  t.testo(valore, x, y + 16, accento ? 16 : 13, bold: true, colore: accento ? _accento : _testo);
}

double _destinatario(_Tela t, double y0, Cliente c) {
  const h = 90.0;
  t.rettTondo(_margX, y0, _contW, h, 8, _zebra);
  t.rettTondo(_margX, y0, _contW, h, 8, _bordo, pieno: false);
  t.rett(_margX, y0, 3, h, _accento);
  const x = _margX + 16;
  t.testo('DESTINATARIO', x, y0 + 16, 8.5, bold: true, colore: _accento, spaziatura: .15);
  t.testo(c.nominativo.isEmpty ? '(senza nome)' : c.nominativo, x, y0 + 34, 15, bold: true, spaziatura: -.01);
  var r = y0 + 50;
  for (final riga in [
    c.indirizzoCompleto,
    [if (c.piva.trim().isNotEmpty) 'P.IVA ${c.piva}', if (c.codiceFiscale.trim().isNotEmpty) 'CF ${c.codiceFiscale}']
        .join(' · '),
    [c.telefono, c.email].where((s) => s.trim().isNotEmpty).join(' · '),
  ]) {
    if (riga.trim().isEmpty) continue;
    t.testo(riga, x, r, 10, colore: _testo2);
    r += 13;
  }
  return y0 + h;
}

double _intestazioneTabella(_Tela t, double y0) {
  const h = 22.0;
  void titolo(String s, double x, {bool dx = true}) =>
      t.testo(s, x, y0 + 14, 8.5, bold: true, colore: _navy, a: dx ? _Alline.dx : _Alline.sx, spaziatura: .12);
  titolo('CODICE', _col1, dx: false);
  titolo('DESCRIZIONE', _col2, dx: false);
  titolo('Q.TÀ', _col3);
  titolo('PREZZO', _col4);
  titolo('SC%', _col5);
  titolo('TOTALE', _col6);
  t.linea(_margX, y0 + h, _margX + _contW, y0 + h, 1.5, _accento);
  return y0 + h;
}

void _riga(_Tela t, double y0, int indice, RigaPreventivo r) {
  final desc = _aCapo(r.descrizione, 28);
  final h = 14 + desc.length * 12 + 6.0;
  if (indice.isEven) t.rett(_margX, y0, _contW, h, _zebra);
  t.testo(r.codice, _col1, y0 + 14, 9, bold: true);
  for (var i = 0; i < desc.length; i++) {
    t.testo(desc[i], _col2, y0 + 14 + i * 12, 9, colore: _testo2);
  }
  t.testo('${numero(r.quantita)} ${r.unitaMisura}', _col3, y0 + 14, 9, colore: _testo2, a: _Alline.dx);
  t.testo(euro(r.prezzoUnitario), _col4, y0 + 14, 9, colore: _testo2, a: _Alline.dx);
  t.testo(r.scontoPercentuale > 0 ? '${_intero(r.scontoPercentuale)}%' : '—', _col5, y0 + 14, 9,
      colore: _testo2, a: _Alline.dx);
  t.testo(euro(r.totaleRiga), _col6, y0 + 14, 9, bold: true, a: _Alline.dx);
  t.linea(_margX, y0 + h, _margX + _contW, y0 + h, .5, _bordo);
}

double _totali(_Tela t, double y0, Preventivo p, List<RigaPreventivo> righe) {
  const larg = 240.0;
  const x = _margX + _contW - larg;
  var y = y0 + 14;
  void voce(String etichetta, String valore) {
    t.testo(etichetta, x, y, 10, colore: _testo2);
    t.testo(valore, x + larg, y, 10, bold: true, a: _Alline.dx);
  }

  voce('Imponibile', euro(p.totaleImponibile));
  y += 18;
  if (p.scontoGlobale > 0) {
    final lordo = righe.fold<double>(0, (s, r) => s + r.totaleRiga);
    voce('Sconto ${numero(p.scontoGlobale)}%', '- ${euro(lordo - p.totaleImponibile)}');
    y += 18;
  }
  voce('IVA ${_intero(p.ivaPercentuale)}%', euro(p.totaleIva));
  y += 14;
  t.linea(x, y, x + larg, y, 1, _bordo);
  y += 18;
  const hTot = 48.0;
  t.rettTondo(x, y, larg, hTot, 6, _accento, pieno: false, spessore: 1.5);
  t.testo('IMPORTO TOTALE', x + 14, y + 16, 9, bold: true, colore: _accento, spaziatura: .2);
  t.testo(euro(p.totale), x + larg - 14, y + 38, 20, bold: true, colore: _navy, a: _Alline.dx);
  return y + hTot + 8;
}

double _note(_Tela t, double y0, String note) {
  t.testo('NOTE', _margX, y0, 8.5, bold: true, colore: _accento, spaziatura: .15);
  var y = y0 + 14;
  for (final l in _aCapo(note, 95)) {
    t.testo(l, _margX, y, 10, colore: _testo2);
    y += 13;
  }
  return y + 4;
}

void _pagamento(_Tela t, double y0, Intestazione it) {
  if (it.iban.trim().isEmpty) return;
  t.testo('PAGAMENTO', _margX, y0, 8.5, bold: true, colore: _accento, spaziatura: .15);
  t.testo('Bonifico bancario · IBAN ${it.iban}', _margX, y0 + 14, 10, colore: _testo2);
}

void _piede(_Tela t, int pagina, int totale, Intestazione it) {
  t.linea(_margX, _pagH - 38, _pagW - _margX, _pagH - 38, .5, _bordo);
  final parti = [
    it.ragioneSociale,
    [it.indirizzo, '${it.cap} ${it.citta} ${it.provincia}'.trim()].where((s) => s.trim().isNotEmpty).join(' – '),
    if (it.piva.trim().isNotEmpty) 'P.IVA ${it.piva}',
  ].where((s) => s.trim().isNotEmpty).join(' · ');
  t.testo(parti, _pagW / 2, _pagH - 22, 8.5, colore: _tenue, a: _Alline.centro);
  t.testo(it.noteFooter, _pagW / 2, _pagH - 10, 8.5, colore: _tenue, a: _Alline.centro);
  t.testo('PAG. $pagina / $totale', _pagW - _margX, _pagH - 22, 8, bold: true, colore: _tenue, a: _Alline.dx, spaziatura: .1);
}
