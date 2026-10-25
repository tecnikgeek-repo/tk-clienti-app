// Clienti: elenco con ricerca, scheda (riepilogo, contatti, anagrafica, storico preventivi) e modulo.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app.dart';
import '../dati/formati.dart';
import '../dati/modelli.dart';
import '../tema.dart';
import 'preventivi.dart';
import 'preventivo_modulo.dart';

// ───────────────────────── elenco ─────────────────────────

class SchermataClienti extends StatefulWidget {
  const SchermataClienti({super.key});

  @override
  State<SchermataClienti> createState() => _SchermataClientiState();
}

class _SchermataClientiState extends State<SchermataClienti> {
  String _cerca = '';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: archivio,
        builder: (context, _) {
          final clienti = archivio.cercaClienti(_cerca);
          return Scaffold(
            floatingActionButton: pulsanteNuovo('Nuovo cliente', () => vai(context, const SchermataModificaCliente())),
            body: Column(children: [
              Testata(
                titolo: 'Clienti',
                sottotitolo: _cerca.isEmpty ? '${archivio.clienti.length} in anagrafica' : '${clienti.length} risultati',
                indietro: () => Navigator.pop(context),
                logo: false,
                sotto: TextField(
                  onChanged: (t) => setState(() => _cerca = t),
                  decoration: const InputDecoration(
                      hintText: 'Cerca per nome, telefono, email, P.IVA, città…',
                      prefixIcon: Icon(Icons.search_rounded),
                      isDense: true),
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
                      if (clienti.isEmpty)
                        _cerca.isEmpty
                            ? const StatoVuoto(Icons.people_alt_rounded, 'Nessun cliente',
                                'Tocca «Nuovo cliente» per aggiungere il primo, oppure collega il file dei clienti nelle Impostazioni')
                            : const StatoVuoto(Icons.search_off_rounded, 'Nessun risultato',
                                'Cambia la ricerca o aggiungi un nuovo cliente')
                      else
                        for (final c in clienti)
                          Padding(padding: const EdgeInsets.only(bottom: 10), child: _RigaCliente(c)),
                    ],
                  ),
                ),
              ),
            ]),
          );
        },
      );
}

const _coloriAvatar = [
  Color(0xFF2563EB), Color(0xFFE39A2E), Color(0xFF16A34A), Color(0xFF7C3AED),
  Color(0xFFDC2626), Color(0xFF0E9AA7), Color(0xFFDB2777), Color(0xFF4F46E5),
];

/// Avatar a iniziali, colore fisso per nome.
class Avatar extends StatelessWidget {
  const Avatar(this.nome, {super.key, this.lato = 42});

  final String nome;
  final double lato;

  @override
  Widget build(BuildContext context) {
    final parole = nome.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2);
    final iniziali = parole.map((p) => p.characters.first.toUpperCase()).join();
    var h = 0;
    for (final c in nome.toLowerCase().codeUnits) {
      h = (31 * h + c) & 0x7fffffff;
    }
    return Container(
      width: lato,
      height: lato,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: nome.trim().isEmpty ? grigio500 : _coloriAvatar[h % _coloriAvatar.length],
          borderRadius: BorderRadius.circular(lato * .33)),
      child: Text(iniziali.isEmpty ? '?' : iniziali,
          style: TextStyle(color: bianco, fontWeight: FontWeight.w800, fontSize: lato * .36)),
    );
  }
}

class _RigaCliente extends StatelessWidget {
  const _RigaCliente(this.c);

  final Cliente c;

  @override
  Widget build(BuildContext context) {
    final nome = c.nominativo.isEmpty ? '(senza nome)' : c.nominativo;
    final dettagli = [c.telefono, c.email].where((s) => s.trim().isNotEmpty).join(' · ');
    final luogo = [c.indirizzo, c.cap, c.citta, c.provincia].where((s) => s.trim().isNotEmpty).join(', ');
    return CardTk(
      padding: const EdgeInsets.all(14),
      onTap: () => vai(context, SchermataCliente(c.id)),
      child: Row(children: [
        Avatar(nome),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(nome,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: navy, fontSize: 14.5, fontWeight: FontWeight.w800)),
              ),
              if (c.tag.trim().isNotEmpty) ...[const SizedBox(width: 8), Pilla(c.tag, accento, piena: false)],
            ]),
            if (dettagli.isNotEmpty)
              Text(dettagli,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: grigio500, fontSize: 12.5, fontWeight: FontWeight.w600)),
            if (luogo.isNotEmpty)
              Text(luogo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: grigio400, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
        const Icon(Icons.chevron_right_rounded, color: grigio300),
      ]),
    );
  }
}

