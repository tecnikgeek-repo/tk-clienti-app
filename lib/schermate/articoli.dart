// Magazzino: elenco articoli con ricerca (a pagine: il listino può avere migliaia di righe),
// import di un CSV al volo, scheda articolo con prezzi, giacenza e carico/scarico.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../dati/file_collegati.dart';
import '../dati/formati.dart';
import '../dati/impostazioni.dart';
import '../dati/listino.dart';
import '../dati/modelli.dart';
import '../tema.dart';

class SchermataArticoli extends StatefulWidget {
  const SchermataArticoli({super.key});

  @override
  State<SchermataArticoli> createState() => _SchermataArticoliState();
}

class _SchermataArticoliState extends State<SchermataArticoli> {
  static const _pagina = 150;
  String _cerca = '';
  int _limite = _pagina;
  List<Articolo> _articoli = const [];
  bool _importo = false;
  int _giro = -1;
  Timer? _attesa;
  final _scorrimento = ScrollController();

  @override
  void initState() {
    super.initState();
    archivio.addListener(_seCambiato);
    _scorrimento.addListener(() {
      // vicino al fondo e pagina piena: carica la pagina dopo
      if (_scorrimento.position.extentAfter < 600 && _articoli.length >= _limite) {
        _limite += _pagina;
        _leggi();
      }
    });
    _leggi();
  }

  @override
  void dispose() {
    archivio.removeListener(_seCambiato);
    _attesa?.cancel();
    _scorrimento.dispose();
    super.dispose();
  }

  void _seCambiato() {
    if (_giro != archivio.giro) _leggi();
  }

  Future<void> _leggi() async {
    _giro = archivio.giro;
    final r = await archivio.cercaArticoli(_cerca, limite: _limite);
    if (mounted) setState(() => _articoli = r);
  }

  void _cambiaRicerca(String t) {
    _attesa?.cancel();
    _attesa = Timer(const Duration(milliseconds: 220), () {
      _cerca = t;
      _limite = _pagina;
      _leggi();
    });
  }

  /// Import di un CSV scelto al volo (senza collegarlo): aggiorna o aggiunge gli articoli.
  Future<void> _importaCsv() async {
    Uint8List? dati;
    String nome = '';
    if (Platform.isAndroid) {
      final f = await scegliFile(const ['text/csv', 'text/comma-separated-values', 'text/plain', '*/*']);
      if (f == null) return;
      nome = f.nome;
      setState(() => _importo = true);
      try {
        dati = await leggiFile(f.uri);
      } catch (e) {
        if (mounted) avviso(context, 'Non riesco a leggere il file: $e');
      }
    } else {
      final f = await FilePicker.pickFile();
      if (f == null) return;
      nome = f.name;
      dati = await f.readAsBytes();
    }
    if (dati == null) {
      if (mounted) setState(() => _importo = false);
      return;
    }
    setState(() => _importo = true);
    final lettura = leggiListino(dati, nome.toLowerCase().endsWith('.xlsx') ? nome : 'file.csv',
        await archivio.articoliPerCodice());
    final scritti = await archivio.scriviListino(lettura.articoli);
    if (lettura.articoli.isNotEmpty) archivio.onModifica?.call(Dominio.listino);
    if (!mounted) return;
    setState(() => _importo = false);
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Importazione completata'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Righe lette: ${lettura.totali}'),
          Text('Articoli importati o aggiornati: $scritti'),
          if (lettura.errori.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Errori: ${lettura.errori.length}', style: const TextStyle(color: rosso, fontWeight: FontWeight.w700)),
            for (final e in lettura.errori.take(5)) Text('• $e', style: const TextStyle(fontSize: 12)),
          ],
        ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton:
            pulsanteNuovo('Nuovo articolo', () => vai(context, const SchermataArticolo()), colore: ambra),
        body: Column(children: [
          Testata(
            titolo: 'Magazzino',
            sottotitolo: _importo
                ? 'Importazione in corso…'
                : _cerca.trim().isEmpty
                    ? '${archivio.nArticoli} articoli'
                    : '${_articoli.length}${_articoli.length >= _limite ? '+' : ''} risultati',
            indietro: () => Navigator.pop(context),
            logo: false,
            azioni: [AzioneTk(Icons.file_download_rounded, 'Importa un CSV', _importo ? null : _importaCsv)],
            sotto: TextField(
              onChanged: _cambiaRicerca,
              decoration: const InputDecoration(
                  hintText: 'Cerca per codice, descrizione, EAN…', prefixIcon: Icon(Icons.search_rounded), isDense: true),
            ),
          ),
          if (_importo) const LinearProgressIndicator(color: ambra),
          Expanded(
            child: RefreshIndicator(
              color: accento,
              onRefresh: () async {
                final esito = await sincronia.sincronizzaTutto();
                if (context.mounted) avviso(context, esito);
              },
              child: _articoli.isEmpty
                  ? ListView(children: [
                      _cerca.trim().isEmpty
                          ? const StatoVuoto(Icons.inventory_2_rounded, 'Nessun articolo',
                              'Collega il file del listino nelle Impostazioni per caricare i prodotti dal cloud')
                          : const StatoVuoto(Icons.search_off_rounded, 'Nessun risultato', 'Prova un altro codice o parola'),
                    ])
                  : ListView.separated(
                      controller: _scorrimento,
                      padding: EdgeInsets.fromLTRB(14, 14, 14, spazioFondo(context, pulsante: true)),
                      itemCount: _articoli.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _RigaArticolo(_articoli[i]),
                    ),
            ),
          ),
        ]),
      );
}

