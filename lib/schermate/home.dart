// Schermata principale: preventivi del mese e dell'anno (cifre nascoste come nell'app della banca),
// azioni rapide, andamento, clienti, magazzino e ultimi preventivi.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../dati/formati.dart';
import '../dati/impostazioni.dart';
import '../dati/modelli.dart';
import '../tema.dart';
import '../tk_pro.dart';
import 'andamento.dart';
import 'articoli.dart';
import 'clienti.dart';
import 'impostazioni.dart';
import 'preventivi.dart';
import 'preventivo_modulo.dart';

class SchermataHome extends StatefulWidget {
  const SchermataHome({super.key, this.crash});

  final String? crash;

  @override
  State<SchermataHome> createState() => _SchermataHomeState();
}

class _SchermataHomeState extends State<SchermataHome> {
  late bool _nascoste = impostazioni.cifreNascoste;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (widget.crash != null) await _mostraCrash(widget.crash!);
      // primo avvio: benvenuto (software libero, privacy, statistiche) PRIMA di qualunque chiamata in rete
      if (mounted) await benvenutoTk(context);
      if (!mounted) return;
      sincronia.allAvvio();
      if (mounted) proponiAggiornamento(context, avvisaSeAggiornata: false);
      // invito al caffè: al primo avvio e poi al massimo una volta al mese, mai sopra un'altra finestra
      if (mounted) invitoCaffe(context);
    });
  }

  Future<void> _mostraCrash(String testo) => showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text("L'app si era chiusa per un errore"),
          content: SingleChildScrollView(
              child: Text(testo, style: const TextStyle(fontFamily: 'monospace', fontSize: 11))),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: testo));
                avviso(context, 'Copiato: incollalo in un messaggio a TecnikGeek');
              },
              child: const Text('Copia'),
            ),
            FilledButton(onPressed: () => Navigator.pop(d), child: const Text('Continua')),
          ],
        ),
      );

  String _cifra(double v) => _nascoste ? '••••• €' : euroTondo(v);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: archivio,
        builder: (context, _) {
          final ora = DateTime.now();
          final tutti = archivio.preventivi;
          bool anno(Preventivo p) => DateTime.fromMillisecondsSinceEpoch(p.data).year == ora.year;
          bool mese(Preventivo p) {
            final d = DateTime.fromMillisecondsSinceEpoch(p.data);
            return d.year == ora.year && d.month == ora.month;
          }

          final delMese = tutti.where(mese).toList();
          final dellAnno = tutti.where(anno).toList();
          final totMese = delMese.fold<double>(0, (s, p) => s + p.totale);
          final totAnno = dellAnno.fold<double>(0, (s, p) => s + p.totale);

          return Scaffold(
            body: Column(children: [
              Testata(
                sottotitolo: 'Clienti, listino e preventivi',
                azioni: [
                  AzioneTk(_nascoste ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      _nascoste ? 'Mostra le cifre' : 'Nascondi le cifre', () {
                    setState(() => _nascoste = !_nascoste);
                    impostazioni.nascondiCifre(_nascoste);
                  }),
                  AzioneTk(Icons.settings_rounded, 'Impostazioni', () => vai(context, const SchermataImpostazioni())),
                  AzioneTk(
                      Icons.info,
                      'Informazioni',
                      () => apriInformazioni(context,
                          righe: () async => [
                                ('Clienti', '${archivio.clienti.length}'),
                                ('Articoli a listino', '${archivio.nArticoli}'),
                                ('Preventivi', '${archivio.preventivi.length}'),
                                ('File collegati',
                                    '${Dominio.values.where((d) => impostazioni.file(d).collegato).length} di ${Dominio.values.length}'),
                              ],
                          notaDati: 'Restano su questo telefono e nei file che colleghi tu (Drive, Dropbox o telefono).')),
                ],
                sotto: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('PREVENTIVI DEL MESE',
                      style: TextStyle(color: grigio300, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .8)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(_cifra(totMese),
                        style: const TextStyle(color: bianco, fontSize: 38, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
                  ),
                  Text('${delMese.length} ${delMese.length == 1 ? 'preventivo' : 'preventivi'} a ${_nomeMese(ora.month)}',
                      style: const TextStyle(color: grigio300, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(flex: 14, child: _Kpi(_cifra(totAnno), 'Anno ${ora.year} · ${dellAnno.length}')),
                    const SizedBox(width: 8),
                    Expanded(
                        flex: 10,
                        child: _Kpi('${archivio.clienti.length}', 'Clienti',
                            onTap: () => vai(context, const SchermataClienti()))),
                    const SizedBox(width: 8),
                    Expanded(
                        flex: 10,
                        child: _Kpi('${archivio.nArticoli}', 'Articoli',
                            onTap: () => vai(context, const SchermataArticoli()))),
                  ]),
                ]),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: accento,
                  onRefresh: () async {
                    final esito = await sincronia.sincronizzaTutto();
                    if (context.mounted) avviso(context, esito);
                  },
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(14, 14, 14, spazioFondo(context)),
                    children: [
                      Row(children: [
                        Expanded(
                            child: _Rapida('Nuovo\ncliente', Icons.person_add_alt_1_rounded, accento,
                                () => vai(context, const SchermataModificaCliente()))),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _Rapida('Nuovo\npreventivo', Icons.post_add_rounded, verde,
                                () => vai(context, const SchermataModuloPreventivo()))),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _Rapida('Nuovo\narticolo', Icons.add_box_rounded, ambra,
                                () => vai(context, const SchermataArticolo()))),
                      ]),
                      const SizedBox(height: 14),
                      _Voce(
                        icona: Icons.people_alt_rounded,
                        colore: accento,
                        titolo: 'Clienti',
                        sotto: archivio.clienti.isEmpty
                            ? 'Anagrafica, contatti e storico'
                            : '${archivio.clienti.length} in anagrafica',
                        onTap: () => vai(context, const SchermataClienti()),
                      ),
                      const SizedBox(height: 10),
                      _Voce(
                        icona: Icons.inventory_2_rounded,
                        colore: ambra,
                        titolo: 'Magazzino',
                        sotto: archivio.nArticoli == 0
                            ? 'Listino prodotti e giacenze'
                            : '${archivio.nArticoli} articoli a listino',
                        onTap: () => vai(context, const SchermataArticoli()),
                      ),
                      const SizedBox(height: 10),
                      _Voce(
                        icona: Icons.show_chart_rounded,
                        colore: verde,
                        titolo: 'Andamento e commissioni',
                        sotto: 'Fatturato e provvigioni per giorno, mese, anno',
                        onTap: () => vai(context, const SchermataAndamento()),
                      ),
                      const SizedBox(height: 18),
                      Row(children: [
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Text('Ultimi preventivi',
                              style: TextStyle(color: navy, fontSize: 15, fontWeight: FontWeight.w800)),
                        ),
                        const Spacer(),
                        TextButton(
                            onPressed: () => vai(context, const SchermataPreventivi()),
                            child: Text('Vedi tutti (${tutti.length})')),
                      ]),
                      const SizedBox(height: 4),
                      if (tutti.isEmpty)
                        const StatoVuoto(Icons.receipt_long_rounded, 'Nessun preventivo',
                            'Tocca «Nuovo preventivo» per fare il primo')
                      else
                        for (final p in tutti.take(5))
                          Padding(padding: const EdgeInsets.only(bottom: 10), child: VocePreventivo(p)),
                    ],
                  ),
                ),
              ),
            ]),
          );
        },
      );
}