// ───────────────────────── scheda ─────────────────────────

class SchermataCliente extends StatelessWidget {
  const SchermataCliente(this.id, {super.key});

  final int id;

  Future<void> _elimina(BuildContext context, Cliente c) async {
    final n = archivio.preventiviDi(c.id).length;
    if (n > 0) {
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Non si può eliminare'),
          content: Text('${c.nominativo} ha $n preventivi. Elimina prima i preventivi, poi il cliente.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('Ho capito'))],
        ),
      );
      return;
    }
    if (!await conferma(context, 'Eliminare il cliente?', 'Confermi l\'eliminazione di ${c.nominativo}?')) return;
    await archivio.eliminaCliente(c);
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: archivio,
        builder: (context, _) {
          final c = archivio.cliente(id);
          if (c == null) return const Scaffold(body: Center(child: Text('Cliente eliminato')));
          final prev = archivio.preventiviDi(id);
          final fatturato = prev.fold<double>(0, (s, p) => s + p.totale);
          final nome = c.nominativo.isEmpty ? 'Cliente' : c.nominativo;
          return Scaffold(
            floatingActionButton: pulsanteNuovo(
                'Preventivo', () => vai(context, SchermataModuloPreventivo(clienteId: c.id)),
                colore: verde),
            body: Column(children: [
              Testata(
                titolo: nome,
                sottotitolo: c.citta.isEmpty ? 'Scheda cliente' : c.citta,
                indietro: () => Navigator.pop(context),
                logo: false,
                azioni: [
                  AzioneTk(Icons.edit_rounded, 'Modifica', () => vai(context, SchermataModificaCliente(cliente: c))),
                  AzioneTk(Icons.delete_outline_rounded, 'Elimina', () => _elimina(context, c)),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(14, 14, 14, spazioFondo(context, pulsante: true)),
                  children: [
                    CardTk(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const TitoloCard('Riepilogo', icona: Icons.insights_rounded),
                        Row(children: [
                          Expanded(child: _Cifra('PREVENTIVI', '${prev.length}', accento)),
                          const SizedBox(width: 10),
                          Expanded(child: _Cifra('FATTURATO', euro(fatturato), verde)),
                        ]),
                        if (prev.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          InfoRiga('Primo preventivo', data(prev.map((p) => p.data).reduce((a, b) => a < b ? a : b))),
                          InfoRiga('Ultimo preventivo', data(prev.map((p) => p.data).reduce((a, b) => a > b ? a : b))),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 12),
                    CardTk(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const TitoloCard('Contatti', icona: Icons.contact_phone_rounded),
                        if (c.telefono.trim().isEmpty && c.email.trim().isEmpty && c.pec.trim().isEmpty)
                          const Text('Nessun contatto registrato',
                              style: TextStyle(color: grigio500, fontWeight: FontWeight.w600)),
                        if (c.telefono.trim().isNotEmpty)
                          _Contatto(Icons.call_rounded, c.telefono, 'tel:${c.telefono.replaceAll(' ', '')}'),
                        if (c.email.trim().isNotEmpty) _Contatto(Icons.mail_rounded, c.email, 'mailto:${c.email}'),
                        if (c.pec.trim().isNotEmpty) _Contatto(Icons.verified_rounded, 'PEC ${c.pec}', 'mailto:${c.pec}'),
                      ]),
                    ),
                    if (c.indirizzoCompleto.isNotEmpty ||
                        c.piva.isNotEmpty ||
                        c.codiceFiscale.isNotEmpty ||
                        c.codiceSdi.isNotEmpty ||
                        c.tag.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      CardTk(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const TitoloCard('Anagrafica', icona: Icons.badge_rounded),
                          if (c.indirizzoCompleto.isNotEmpty) InfoRiga('Indirizzo', c.indirizzoCompleto),
                          if (c.piva.isNotEmpty) InfoRiga('P.IVA', c.piva),
                          if (c.codiceFiscale.isNotEmpty) InfoRiga('Cod. fiscale', c.codiceFiscale),
                          if (c.codiceSdi.isNotEmpty) InfoRiga('SDI', c.codiceSdi),
                          if (c.tag.isNotEmpty) InfoRiga('Tag', c.tag),
                          if (c.commissionePerc >= 0) InfoRiga('Commissione', '${percentuale(c.commissionePerc)}%'),
                        ]),
                      ),
                    ],
                    if (c.note.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      CardTk(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const TitoloCard('Note', icona: Icons.sticky_note_2_rounded),
                          Text(c.note, style: const TextStyle(color: navy, fontSize: 13.5)),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.only(left: 6, bottom: 8),
                      child: Text('Storico preventivi (${prev.length})',
                          style: const TextStyle(color: navy, fontSize: 15, fontWeight: FontWeight.w800)),
                    ),
                    if (prev.isEmpty)
                      const StatoVuoto(Icons.receipt_long_rounded, 'Nessun preventivo',
                          'Tocca «Preventivo» per fare il primo a questo cliente')
                    else
                      for (final p in prev)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 10), child: VocePreventivo(p, mostraCliente: false)),
                  ],
                ),
              ),
            ]),
          );
        },
      );
}

