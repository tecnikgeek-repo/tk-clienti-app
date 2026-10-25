// Andamento: fatturato e commissioni per giorno (ultimi 30), mese (anno a scelta) o anno, con grafico a barre.
// Le commissioni usano sempre la percentuale ATTUALE di ogni cliente (o la predefinita).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app.dart';
import '../dati/formati.dart';
import '../dati/modelli.dart';
import '../tema.dart';

enum _Periodo { giorni, mesi, anni }

enum _Metrica { commissioni, fatturato }

class _Gruppo {
  _Gruppo(this.etichetta);
  final String etichetta;
  double fatturato = 0, commissioni = 0;
  int n = 0;
}

class SchermataAndamento extends StatefulWidget {
  const SchermataAndamento({super.key});

  @override
  State<SchermataAndamento> createState() => _SchermataAndamentoState();
}

class _SchermataAndamentoState extends State<SchermataAndamento> {
  _Periodo _periodo = _Periodo.mesi;
  _Metrica _metrica = _Metrica.commissioni;
  int _anno = DateTime.now().year;
  int? _scelto;

  List<_Gruppo> _gruppi() {
    final cfg = impostazioni.commissione;
    final perc = {for (final c in archivio.clienti) c.id: c.commissionePerc};
    final dati = [
      for (final p in archivio.preventivi)
        (DateTime.fromMillisecondsSinceEpoch(p.data), p.totale, commissionePreventivo(p, perc[p.clienteId] ?? -1, cfg))
    ];
    void somma(_Gruppo g, (DateTime, double, double) d) {
      g
        ..fatturato += d.$2
        ..commissioni += d.$3
        ..n += 1;
    }

    switch (_periodo) {
      case _Periodo.giorni:
        final oggi = DateTime.now();
        final inizio = DateTime(oggi.year, oggi.month, oggi.day);
        final giorni = [
          for (var i = 29; i >= 0; i--) DateTime(inizio.year, inizio.month, inizio.day - i),
        ];
        final gruppi = [
          for (final g in giorni) _Gruppo('${g.day.toString().padLeft(2, '0')}/${g.month.toString().padLeft(2, '0')}')
        ];
        for (final d in dati) {
          final giorno = DateTime(d.$1.year, d.$1.month, d.$1.day);
          final i = giorni.indexWhere((g) => g == giorno);
          if (i >= 0) somma(gruppi[i], d);
        }
        return gruppi;
      case _Periodo.mesi:
        final gruppi = [for (final m in mesiBrevi) _Gruppo(m)];
        for (final d in dati) {
          if (d.$1.year == _anno) somma(gruppi[d.$1.month - 1], d);
        }
        return gruppi;
      case _Periodo.anni:
        if (dati.isEmpty) return [_Gruppo('${DateTime.now().year}')];
        final minA = dati.map((d) => d.$1.year).reduce(math.min);
        final maxA = dati.map((d) => d.$1.year).reduce(math.max);
        final gruppi = [for (var a = minA; a <= maxA; a++) _Gruppo('$a')];
        for (final d in dati) {
          somma(gruppi[d.$1.year - minA], d);
        }
        return gruppi;
    }
  }

