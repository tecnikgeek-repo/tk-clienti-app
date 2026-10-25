// Impostazioni: commissione agente, i tre file collegati (listino, clienti, preventivi) e intestazione del PDF.
// L'app parte vuota: i dati arrivano dai file collegati su Drive o Dropbox; se al collegamento il telefono
// è vuoto, li importa da sola. Poi ogni file si sincronizza da solo.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app.dart';
import '../dati/file_collegati.dart';
import '../dati/formati.dart';
import '../dati/impostazioni.dart';
import '../dati/modelli.dart';
import '../dati/sincronia.dart';
import '../tema.dart';

class SchermataImpostazioni extends StatefulWidget {
  const SchermataImpostazioni({super.key});

  @override
  State<SchermataImpostazioni> createState() => _SchermataImpostazioniState();
}

class _SchermataImpostazioniState extends State<SchermataImpostazioni> {
  late final _perc = TextEditingController(
      text: impostazioni.commissione.percentualeDefault > 0 ? percentuale(impostazioni.commissione.percentualeDefault) : '');
  late String _base = impostazioni.commissione.baseCalcolo;
  late final Intestazione _it = impostazioni.intestazione.copia();
  late final Map<String, TextEditingController> _campi = {
    for (final e in _it.perJson().entries) e.key: TextEditingController(text: '${e.value ?? ''}'),
  };