class _Cifra extends StatelessWidget {
  const _Cifra(this.etichetta, this.valore, this.colore);

  final String etichetta, valore;
  final Color colore;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: grigio50, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(etichetta, style: const TextStyle(color: grigio500, fontSize: 10.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(valore, style: TextStyle(color: colore, fontSize: 18, fontWeight: FontWeight.w800)),
          ),
        ]),
      );
}

class _Contatto extends StatelessWidget {
  const _Contatto(this.icona, this.testo, this.link);

  final IconData icona;
  final String testo, link;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => launchUrl(Uri.parse(link)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            Icon(icona, color: accento, size: 19),
            const SizedBox(width: 10),
            Expanded(
                child: Text(testo, style: const TextStyle(color: navy, fontSize: 14, fontWeight: FontWeight.w700))),
          ]),
        ),
      );
}

// ───────────────────────── modulo ─────────────────────────

class SchermataModificaCliente extends StatefulWidget {
  const SchermataModificaCliente({super.key, this.cliente});

  final Cliente? cliente;

  @override
  State<SchermataModificaCliente> createState() => _SchermataModificaClienteState();
}

class _SchermataModificaClienteState extends State<SchermataModificaCliente> {
  late final Cliente _c = widget.cliente?.copia() ?? Cliente();
  late final _nome = TextEditingController(text: _c.nome);
  late final _cognome = TextEditingController(text: _c.cognome);
  late final _telefono = TextEditingController(text: _c.telefono);
  late final _email = TextEditingController(text: _c.email);
  late final _piva = TextEditingController(text: _c.piva);
  late final _cf = TextEditingController(text: _c.codiceFiscale);
  late final _sdi = TextEditingController(text: _c.codiceSdi);
  late final _pec = TextEditingController(text: _c.pec);
  late final _indirizzo = TextEditingController(text: _c.indirizzo);
  late final _cap = TextEditingController(text: _c.cap);
  late final _provincia = TextEditingController(text: _c.provincia);
  late final _citta = TextEditingController(text: _c.citta);
  late final _tag = TextEditingController(text: _c.tag);
  late final _note = TextEditingController(text: _c.note);
  late final _commissione = TextEditingController(text: _c.commissionePerc >= 0 ? percentuale(_c.commissionePerc) : '');
  bool _erroreNome = false;

  bool get _nuovo => widget.cliente == null;