class _RigaArticolo extends StatelessWidget {
  const _RigaArticolo(this.a);

  final Articolo a;

  @override
  Widget build(BuildContext context) => CardTk(
        padding: const EdgeInsets.all(12),
        onTap: () => vai(context, SchermataArticolo(id: a.id)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CodiceArticolo(a.codice),
            const SizedBox(width: 8),
            Expanded(
              child: Text(euro(a.prezzoVendita),
                  style: const TextStyle(color: accentoScuro, fontSize: 14, fontWeight: FontWeight.w800)),
            ),
            if (a.origine == origineManuale) ...[const Pilla('a mano', ambra, piena: false), const SizedBox(width: 6)],
            if (a.giacenza != 0)
              Pilla('${numero(a.giacenza)} ${a.unitaMisura}', a.giacenza > 0 ? verde : rosso, piena: false),
          ]),
          const SizedBox(height: 5),
          Text(a.descrizione,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: grigio500, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      );
}

// ───────────────────────── scheda articolo ─────────────────────────

class SchermataArticolo extends StatefulWidget {
  const SchermataArticolo({super.key, this.id = 0});

  final int id;

  @override
  State<SchermataArticolo> createState() => _SchermataArticoloState();
}

class _SchermataArticoloState extends State<SchermataArticolo> {
  Articolo _a = Articolo();
  List<Movimento> _movimenti = const [];
  bool _caricato = false;
  final _codice = TextEditingController();
  final _descrizione = TextEditingController();
  final _ean = TextEditingController();
  final _um = TextEditingController(text: 'PZ');
  final _listino = TextEditingController();
  final _rivenditore = TextEditingController();
  final _giacenza = TextEditingController(text: '0');
  final _delta = TextEditingController();
  final _causale = TextEditingController();
  String? _erroreCodice;

  bool get _nuovo => widget.id == 0;

  @override
  void initState() {
    super.initState();
    _carica();
  }

  Future<void> _carica() async {
    if (!_nuovo) {
      final a = await archivio.articolo(widget.id);
      if (a != null) {
        _a = a;
        _codice.text = a.codice;
        _descrizione.text = a.descrizione;
        _ean.text = a.ean13;
        _um.text = a.unitaMisura;
        _listino.text = a.prezzoListino > 0 ? perCampo(a.prezzoListino) : '';
        _rivenditore.text = a.prezzoRivenditore > 0 ? perCampo(a.prezzoRivenditore) : '';
        _giacenza.text = perCampo(a.giacenza);
        _movimenti = await archivio.movimenti(a.id);
      }
    }
    if (mounted) setState(() => _caricato = true);
  }

  Future<void> _salva() async {
    if (_codice.text.trim().isEmpty) {
      setState(() => _erroreCodice = 'Scrivi il codice');
      return;
    }
    _a
      ..codice = _codice.text.trim()
      ..descrizione = _descrizione.text.trim()
      ..ean13 = _ean.text.trim()
      ..unitaMisura = _um.text.trim().isEmpty ? 'PZ' : _um.text.trim().toUpperCase()
      ..prezzoListino = leggiNumero(_listino.text)
      ..prezzoRivenditore = leggiNumero(_rivenditore.text)
      ..giacenza = leggiNumero(_giacenza.text);
    final id = await archivio.salvaArticolo(_a);
    if (!mounted) return;
    if (id == null) {
      setState(() => _erroreCodice = 'Questo codice è già di un altro articolo');
      return;
    }
    Navigator.pop(context);
  }