  @override
  Widget build(BuildContext context) {
    final gruppi = _gruppi();
    final totF = gruppi.fold<double>(0, (s, g) => s + g.fatturato);
    final totC = gruppi.fold<double>(0, (s, g) => s + g.commissioni);
    final totN = gruppi.fold<int>(0, (s, g) => s + g.n);
    final annoOra = DateTime.now().year;
    final sel = _scelto != null && _scelto! < gruppi.length ? gruppi[_scelto!] : null;
    return Scaffold(
      body: Column(children: [
        Testata(
            titolo: 'Andamento',
            sottotitolo: 'Fatturato e commissioni',
            indietro: () => Navigator.pop(context),
            logo: false),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(14, 14, 14, spazioFondo(context)),
            children: [
              Scelta<_Periodo>(
                voci: const [(_Periodo.giorni, 'Giorni'), (_Periodo.mesi, 'Mesi'), (_Periodo.anni, 'Anni')],
                valore: _periodo,
                onCambia: (v) => setState(() {
                  _periodo = v;
                  _scelto = null;
                }),
              ),
              const SizedBox(height: 10),
              if (_periodo == _Periodo.mesi)
                Row(children: [
                  IconButton(
                    onPressed: () => setState(() {
                      _anno--;
                      _scelto = null;
                    }),
                    icon: const Icon(Icons.chevron_left_rounded, color: navy),
                    tooltip: 'Anno precedente',
                  ),
                  Expanded(
                    child: Text('$_anno',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: navy, fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    onPressed: _anno < annoOra
                        ? () => setState(() {
                              _anno++;
                              _scelto = null;
                            })
                        : null,
                    icon: Icon(Icons.chevron_right_rounded, color: _anno < annoOra ? navy : grigio300),
                    tooltip: 'Anno successivo',
                  ),
                ])
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(_periodo == _Periodo.giorni ? 'Ultimi 30 giorni' : 'Tutti gli anni',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: grigio500, fontSize: 13.5, fontWeight: FontWeight.w700)),
                ),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: _Riepilogo('COMMISSIONI', euro(totC), verde)),
                const SizedBox(width: 10),
                Expanded(child: _Riepilogo('FATTURATO', euro(totF), accento)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _Riepilogo('PREVENTIVI', '$totN', navy3)),
                const SizedBox(width: 10),
                Expanded(child: _Riepilogo('COMM. MEDIA', euro(totN > 0 ? totC / totN : 0), ambra)),
              ]),
              const SizedBox(height: 14),
              Scelta<_Metrica>(
                voci: const [(_Metrica.commissioni, 'Commissioni'), (_Metrica.fatturato, 'Fatturato')],
                valore: _metrica,
                onCambia: (v) => setState(() {
                  _metrica = v;
                  _scelto = null;
                }),
              ),
              const SizedBox(height: 12),
              CardTk(
                padding: const EdgeInsets.all(14),
                child: sel == null
                    ? const Text('Tocca una barra per vedere il dettaglio del periodo.',
                        style: TextStyle(color: grigio500, fontSize: 12.5, fontWeight: FontWeight.w600))
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(sel.etichetta, style: const TextStyle(color: navy, fontSize: 15, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text('Commissioni: ${euro(sel.commissioni)}',
                            style: const TextStyle(color: verdeScuro, fontWeight: FontWeight.w700)),
                        Text('Fatturato: ${euro(sel.fatturato)}',
                            style: const TextStyle(color: accentoScuro, fontWeight: FontWeight.w700)),
                        Text('Preventivi: ${sel.n}', style: const TextStyle(color: grigio500, fontWeight: FontWeight.w700)),
                      ]),
              ),
              const SizedBox(height: 12),
              CardTk(
                padding: const EdgeInsets.all(12),
                child: gruppi.every((g) => g.n == 0)
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Nessun preventivo in questo periodo.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: grigio500, fontWeight: FontWeight.w600)),
                      )
                    : _Grafico(
                        gruppi: gruppi,
                        commissioni: _metrica == _Metrica.commissioni,
                        scelto: _scelto,
                        onScelta: (i) => setState(() => _scelto = _scelto == i ? null : i),
                      ),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _Riepilogo extends StatelessWidget {
  const _Riepilogo(this.etichetta, this.valore, this.colore);

  final String etichetta, valore;
  final Color colore;

  @override
  Widget build(BuildContext context) => CardTk(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              width: 34, height: 4, decoration: BoxDecoration(color: colore, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          Text(etichetta, style: const TextStyle(color: grigio500, fontSize: 10.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(valore, style: const TextStyle(color: navy, fontSize: 18, fontWeight: FontWeight.w800)),
          ),
        ]),
      );
}

/// «€1,2k», «€850»
String _compatto(double v) {
  if (v >= 1000) {
    final k = v / 1000;
    return '€${k % 1 == 0 ? k.toInt() : k.toStringAsFixed(1).replaceAll('.', ',')}k';
  }
  return '€${v.toInt()}';
}

class _Grafico extends StatelessWidget {
  const _Grafico({required this.gruppi, required this.commissioni, required this.scelto, required this.onScelta});

  final List<_Gruppo> gruppi;
  final bool commissioni;
  final int? scelto;
  final ValueChanged<int> onScelta;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, v) => GestureDetector(
          onTapDown: (d) {
            final i = (d.localPosition.dx / (v.maxWidth / gruppi.length)).floor().clamp(0, gruppi.length - 1);
            onScelta(i);
          },
          child: CustomPaint(
            size: Size(v.maxWidth, 230),
            painter: _Barre(gruppi, commissioni, scelto),
          ),
        ),
      );
}

class _Barre extends CustomPainter {
  _Barre(this.gruppi, this.commissioni, this.scelto);

  final List<_Gruppo> gruppi;
  final bool commissioni;
  final int? scelto;

  @override
  void paint(Canvas canvas, Size size) {
    final colore = commissioni ? verde : accento;
    final coloreSel = commissioni ? verdeScuro : accentoScuro;
    final valori = [for (final g in gruppi) commissioni ? g.commissioni : g.fatturato];
    final massimo = math.max(valori.fold<double>(0, math.max), 1.0);
    const sotto = 22.0, sopra = 18.0;
    final altezza = size.height - sotto - sopra;
    final base = sopra + altezza;
    final n = gruppi.length;
    final slot = size.width / n;
    const spazio = 3.0;
    final larg = math.max(slot - spazio, 2.0);

    final griglia = Paint()
      ..color = grigio200
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = sopra + altezza * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), griglia);
    }
    final ogni = n <= 12 ? 1 : (n / 8).ceil();
    void scrivi(String t, double cx, double y, Color c, double dim, {bool bold = false}) {
      final tp = TextPainter(
        text: TextSpan(text: t, style: TextStyle(color: c, fontSize: dim, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, y));
    }

    for (var i = 0; i < n; i++) {
      final v = valori[i];
      final h = altezza * (v / massimo);
      final x = slot * i + spazio / 2;
      final top = base - h;
      canvas.drawRRect(
        RRect.fromRectAndCorners(Rect.fromLTWH(x, top, larg, h),
            topLeft: const Radius.circular(4), topRight: const Radius.circular(4)),
        Paint()..color = scelto == i ? coloreSel : colore,
      );
      if (n <= 12 && v > 0) scrivi(_compatto(v), x + larg / 2, math.max(top - 15, 0), coloreSel, 9, bold: true);
      if (i % ogni == 0 || i == n - 1) scrivi(gruppi[i].etichetta, x + larg / 2, size.height - 16, grigio500, 10);
    }
  }

  @override
  bool shouldRepaint(covariant _Barre old) => true;
}