  Future<void> _salva({bool preventivo = false}) async {
    if (_nome.text.trim().isEmpty && _cognome.text.trim().isEmpty) {
      setState(() => _erroreNome = true);
      return;
    }
    _c
      ..nome = _nome.text.trim()
      ..cognome = _cognome.text.trim()
      ..telefono = _telefono.text.trim()
      ..email = _email.text.trim()
      ..piva = _piva.text.trim()
      ..codiceFiscale = _cf.text.trim().toUpperCase()
      ..codiceSdi = _sdi.text.trim().toUpperCase()
      ..pec = _pec.text.trim()
      ..indirizzo = _indirizzo.text.trim()
      ..cap = _cap.text.trim()
      ..provincia = _provincia.text.trim().toUpperCase()
      ..citta = _citta.text.trim()
      ..tag = _tag.text.trim()
      ..note = _note.text.trim()
      ..commissionePerc = _commissione.text.trim().isEmpty ? -1 : leggiNumero(_commissione.text);
    final id = await archivio.salvaCliente(_c);
    if (!mounted) return;
    if (preventivo) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => SchermataModuloPreventivo(clienteId: id)));
    } else if (_nuovo) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SchermataCliente(id)));
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          TestataSemplice(
              titolo: _nuovo ? 'Nuovo cliente' : 'Modifica cliente', indietro: () => Navigator.pop(context)),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(14, 14, 14, spazioFondo(context)),
              children: [
                CardTk(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const TitoloCard('Anagrafica', icona: Icons.person_rounded),
                    campo('Nome', _nome,
                        maiuscole: true,
                        errore: _erroreNome ? 'Scrivi il nome o il cognome' : null,
                        onChanged: (_) => setState(() => _erroreNome = false)),
                    campo('Cognome / Ragione sociale', _cognome, maiuscole: true),
                    campo('Telefono', _telefono, tastiera: TextInputType.phone),
                    campo('Email', _email, tastiera: TextInputType.emailAddress, sotto: 0),
                  ]),
                ),
                const SizedBox(height: 12),
                CardTk(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const TitoloCard('Dati fiscali', icona: Icons.receipt_rounded),
                    campo('Partita IVA', _piva, tastiera: TextInputType.text),
                    campo('Codice fiscale', _cf, tuttoMaiuscolo: true),
                    campo('Codice SDI / Univoco', _sdi, tuttoMaiuscolo: true),
                    campo('PEC', _pec, tastiera: TextInputType.emailAddress, sotto: 0),
                  ]),
                ),
                const SizedBox(height: 12),
                CardTk(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const TitoloCard('Indirizzo', icona: Icons.place_rounded),
                    campo('Via e numero civico', _indirizzo, maiuscole: true),
                    Row(children: [
                      Expanded(child: campo('CAP', _cap, tastiera: TextInputType.number)),
                      const SizedBox(width: 10),
                      Expanded(child: campo('Prov.', _provincia, tuttoMaiuscolo: true)),
                    ]),
                    campo('Città', _citta, maiuscole: true, sotto: 0),
                  ]),
                ),
                const SizedBox(height: 12),
                CardTk(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const TitoloCard('Note e categoria', icona: Icons.label_rounded),
                    campo('Tag (es. PRIVATO, AZIENDA, VIP)', _tag, tuttoMaiuscolo: true),
                    campo('Note', _note, righe: 3, sotto: 0),
                  ]),
                ),
                const SizedBox(height: 12),
                CardTk(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const TitoloCard('Commissione agente', icona: Icons.percent_rounded, colore: verde),
                    campo('Commissione % per questo cliente', _commissione,
                        suggerimento: 'Vuoto = la percentuale predefinita', tastiera: tastieraNumeri, sotto: 6),
                    const Text(
                        'Lascia vuoto per usare la percentuale delle Impostazioni. Compila solo se questo cliente ha una commissione diversa.',
                        style: TextStyle(color: grigio500, fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                ),
                const SizedBox(height: 16),
                if (_nuovo) ...[
                  BottoneTk(
                      testo: 'Salva e crea preventivo',
                      icona: Icons.post_add_rounded,
                      onTap: () => _salva(preventivo: true)),
                  const SizedBox(height: 10),
                  BottoneTk(testo: 'Salva soltanto', icona: Icons.check_rounded, chiaro: true, onTap: _salva),
                ] else
                  BottoneTk(testo: 'Salva modifiche', icona: Icons.check_rounded, onTap: _salva),
              ],
            ),
          ),
        ]),
      );
}
