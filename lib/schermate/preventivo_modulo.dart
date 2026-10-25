// Modulo del preventivo: cliente, data, righe (dal listino o a mano), sconto, IVA, note.
import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../dati/formati.dart';
import '../dati/modelli.dart';
import '../tema.dart';
import 'clienti.dart';
import 'preventivi.dart';

class SchermataModuloPreventivo extends StatefulWidget {
  const SchermataModuloPreventivo({super.key, this.preventivoId = 0, this.clienteId = 0});

  final int preventivoId, clienteId;

  @override
  State<SchermataModuloPreventivo> createState() => _SchermataModuloPreventivoState();
}

/// Riga in modifica con i suoi campi di testo.
class _Riga {
  _Riga(this.r)
      : qta = TextEditingController(text: perCampo(r.quantita)),
        prezzo = TextEditingController(text: perCampo(r.prezzoUnitario)),
        sconto = TextEditingController(text: r.scontoPercentuale > 0 ? perCampo(r.scontoPercentuale) : '');

  final RigaPreventivo r;
  final TextEditingController qta, prezzo, sconto;

  void leggi() {
    final q = leggiNumero(qta.text);
    r
      ..quantita = q > 0 ? q : 1
      ..prezzoUnitario = leggiNumero(prezzo.text)
      ..scontoPercentuale = leggiNumero(sconto.text);
  }
}

class _SchermataModuloPreventivoState extends State<SchermataModuloPreventivo> {
  Preventivo _testa = Preventivo();
  Cliente? _cliente;
  final List<_Riga> _righe = [];
  final _iva = TextEditingController(text: '22');
  final _sconto = TextEditingController(text: '0');
  final _note = TextEditingController();
  bool _caricato = false;
  bool _salvando = false;

  bool get _nuovo => widget.preventivoId == 0;

  @override
  void initState() {
    super.initState();
    _carica();
  }

  Future<void> _carica() async {
    if (!_nuovo) {
      final pcr = await archivio.preventivoConRighe(widget.preventivoId);
      if (pcr != null) {
        _testa = pcr.preventivo.copia();
        _righe.addAll([for (final r in pcr.righe) _Riga(r.copia())]);
        _iva.text = perCampo(_testa.ivaPercentuale);
        _sconto.text = perCampo(_testa.scontoGlobale);
        _note.text = _testa.note;
        _cliente = archivio.cliente(_testa.clienteId);
      }
    } else if (widget.clienteId > 0) {
      _cliente = archivio.cliente(widget.clienteId);
      _testa.clienteId = widget.clienteId;
    }
    if (mounted) setState(() => _caricato = true);
  }

  (double, double, double) get _totali {
    for (final r in _righe) {
      r.leggi();
    }
    return calcolaTotali([for (final r in _righe) r.r], leggiNumero(_iva.text), leggiNumero(_sconto.text));
  }