  Future<void> _movimento() async {
    final delta = leggiNumero(_delta.text);
    if (delta == 0) {
      avviso(context, 'Scrivi la quantità: positiva per il carico, negativa per lo scarico');
      return;
    }
    final tipo = delta >= 0 ? 'CARICO' : 'SCARICO';
    final a = await archivio.movimentaGiacenza(
        _a, delta, tipo, _causale.text.trim().isEmpty ? '$tipo manuale' : _causale.text.trim());
    final m = await archivio.movimenti(a.id);
    if (!mounted) return;
    setState(() {
      _a = a;
      _movimenti = m;
      _giacenza.text = perCampo(a.giacenza);
      _delta.clear();
      _causale.clear();
    });
    avviso(context, '$tipo registrato: giacenza ${numero(a.giacenza)} ${a.unitaMisura}');
  }

  Future<void> _elimina() async {
    if (!await conferma(context, 'Eliminare l\'articolo?', 'L\'articolo ${_a.codice} sparisce con tutti i suoi movimenti.')) {
      return;
    }
    await archivio.eliminaArticolo(_a);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (!_caricato) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      body: Column(children: [
        TestataSemplice(
          titolo: _nuovo ? 'Nuovo articolo' : _a.codice,
          indietro: () => Navigator.pop(context),
          azioni: [if (!_nuovo) AzioneTk(Icons.delete_outline_rounded, 'Elimina', _elimina)],
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(14, 14, 14, spazioFondo(context)),
            children: [
              if (!_nuovo && _a.origine == origineListino)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: accentoChiaro, borderRadius: BorderRadius.circular(14)),
                  child: const Row(children: [
                    Icon(Icons.sync_rounded, color: accentoScuro, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('Articolo del listino: se cambia nel file, la sincronizzazione lo aggiorna.',
                          style: TextStyle(color: accentoScuro, fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                  ]),
                ),
              CardTk(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const TitoloCard('Dati articolo', icona: Icons.inventory_2_rounded, colore: ambra),
                  campo('Codice', _codice,
                      tuttoMaiuscolo: true,
                      errore: _erroreCodice,
                      onChanged: (_) => setState(() => _erroreCodice = null)),
                  campo('Descrizione', _descrizione, righe: 2),
                  Row(children: [
                    Expanded(flex: 3, child: campo('EAN13', _ean, tastiera: TextInputType.number, sotto: 0)),
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: campo('U.M.', _um, tuttoMaiuscolo: true, sotto: 0)),
                  ]),
                ]),
              ),
              const SizedBox(height: 12),
              CardTk(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const TitoloCard('Prezzi', icona: Icons.euro_rounded),
                  campo('Prezzo di listino €', _listino, tastiera: tastieraNumeri),
                  campo('Prezzo rivenditore € (quello del preventivo)', _rivenditore, tastiera: tastieraNumeri, sotto: 0),
                ]),
              ),
              const SizedBox(height: 12),
              CardTk(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const TitoloCard('Giacenza', icona: Icons.warehouse_rounded, colore: verde),
                  campo('Giacenza attuale (si sovrascrive)', _giacenza, tastiera: tastieraNumeri, sotto: _nuovo ? 0 : 12),
                  if (!_nuovo) ...[
                    const TitoloSezione('Carico / scarico rapido'),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: campo('Quantità (+/−)', _delta, tastiera: tastieraNumeri)),
                      const SizedBox(width: 10),
                      Expanded(child: campo('Causale', _causale)),
                    ]),
                    BottoneTk(testo: 'Registra movimento', icona: Icons.swap_vert_rounded, chiaro: true, onTap: _movimento),
                  ],
                ]),
              ),
              if (_movimenti.isNotEmpty) ...[
                const SizedBox(height: 12),
                CardTk(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    TitoloCard('Movimenti (${_movimenti.length})', icona: Icons.history_rounded),
                    for (final m in _movimenti.take(20))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Icon(m.quantita >= 0 ? Icons.south_west_rounded : Icons.north_east_rounded,
                              color: m.quantita >= 0 ? verde : rosso, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(m.causale.isEmpty ? m.tipo : m.causale,
                                  style: const TextStyle(color: navy, fontSize: 13, fontWeight: FontWeight.w700)),
                              Text(dataOra(m.data),
                                  style: const TextStyle(color: grigio500, fontSize: 11.5, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                          Text('${m.quantita > 0 ? '+' : ''}${numero(m.quantita)} → ${numero(m.giacenzaNuova)}',
                              style: TextStyle(
                                  color: m.quantita >= 0 ? verdeScuro : rosso, fontSize: 12.5, fontWeight: FontWeight.w800)),
                        ]),
                      ),
                  ]),
                ),
              ],
              const SizedBox(height: 16),
              BottoneTk(testo: 'Salva', icona: Icons.check_rounded, onTap: _salva),
            ],
          ),
        ),
      ]),
    );
  }
}
