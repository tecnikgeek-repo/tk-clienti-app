// Preventivi: elenco e dettaglio con PDF (condividi, WhatsApp, email, stampa), stato e commissione agente.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app.dart';
import '../dati/file_collegati.dart';
import '../dati/formati.dart';
import '../dati/modelli.dart';
import '../dati/pdf_preventivo.dart';
import '../tema.dart';
import 'clienti.dart';
import 'preventivo_modulo.dart';

// ───────────────────────── elenco ─────────────────────────

class SchermataPreventivi extends StatefulWidget {
  const SchermataPreventivi({super.key});

  @override
  State<SchermataPreventivi> createState() => _SchermataPreventiviState();
}

class _SchermataPreventiviState extends State<SchermataPreventivi> {
  String _cerca = '';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: archivio,
        builder: (context, _) {
          final t = _cerca.trim().toLowerCase();
          final lista = archivio.preventivi
              .where((p) =>
                  t.isEmpty ||
                  p.numero.toLowerCase().contains(t) ||
                  archivio.nomeCliente(p.clienteId).toLowerCase().contains(t))
              .toList();
          final totale = lista.fold<double>(0, (s, p) => s + p.totale);
          return Scaffold(
            floatingActionButton: pulsanteNuovo(
                'Nuovo preventivo', () => vai(context, const SchermataModuloPreventivo()),
                colore: verde),
            body: Column(children: [
              Testata(
                titolo: 'Preventivi',
                sottotitolo: '${lista.length} preventivi · ${euro(totale)}',
                indietro: () => Navigator.pop(context),
                logo: false,
                sotto: TextField(
                  onChanged: (v) => setState(() => _cerca = v),
                  decoration: const InputDecoration(
                      hintText: 'Cerca per numero o cliente…', prefixIcon: Icon(Icons.search_rounded), isDense: true),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: accento,
                  onRefresh: () async {
                    final esito = await sincronia.sincronizzaTutto();
                    if (context.mounted) avviso(context, esito);
                  },
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(14, 14, 14, spazioFondo(context, pulsante: true)),
                    children: [
                      if (lista.isEmpty)
                        archivio.preventivi.isEmpty
                            ? const StatoVuoto(Icons.receipt_long_rounded, 'Nessun preventivo',
                                'Tocca «Nuovo preventivo» per fare il primo')
                            : const StatoVuoto(Icons.search_off_rounded, 'Nessun risultato', 'Cambia la ricerca')
                      else
                        for (final p in lista)
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

/// Card di un preventivo negli elenchi.
class VocePreventivo extends StatelessWidget {
  const VocePreventivo(this.p, {super.key, this.mostraCliente = true});

  final Preventivo p;
  final bool mostraCliente;

  @override
  Widget build(BuildContext context) => CardTk(
        padding: const EdgeInsets.all(14),
        onTap: () => vai(context, SchermataPreventivo(p.id)),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: accentoChiaro, borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.receipt_long_rounded, color: accentoScuro),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text('N° ${p.numero}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: navy, fontSize: 14.5, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 8),
                pillaStato(p.stato),
              ]),
              Text(mostraCliente ? '${archivio.nomeCliente(p.clienteId)} · ${data(p.data)}' : data(p.data),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: grigio500, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(width: 8),
          Text(euro(p.totale), style: const TextStyle(color: accentoScuro, fontSize: 14.5, fontWeight: FontWeight.w800)),
        ]),
      );
}

// ───────────────────────── dettaglio ─────────────────────────

class SchermataPreventivo extends StatefulWidget {
  const SchermataPreventivo(this.id, {super.key});

  final int id;

  @override
  State<SchermataPreventivo> createState() => _SchermataPreventivoState();
}

class _SchermataPreventivoState extends State<SchermataPreventivo> {
  PreventivoConRighe? _pcr;
  bool _caricato = false;
  bool _generando = false;
  int _giro = -1;

  @override
  void initState() {
    super.initState();
    archivio.addListener(_ricarica);
    _ricarica();
  }

  @override
  void dispose() {
    archivio.removeListener(_ricarica);
    super.dispose();
  }

  Future<void> _ricarica() async {
    if (_giro == archivio.giro) return;
    _giro = archivio.giro;
    final pcr = await archivio.preventivoConRighe(widget.id);
    if (mounted) {
      setState(() {
        _pcr = pcr;
        _caricato = true;
      });
    }
  }

  /// Crea il PDF nella cartella temporanea e ne restituisce il percorso.
  Future<String?> _pdf() async {
    final pcr = _pcr;
    if (pcr == null) return null;
    final c = archivio.cliente(pcr.preventivo.clienteId);
    if (c == null) {
      avviso(context, 'Il cliente di questo preventivo non c\'è più');
      return null;
    }
    setState(() => _generando = true);
    try {
      final byte = await creaPdfPreventivo(pcr.preventivo, c, pcr.righe, impostazioni.intestazione,
          fontNormale: await rootBundle.load('assets/font/Roboto-Regular.ttf'),
          fontGrassetto: await rootBundle.load('assets/font/Roboto-Bold.ttf'));
      final cartella = Directory('${(await getTemporaryDirectory()).path}/preventivi')..createSync(recursive: true);
      final f = File('${cartella.path}/${nomeFilePdf(pcr.preventivo, c)}');
      await f.writeAsBytes(byte, flush: true);
      return f.path;
    } catch (e) {
      if (mounted) avviso(context, 'PDF non creato: $e');
      return null;
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  Future<void> _condividi({bool whatsapp = false, bool email = false}) async {
    final percorso = await _pdf();
    if (percorso == null || !mounted) return;
    final p = _pcr!.preventivo;
    final c = archivio.cliente(p.clienteId)!;
    final saluto = c.nome.trim().isEmpty ? c.nominativo : c.nome.trim();
    final testo = email
        ? 'Buongiorno $saluto,\n\nin allegato il preventivo richiesto.\n\nCordiali saluti'
        : whatsapp
            ? 'Buongiorno, in allegato il preventivo ${p.numero}.'
            : null;
    try {
      if (Platform.isAndroid) {
        await condividiFile(percorso,
            oggetto: 'Preventivo ${p.numero}',
            testo: testo,
            pacchetti: whatsapp ? const ['com.whatsapp', 'com.whatsapp.w4b'] : const [],
            email: email ? c.email : null,
            titolo: whatsapp ? 'Invia con…' : (email ? 'Email' : 'Condividi preventivo'));
      } else {
        await SharePlus.instance.share(ShareParams(
            files: [XFile(percorso, mimeType: 'application/pdf')], subject: 'Preventivo ${p.numero}', text: testo));
      }
    } catch (e) {
      if (mounted) avviso(context, 'Condivisione non riuscita: $e');
    }
  }

  Future<void> _stampa() async {
    final percorso = await _pdf();
    if (percorso == null) return;
    try {
      if (Platform.isAndroid) {
        await apriFileLocale(percorso);
      } else {
        await OpenFilex.open(percorso, type: 'application/pdf');
      }
    } catch (e) {
      if (mounted) avviso(context, 'Non riesco ad aprire il PDF: $e');
    }
  }

  Future<void> _cambiaStato(Preventivo p) async {
    final nuovo = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (d) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('Stato del preventivo', style: TextStyle(color: navy, fontSize: 16, fontWeight: FontWeight.w800)),
          ),
          for (final s in statiPreventivo)
            ListTile(
              leading: pillaStato(s),
              trailing: s == p.stato ? const Icon(Icons.check_rounded, color: accento) : null,
              onTap: () => Navigator.pop(d, s),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (nuovo != null && nuovo != p.stato) await archivio.cambiaStato(p, nuovo);
  }

  Future<void> _elimina(Preventivo p) async {
    if (!await conferma(context, 'Eliminare il preventivo?', 'Il preventivo N° ${p.numero} sparisce. Non si può annullare.')) {
      return;
    }
    await archivio.eliminaPreventivo(p);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final pcr = _pcr;
    if (pcr == null) {
      return Scaffold(
        body: Column(children: [
          TestataSemplice(titolo: 'Preventivo', indietro: () => Navigator.pop(context)),
          Expanded(
            child: Center(
                child: _caricato ? const Text('Preventivo eliminato') : const CircularProgressIndicator()),
          ),
        ]),
      );
    }
    final p = pcr.preventivo;
    final c = archivio.cliente(p.clienteId);
    final cfg = impostazioni.commissione;
    final percAttuale = percentualeEffettiva(c?.commissionePerc ?? -1, cfg);
    final comm = commissionePreventivo(p, c?.commissionePerc ?? -1, cfg);
    return Scaffold(
      body: Column(children: [
        Testata(
          titolo: 'Preventivo ${p.numero}',
          sottotitolo: archivio.nomeCliente(p.clienteId),
          indietro: () => Navigator.pop(context),
          logo: false,
          azioni: [
            AzioneTk(Icons.edit_rounded, 'Modifica', () => vai(context, SchermataModuloPreventivo(preventivoId: p.id))),
            AzioneTk(Icons.delete_outline_rounded, 'Elimina', () => _elimina(p)),
          ],
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(14, 14, 14, spazioFondo(context)),
            children: [
              CardTk(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TitoloCard('Riepilogo',
                      icona: Icons.receipt_long_rounded,
                      destra: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => _cambiaStato(p),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            pillaStato(p.stato),
                            const Icon(Icons.expand_more_rounded, color: grigio400, size: 20),
                          ]))),
                  InfoRiga('Numero', p.numero),
                  InfoRiga('Data', data(p.data)),
                  InfoRiga('Validità', '${p.validita} giorni'),
                ]),
              ),
              if (c != null) ...[
                const SizedBox(height: 12),
                CardTk(
                  onTap: () => vai(context, SchermataCliente(c.id)),
                  child: Row(children: [
                    Avatar(c.nominativo),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c.nominativo.isEmpty ? '(senza nome)' : c.nominativo,
                            style: const TextStyle(color: navy, fontSize: 15, fontWeight: FontWeight.w800)),
                        if ('${c.telefono} ${c.email}'.trim().isNotEmpty)
                          Text([c.telefono, c.email].where((s) => s.trim().isNotEmpty).join(' · '),
                              style: const TextStyle(color: grigio500, fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: grigio300),
                  ]),
                ),
              ],
              const SizedBox(height: 12),
              CardTk(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TitoloCard('Righe (${pcr.righe.length})', icona: Icons.format_list_bulleted_rounded),
                  for (var i = 0; i < pcr.righe.length; i++) ...[
                    if (i > 0) const Divider(height: 16),
                    _RigaVista(pcr.righe[i]),
                  ],
                ]),
              ),
              const SizedBox(height: 12),
              CardTk(
                child: Column(children: [
                  InfoRiga('Imponibile', euro(p.totaleImponibile)),
                  if (p.scontoGlobale > 0) InfoRiga('Sconto applicato', '${percentuale(p.scontoGlobale)}%'),
                  InfoRiga('IVA ${percentuale(p.ivaPercentuale)}%', euro(p.totaleIva)),
                  const Divider(height: 18),
                  InfoRiga('TOTALE', euro(p.totale), colore: accentoScuro, grande: true),
                ]),
              ),
              if (percAttuale > 0 || p.commissionePerc >= 0) ...[
                const SizedBox(height: 12),
                CardTk(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const TitoloCard('Commissione agente', icona: Icons.percent_rounded, colore: verde),
                    InfoRiga('Percentuale',
                        '${percentuale(percAttuale)}% ${cfg.baseCalcolo == baseTotale ? 'sul totale' : 'sull\'imponibile'}'),
                    InfoRiga('COMMISSIONE', euro(comm), colore: verdeScuro, grande: true),
                    if (p.commissionePerc < 0)
                      const _Nota('Questo preventivo era stato fatto prima di impostare le commissioni.')
                    else if ((p.commissionePerc - percAttuale).abs() > 0.001)
                      _Nota('Preventivo fatto con commissione ${percentuale(p.commissionePerc)}%. '
                          'Qui è ricalcolata con la percentuale attuale (${percentuale(percAttuale)}%).'),
                  ]),
                ),
              ],
              if (p.note.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                CardTk(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const TitoloCard('Note', icona: Icons.sticky_note_2_rounded),
                    Text(p.note, style: const TextStyle(color: navy, fontSize: 13.5)),
                  ]),
                ),
              ],
              const SizedBox(height: 16),
              if (_generando)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4)),
                    SizedBox(width: 10),
                    Text('Preparo il PDF…', style: TextStyle(color: grigio500, fontWeight: FontWeight.w700)),
                  ]),
                ),
              BottoneTk(testo: 'Condividi PDF', icona: Icons.share_rounded, onTap: _generando ? null : _condividi),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: TastoSecondario('WhatsApp', Icons.chat_rounded,
                        _generando ? null : () => _condividi(whatsapp: true),
                        colore: const Color(0xFF128C4A))),
                const SizedBox(width: 8),
                Expanded(
                    child: TastoSecondario(
                        'Email', Icons.mail_rounded, _generando ? null : () => _condividi(email: true))),
                const SizedBox(width: 8),
                Expanded(child: TastoSecondario('Stampa', Icons.print_rounded, _generando ? null : _stampa)),
              ]),
            ],
          ),
        ),
      ]),
    );
  }
}

class _RigaVista extends StatelessWidget {
  const _RigaVista(this.r);

  final RigaPreventivo r;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (r.codice.trim().isNotEmpty) ...[CodiceArticolo(r.codice), const SizedBox(width: 8)],
          Expanded(
              child: Text(r.descrizione, style: const TextStyle(color: navy, fontSize: 13.5, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: Text(
                '${numero(r.quantita)} ${r.unitaMisura} × ${euro(r.prezzoUnitario)}'
                '${r.scontoPercentuale > 0 ? ' − ${percentuale(r.scontoPercentuale)}%' : ''}',
                style: const TextStyle(color: grigio500, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
          Text(euro(r.totaleRiga), style: const TextStyle(color: accentoScuro, fontSize: 13.5, fontWeight: FontWeight.w800)),
        ]),
      ]);
}

class _Nota extends StatelessWidget {
  const _Nota(this.testo);

  final String testo;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: ambraChiaro, borderRadius: BorderRadius.circular(10)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline_rounded, color: ambraScuro, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(testo, style: const TextStyle(color: ambraScuro, fontSize: 12, fontWeight: FontWeight.w600))),
        ]),
      );
}