  Future<void> _scegliCliente() async {
    final c = await showModalBottomSheet<Cliente>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _SceltaCliente(),
    );
    if (c != null) {
      setState(() {
        _cliente = c;
        _testa.clienteId = c.id;
      });
    }
  }

  Future<void> _scegliData() async {
    final d = DateTime.fromMillisecondsSinceEpoch(_testa.data);
    final scelta = await showDatePicker(
      context: context,
      initialDate: d,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (scelta != null) {
      // tiene l'ora del preventivo, cambia solo il giorno
      setState(() => _testa.data =
          DateTime(scelta.year, scelta.month, scelta.day, d.hour, d.minute, d.second).millisecondsSinceEpoch);
    }
  }

  Future<void> _aggiungiRiga() async {
    final r = await showModalBottomSheet<RigaPreventivo>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AggiungiRiga(),
    );
    if (r != null) setState(() => _righe.add(_Riga(r)));
  }

  Future<void> _salva() async {
    final c = _cliente;
    if (c == null || _righe.isEmpty || _salvando) return;
    setState(() => _salvando = true);
    final (imponibile, iva, totale) = _totali;
    _testa
      ..clienteId = c.id
      ..ivaPercentuale = leggiNumero(_iva.text)
      ..scontoGlobale = leggiNumero(_sconto.text)
      ..totaleImponibile = imponibile
      ..totaleIva = iva
      ..totale = totale
      ..note = _note.text.trim();
    // la commissione con cui è fatto si fissa solo alla creazione (serve alla nota nel dettaglio)
    if (_testa.id == 0) _testa.commissionePerc = percentualeEffettiva(c.commissionePerc, impostazioni.commissione);
    final id = await archivio.salvaPreventivo(_testa, [for (final r in _righe) r.r]);
    if (!mounted) return;
    if (_nuovo) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SchermataPreventivo(id)));
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_caricato) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final (imponibile, iva, totale) = _totali;
    final c = _cliente;
    return Scaffold(
      body: Column(children: [
        TestataSemplice(
            titolo: _nuovo ? 'Nuovo preventivo' : 'Modifica ${_testa.numero}', indietro: () => Navigator.pop(context)),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(14, 14, 14, spazioFondo(context)),
            children: [
              CardTk(
                onTap: _scegliCliente,
                child: Row(children: [
                  if (c == null)
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(color: rossoChiaro, borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.person_search_rounded, color: rosso),
                    )
                  else
                    Avatar(c.nominativo),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const TitoloSezione('Cliente'),
                      Text(c == null ? 'Scegli il cliente' : (c.nominativo.isEmpty ? '(senza nome)' : c.nominativo),
                          style: TextStyle(color: c == null ? rosso : navy, fontSize: 15.5, fontWeight: FontWeight.w800)),
                      if (c != null && c.indirizzoCompleto.isNotEmpty)
                        Text(c.indirizzoCompleto,
                            style: const TextStyle(color: grigio500, fontSize: 12.5, fontWeight: FontWeight.w600)),
                      if (c != null && c.piva.isNotEmpty)
                        Text('P.IVA ${c.piva}',
                            style: const TextStyle(color: grigio500, fontSize: 12, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  Text(c == null ? 'Cerca' : 'Cambia',
                      style: const TextStyle(color: accento, fontSize: 13, fontWeight: FontWeight.w800)),
                ]),
              ),
              const SizedBox(height: 12),
              CardTk(
                onTap: _scegliData,
                child: Row(children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: accentoChiaro, borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.event_rounded, color: accentoScuro),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const TitoloSezione('Data del preventivo'),
                      Text(data(_testa.data),
                          style: const TextStyle(color: navy, fontSize: 15.5, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                  const Text('Cambia', style: TextStyle(color: accento, fontSize: 13, fontWeight: FontWeight.w800)),
                ]),
              ),
              const SizedBox(height: 12),
              CardTk(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TitoloCard('Righe (${_righe.length})',
                      icona: Icons.format_list_bulleted_rounded,
                      destra: FilledButton.icon(
                        onPressed: _aggiungiRiga,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Aggiungi'),
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 38)),
                      )),
                  if (_righe.isEmpty)
                    const Text('Nessuna riga. Tocca «Aggiungi» per prendere un articolo dal listino o scriverlo a mano.',
                        style: TextStyle(color: grigio500, fontSize: 13, fontWeight: FontWeight.w600)),
                  for (var i = 0; i < _righe.length; i++) ...[
                    if (i > 0) const Divider(height: 22),
                    _EditorRiga(
                      _righe[i],
                      onCambio: () => setState(() {}),
                      onTogli: () => setState(() => _righe.removeAt(i)),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 12),
              CardTk(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const TitoloCard('Totali', icona: Icons.calculate_rounded),
                  Row(children: [
                    Expanded(
                        child: campo('Sconto %', _sconto, tastiera: tastieraNumeri, onChanged: (_) => setState(() {}))),
                    const SizedBox(width: 10),
                    Expanded(child: campo('IVA %', _iva, tastiera: tastieraNumeri, onChanged: (_) => setState(() {}))),
                  ]),
                  InfoRiga('Imponibile', euro(imponibile)),
                  InfoRiga('IVA ${percentuale(leggiNumero(_iva.text))}%', euro(iva)),
                  const Divider(height: 18),
                  InfoRiga('TOTALE', euro(totale), colore: accentoScuro, grande: true),
                ]),
              ),
              const SizedBox(height: 12),
              CardTk(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const TitoloCard('Note del preventivo', icona: Icons.sticky_note_2_rounded),
                  campo('Note', _note,
                      suggerimento: 'Condizioni di pagamento, tempi di consegna…', righe: 3, sotto: 0),
                ]),
              ),
              const SizedBox(height: 16),
              if (c == null || _righe.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(c == null ? 'Scegli il cliente per salvare' : 'Aggiungi almeno una riga per salvare',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: grigio500, fontWeight: FontWeight.w700)),
                ),
              BottoneTk(
                testo: _salvando ? 'Salvo…' : 'Salva preventivo',
                icona: Icons.check_rounded,
                onTap: c == null || _righe.isEmpty || _salvando ? null : _salva,
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _EditorRiga extends StatelessWidget {
  const _EditorRiga(this.riga, {required this.onCambio, required this.onTogli});

  final _Riga riga;
  final VoidCallback onCambio, onTogli;

  @override
  Widget build(BuildContext context) {
    final r = riga.r;
    Widget piccolo(String etichetta, TextEditingController c) => TextField(
          controller: c,
          keyboardType: tastieraNumeri,
          onChanged: (_) => onCambio(),
          decoration: InputDecoration(labelText: etichetta, isDense: true),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (r.codice.trim().isNotEmpty) ...[
          Padding(padding: const EdgeInsets.only(top: 3), child: CodiceArticolo(r.codice)),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(r.descrizione, style: const TextStyle(color: navy, fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
        ),
        IconButton(
          onPressed: onTogli,
          tooltip: 'Togli la riga',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.delete_outline_rounded, color: rosso),
        ),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(flex: 8, child: piccolo('Q.tà', riga.qta)),
        const SizedBox(width: 8),
        Expanded(flex: 11, child: piccolo('Prezzo €', riga.prezzo)),
        const SizedBox(width: 8),
        Expanded(flex: 8, child: piccolo('Sc. %', riga.sconto)),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        const Expanded(
            child: Text('Totale riga', style: TextStyle(color: grigio500, fontSize: 12.5, fontWeight: FontWeight.w600))),
        Text(euro(r.totaleRiga), style: const TextStyle(color: accentoScuro, fontSize: 14, fontWeight: FontWeight.w800)),
      ]),
    ]);
  }
}