  Future<void> _esito(Esito e, {bool finestra = false}) async {
    if (!mounted) return;
    if (finestra) {
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          icon: Icon(e.ok ? Icons.check_circle_rounded : Icons.error_rounded, color: e.ok ? verde : rosso, size: 40),
          title: Text(e.ok ? 'Fatto' : 'Non riuscito'),
          content: Text(e.messaggio),
          actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('OK'))],
        ),
      );
    } else {
      avviso(context, e.messaggio);
    }
    if (mounted) setState(() {});
  }

  Future<void> _prova(Future<Esito> Function() lavoro, {bool finestra = true}) async {
    try {
      await _esito(await lavoro(), finestra: finestra);
    } catch (e) {
      await _esito(Esito(false, 'Errore: $e'), finestra: true);
    }
  }

  // ───────────────────────── commissione ─────────────────────────

  Future<void> _salvaCommissione() async {
    await impostazioni.salvaCommissione(
        ConfigCommissione(percentualeDefault: leggiNumero(_perc.text), baseCalcolo: _base));
    if (mounted) avviso(context, 'Commissione salvata');
  }

  // ───────────────────────── intestazione ─────────────────────────

  Future<void> _salvaIntestazione() async {
    final j = {for (final e in _campi.entries) e.key: e.value.text.trim()};
    j['provincia'] = (j['provincia'] ?? '').toUpperCase();
    await impostazioni.salvaIntestazione(Intestazione.daJson(j));
    // l'intestazione viaggia nel file dei clienti
    sincronia.pianifica(Dominio.clienti);
    if (mounted) avviso(context, 'Intestazione salvata');
  }

  // ───────────────────────── listino ─────────────────────────

  static const _tipiListino = [
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-excel',
    'text/csv',
    'text/comma-separated-values',
    'text/plain',
    '*/*',
  ];

  Future<void> _collegaListino() async {
    final f = await scegliFile(_tipiListino, scrittura: true);
    if (f == null) return;
    await _prova(() => sincronia.collegaListino(f));
  }

  Future<void> _svuotaMagazzino() async {
    if (!await conferma(
        context,
        'Svuotare il magazzino?',
        'Cancella tutti i ${archivio.nArticoli} articoli dal telefono. Clienti e preventivi non si toccano. '
            'Puoi ricaricare i prodotti dal file del listino.',
        si: 'Svuota')) {
      return;
    }
    await archivio.eliminaTuttiArticoli();
    if (mounted) avviso(context, 'Magazzino svuotato');
  }

  // ───────────────────────── clienti / preventivi ─────────────────────────

  Future<void> _collegaEsistente(Dominio d) async {
    final f = await scegliFile(const ['application/json', 'application/octet-stream', 'text/plain', '*/*'],
        scrittura: true);
    if (f == null) return;
    await _prova(() => sincronia.collegaEsistente(d, f));
  }

  Future<void> _creaNuovo(Dominio d) async {
    final f = await creaFile('${d.name}.json', 'application/json');
    if (f == null) return;
    await _prova(() => sincronia.collegaNuovo(d, f));
  }

  Future<void> _scarica(Dominio d) async {
    final cfg = impostazioni.file(d);
    final cosa = d == Dominio.clienti
        ? 'I clienti e l\'intestazione del PDF del telefono verranno SOSTITUITI. Articoli e preventivi restano.'
        : 'Preventivi, righe e movimenti del telefono verranno SOSTITUITI. Clienti e articoli restano.';
    if (!await conferma(context, 'Scaricare dal file?', 'Legge «${cfg.nome}» dal cloud. $cosa', si: 'Scarica', pericolo: false)) {
      return;
    }
    await _prova(() => sincronia.scarica(d));
  }

  /// iPhone: importa scegliendo il file (non resta collegato).
  Future<void> _importaIos(Dominio d) async {
    final f = await FilePicker.pickFile();
    if (f == null) return;
    final dati = await f.readAsBytes();
    if (d == Dominio.listino) {
      await _prova(() => sincronia.importaListinoByte(dati, f.name));
    } else {
      if (!mounted) return;
      if (!await conferma(context, 'Importare «${f.name}»?', 'I dati del telefono di questo tipo verranno sostituiti.',
          si: 'Importa', pericolo: false)) {
        return;
      }
      await _prova(() => sincronia.importaByte(d, dati));
    }
  }

  /// iPhone: esporta il file e lo condivide (Salva su File, iCloud, Dropbox…).
  Future<void> _esportaIos(Dominio d) async {
    final c = await sincronia.contenuto(d);
    final f = File('${(await getTemporaryDirectory()).path}/${d.name}.json');
    await f.writeAsBytes(c.byte, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'application/json')]));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([archivio, sincronia]),
        builder: (context, _) => Scaffold(
          body: Column(children: [
            TestataSemplice(titolo: 'Impostazioni', indietro: () => Navigator.pop(context)),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(14, 14, 14, spazioFondo(context)),
                children: [
                  _cardCommissione(),
                  const SizedBox(height: 12),
                  if (!fileCollegabili) ...[_avvisoIos(), const SizedBox(height: 12)],
                  _cardListino(),
                  const SizedBox(height: 12),
                  _cardDati(
                    Dominio.clienti,
                    titolo: 'Clienti',
                    descrizione:
                        'File con la tua anagrafica clienti e l\'intestazione dei PDF. Cambiando telefono ritrovi tutto collegando lo stesso file.',
                    icona: Icons.people_alt_rounded,
                    colore: accento,
                    contatore: ('Clienti nel telefono', '${archivio.clienti.length}'),
                  ),
                  const SizedBox(height: 12),
                  _cardDati(
                    Dominio.preventivi,
                    titolo: 'Preventivi',
                    descrizione:
                        'File con i tuoi preventivi, le righe e i movimenti di magazzino. Tienilo nel TUO Drive o Dropbox personale.',
                    icona: Icons.receipt_long_rounded,
                    colore: verde,
                    contatore: ('Preventivi nel telefono', '${archivio.preventivi.length}'),
                  ),
                  const SizedBox(height: 12),
                  _cardIntestazione(),
                ],
              ),
            ),
          ]),
        ),
      );

  Widget _avvisoIos() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: accentoChiaro, borderRadius: BorderRadius.circular(14)),
        child: const Row(children: [
          Icon(Icons.info_outline_rounded, color: accentoScuro),
          SizedBox(width: 10),
          Expanded(
            child: Text(
                'Su iPhone i file non restano collegati: importali scegliendoli dall\'app File ed esportali con «Esporta».',
                style: TextStyle(color: accentoScuro, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ]),
      );

  Widget _cardCommissione() => CardTk(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const TitoloCard('Commissione agente', icona: Icons.percent_rounded, colore: verde),
          campo('Percentuale predefinita (%)', _perc, suggerimento: 'es. 5', tastiera: tastieraNumeri, sotto: 6),
          const Text(
              'Vale per tutti i clienti. Per un cliente con una percentuale diversa la imposti nella sua scheda.',
              style: TextStyle(color: grigio500, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          const TitoloSezione('Calcola la commissione su'),
          const SizedBox(height: 8),
          Scelta<String>(
            voci: const [(baseImponibile, 'Imponibile netto'), (baseTotale, 'Totale IVA inclusa')],
            valore: _base,
            colore: accento,
            onCambia: (v) => setState(() => _base = v),
          ),
          const SizedBox(height: 12),
          BottoneTk(testo: 'Salva commissione', icona: Icons.check_rounded, onTap: _salvaCommissione),
        ]),
      );

  Widget _intestazioneCard(String titolo, String descrizione, IconData icona, Color colore, bool occupato) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (occupato) ...[
          LinearProgressIndicator(color: colore, backgroundColor: colore.withValues(alpha: .15)),
          const SizedBox(height: 10),
        ],
        TitoloCard(titolo, icona: icona, colore: colore),
        Text(descrizione, style: const TextStyle(color: grigio500, fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
      ]);

  Widget _interruttore(ConfigFile cfg, Dominio d, Color colore) => Row(children: [
        const Expanded(
            child: Text('Sincronizzazione automatica',
                style: TextStyle(color: navy, fontSize: 13.5, fontWeight: FontWeight.w700))),
        Switch(
          value: cfg.abilitato,
          activeTrackColor: colore,
          onChanged: (v) async {
            cfg.abilitato = v;
            await impostazioni.salvaFile(d, cfg);
            setState(() {});
          },
        ),
      ]);

  Widget _cardListino() {
    final cfg = impostazioni.file(Dominio.listino);
    final occupato = sincronia.occupati.contains(Dominio.listino);
    return CardTk(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _intestazioneCard(
            'Listino prodotti',
            'File Excel o CSV su Drive, Dropbox o nel telefono. Lo modifichi sul PC, l\'app lo rilegge da sola.',
            Icons.inventory_2_rounded,
            ambra,
            occupato),
        if (!fileCollegabili) ...[
          InfoRiga('Articoli nel telefono', '${archivio.nArticoli}'),
          const SizedBox(height: 10),
          BottoneTk(testo: 'Importa Excel o CSV', icona: Icons.file_download_rounded, onTap: () => _importaIos(Dominio.listino)),
        ] else if (cfg.collegato) ...[
          InfoRiga('File', cfg.nome),
          InfoRiga('Ultimo aggiornamento', cfg.ultimo > 0 ? dataOra(cfg.ultimo) : '—'),
          InfoRiga('Articoli nel telefono', '${archivio.nArticoli}'),
          _interruttore(cfg, Dominio.listino, ambra),
          const SizedBox(height: 6),
          if (cfg.nome.toLowerCase().endsWith('.xlsx')) ...[
            BottoneTk(
                testo: 'Carica nel file ora',
                icona: Icons.cloud_upload_rounded,
                onTap: occupato ? null : () => _prova(() => sincronia.salva(Dominio.listino))),
            const SizedBox(height: 8),
          ],
          TastoSecondario('Scarica dal file', Icons.cloud_download_rounded,
              occupato ? null : () => _prova(() => sincronia.listinoDaFile()),
              colore: ambraScuro),
          const SizedBox(height: 8),
          TastoSecondario('Cambia file collegato', Icons.swap_horiz_rounded, occupato ? null : _collegaListino),
          TextButton(
            onPressed: occupato
                ? null
                : () async {
                    await impostazioni.scollega(Dominio.listino);
                    if (mounted) setState(() {});
                  },
            child: const Text('Scollega il file', style: TextStyle(color: rosso)),
          ),
        ] else
          BottoneTk(testo: 'Collega file esistente', icona: Icons.link_rounded, onTap: occupato ? null : _collegaListino),
        if (archivio.nArticoli > 0)
          Center(
            child: TextButton.icon(
              onPressed: occupato ? null : _svuotaMagazzino,
              icon: const Icon(Icons.delete_sweep_rounded, color: rosso),
              label: Text('Svuota magazzino (${archivio.nArticoli} articoli)', style: const TextStyle(color: rosso)),
            ),
          ),
      ]),
    );
  }

  Widget _cardDati(Dominio d,
      {required String titolo,
      required String descrizione,
      required IconData icona,
      required Color colore,
      required (String, String) contatore}) {
    final cfg = impostazioni.file(d);
    final occupato = sincronia.occupati.contains(d);
    return CardTk(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _intestazioneCard(titolo, descrizione, icona, colore, occupato),
        if (!fileCollegabili) ...[
          InfoRiga(contatore.$1, contatore.$2),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TastoSecondario('Importa', Icons.file_download_rounded, () => _importaIos(d))),
            const SizedBox(width: 8),
            Expanded(child: TastoSecondario('Esporta', Icons.ios_share_rounded, () => _esportaIos(d))),
          ]),
        ] else if (cfg.collegato) ...[
          InfoRiga('File', cfg.nome),
          InfoRiga('Ultimo salvataggio', cfg.ultimo > 0 ? dataOra(cfg.ultimo) : '—'),
          InfoRiga(contatore.$1, contatore.$2),
          _interruttore(cfg, d, colore),
          const SizedBox(height: 6),
          BottoneTk(
              testo: 'Carica nel file ora',
              icona: Icons.cloud_upload_rounded,
              onTap: occupato ? null : () => _prova(() => sincronia.salva(d))),
          const SizedBox(height: 8),
          TastoSecondario('Scarica dal file', Icons.cloud_download_rounded, occupato ? null : () => _scarica(d),
              colore: colore),
          const SizedBox(height: 8),
          TastoSecondario('Cambia file collegato', Icons.swap_horiz_rounded, occupato ? null : () => _collegaEsistente(d)),
          TextButton(
            onPressed: occupato
                ? null
                : () async {
                    await impostazioni.scollega(d);
                    if (mounted) setState(() {});
                  },
            child: const Text('Scollega il file', style: TextStyle(color: rosso)),
          ),
        ] else ...[
          BottoneTk(
              testo: 'Collega file esistente', icona: Icons.link_rounded, onTap: occupato ? null : () => _collegaEsistente(d)),
          const SizedBox(height: 8),
          TastoSecondario('Crea un file nuovo', Icons.note_add_rounded, occupato ? null : () => _creaNuovo(d),
              colore: colore),
        ],
      ]),
    );
  }

  Widget _cardIntestazione() {
    Widget c(String chiave, String etichetta, {TextInputType? tastiera, bool maiuscole = false, int righe = 1}) =>
        campo(etichetta, _campi[chiave]!, tastiera: tastiera, tuttoMaiuscolo: maiuscole, righe: righe);
    return CardTk(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const TitoloCard('Intestazione dei preventivi PDF', icona: Icons.picture_as_pdf_rounded, colore: rosso),
        const Text('I dati della TUA attività: compaiono in cima al PDF e in fondo. Viaggiano nel file dei clienti.',
            style: TextStyle(color: grigio500, fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        c('ragioneSociale', 'Ragione sociale / Nome'),
        c('indirizzo', 'Indirizzo (via e civico)'),
        Row(children: [
          Expanded(child: c('cap', 'CAP', tastiera: TextInputType.number)),
          const SizedBox(width: 10),
          Expanded(child: c('provincia', 'Prov.', maiuscole: true)),
        ]),
        c('citta', 'Città'),
        c('piva', 'Partita IVA'),
        c('codiceFiscale', 'Codice fiscale', maiuscole: true),
        c('telefono', 'Telefono', tastiera: TextInputType.phone),
        c('email', 'Email', tastiera: TextInputType.emailAddress),
        c('pec', 'PEC', tastiera: TextInputType.emailAddress),
        c('sito', 'Sito web', tastiera: TextInputType.url),
        c('iban', 'IBAN (nel PDF, sotto «Pagamento»)', maiuscole: true),
        c('noteFooter', 'Nota in fondo al PDF (es. condizioni)', righe: 2),
        BottoneTk(testo: 'Salva intestazione', icona: Icons.check_rounded, onTap: _salvaIntestazione),
      ]),
    );
  }
}