String _nomeMese(int m) => const [
      'gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno',
      'luglio', 'agosto', 'settembre', 'ottobre', 'novembre', 'dicembre'
    ][m - 1];

class _Kpi extends StatelessWidget {
  const _Kpi(this.valore, this.etichetta, {this.onTap});

  final String valore, etichetta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: .10)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(valore,
                    maxLines: 1, style: const TextStyle(color: bianco, fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              Text(etichetta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: grigio300, fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
}

class _Rapida extends StatelessWidget {
  const _Rapida(this.testo, this.icona, this.colore, this.onTap);

  final String testo;
  final IconData icona;
  final Color colore;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: colore,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
            child: Column(children: [
              Icon(icona, color: bianco, size: 24),
              const SizedBox(height: 6),
              Text(testo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: bianco, fontSize: 12, fontWeight: FontWeight.w800, height: 1.15)),
            ]),
          ),
        ),
      );
}

class _Voce extends StatelessWidget {
  const _Voce({required this.icona, required this.colore, required this.titolo, required this.sotto, required this.onTap});

  final IconData icona;
  final Color colore;
  final String titolo, sotto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => CardTk(
        padding: const EdgeInsets.all(14),
        onTap: onTap,
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: colore.withValues(alpha: .13), borderRadius: BorderRadius.circular(14)),
            child: Icon(icona, color: colore),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titolo, style: const TextStyle(color: navy, fontSize: 14.5, fontWeight: FontWeight.w800)),
              Text(sotto,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: grigio500, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: grigio300),
        ]),
      );
}