// ───────────────────────── scelta del cliente ─────────────────────────

class _SceltaCliente extends StatefulWidget {
  const _SceltaCliente();

  @override
  State<_SceltaCliente> createState() => _SceltaClienteState();
}

class _SceltaClienteState extends State<_SceltaCliente> {
  String _cerca = '';

  @override
  Widget build(BuildContext context) {
    final lista = archivio.cercaClienti(_cerca);
    return SizedBox(
      height: MediaQuery.of(context).size.height * .8,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom),
        child: Column(children: [
          const Text('Scegli il cliente', style: TextStyle(color: navy, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          TextField(
            autofocus: lista.length > 8,
            onChanged: (t) => setState(() => _cerca = t),
            decoration: const InputDecoration(
                hintText: 'Cerca per nome, telefono…', prefixIcon: Icon(Icons.search_rounded), isDense: true),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: lista.isEmpty
                ? const StatoVuoto(Icons.search_off_rounded, 'Nessun cliente', 'Aggiungilo da «Clienti» e torna qui')
                : ListView.separated(
                    padding: EdgeInsets.only(bottom: 16 + MediaQuery.of(context).padding.bottom),
                    itemCount: lista.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final c = lista[i];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        leading: Avatar(c.nominativo, lato: 38),
                        title: Text(c.nominativo.isEmpty ? '(senza nome)' : c.nominativo,
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text([c.telefono, c.citta].where((s) => s.trim().isNotEmpty).join(' · ')),
                        onTap: () => Navigator.pop(context, c),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

// ───────────────────────── aggiunta di una riga ─────────────────────────

class _AggiungiRiga extends StatefulWidget {
  const _AggiungiRiga();

  @override
  State<_AggiungiRiga> createState() => _AggiungiRigaState();
}

class _AggiungiRigaState extends State<_AggiungiRiga> {
  bool _manuale = false;
  List<Articolo> _trovati = const [];
  Timer? _attesa;
  final _codice = TextEditingController();
  final _descrizione = TextEditingController();
  final _qta = TextEditingController(text: '1');
  final _prezzo = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cerca('');
    if (archivio.nArticoli == 0) _manuale = true;
  }

  @override
  void dispose() {
    _attesa?.cancel();
    super.dispose();
  }

  void _cerca(String q) {
    _attesa?.cancel();
    _attesa = Timer(const Duration(milliseconds: 220), () async {
      final r = await archivio.cercaArticoli(q, limite: 50);
      if (mounted) setState(() => _trovati = r);
    });
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: MediaQuery.of(context).size.height * .85,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom),
          child: Column(children: [
            Scelta<bool>(
              voci: const [(false, 'Dal listino'), (true, 'Scritta a mano')],
              valore: _manuale,
              onCambia: (v) => setState(() => _manuale = v),
            ),
            const SizedBox(height: 12),
            Expanded(child: _manuale ? _moduloManuale() : _ricerca()),
          ]),
        ),
      );

  Widget _ricerca() => Column(children: [
        TextField(
          autofocus: true,
          onChanged: _cerca,
          decoration: const InputDecoration(
              hintText: 'Codice, descrizione o EAN…', prefixIcon: Icon(Icons.search_rounded), isDense: true),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _trovati.isEmpty
              ? StatoVuoto(
                  Icons.inventory_2_rounded,
                  archivio.nArticoli == 0 ? 'Listino vuoto' : 'Nessun articolo',
                  archivio.nArticoli == 0
                      ? 'Collega il file del listino nelle Impostazioni, oppure scrivi la riga a mano'
                      : 'Prova un altro codice o parola')
              : ListView.separated(
                  padding: EdgeInsets.only(bottom: 16 + MediaQuery.of(context).padding.bottom),
                  itemCount: _trovati.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final a = _trovati[i];
                    return InkWell(
                      onTap: () => Navigator.pop(
                          context,
                          RigaPreventivo(
                            articoloId: a.id,
                            codice: a.codice,
                            descrizione: a.descrizione,
                            quantita: 1,
                            prezzoUnitario: a.prezzoVendita,
                            unitaMisura: a.unitaMisura,
                          )),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                CodiceArticolo(a.codice),
                                const SizedBox(width: 8),
                                Text(euro(a.prezzoVendita),
                                    style: const TextStyle(color: accentoScuro, fontWeight: FontWeight.w800)),
                                const Spacer(),
                                if (a.giacenza != 0)
                                  Text('Giac. ${numero(a.giacenza)}',
                                      style: TextStyle(
                                          color: a.giacenza > 0 ? verdeScuro : rosso,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700)),
                              ]),
                              const SizedBox(height: 3),
                              Text(a.descrizione,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: grigio500, fontSize: 12.5, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.add_circle_rounded, color: accento),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ]);

  Widget _moduloManuale() => ListView(padding: EdgeInsets.only(bottom: 16 + MediaQuery.of(context).padding.bottom), children: [
        campo('Codice (facoltativo)', _codice, tuttoMaiuscolo: true),
        campo('Descrizione', _descrizione, righe: 2),
        Row(children: [
          Expanded(child: campo('Quantità', _qta, tastiera: tastieraNumeri)),
          const SizedBox(width: 10),
          Expanded(child: campo('Prezzo €', _prezzo, tastiera: tastieraNumeri)),
        ]),
        BottoneTk(
          testo: 'Aggiungi riga',
          icona: Icons.add_rounded,
          onTap: () {
            if (_descrizione.text.trim().isEmpty) {
              avviso(context, 'Scrivi la descrizione');
              return;
            }
            final q = leggiNumero(_qta.text);
            Navigator.pop(
                context,
                RigaPreventivo(
                  codice: _codice.text.trim(),
                  descrizione: _descrizione.text.trim(),
                  quantita: q > 0 ? q : 1,
                  prezzoUnitario: leggiNumero(_prezzo.text),
                ));
          },
        ),
      ]);
}
