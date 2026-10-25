// Dati di tk-clienti: stesse tabelle e stessi campi della versione Kotlin (Room, schema 3).
import 'formati.dart';

double _d(Object? v, [double predefinito = 0]) => v is num ? v.toDouble() : predefinito;
int _i(Object? v, [int predefinito = 0]) => v is num ? v.toInt() : predefinito;
String _s(Object? v, [String predefinito = '']) => v == null ? predefinito : '$v';

// ───────────────────────── cliente ─────────────────────────

class Cliente {
  Cliente({
    this.id = 0,
    this.nome = '',
    this.cognome = '',
    this.telefono = '',
    this.email = '',
    this.piva = '',
    this.codiceFiscale = '',
    this.codiceSdi = '',
    this.pec = '',
    this.indirizzo = '',
    this.cap = '',
    this.citta = '',
    this.provincia = '',
    this.note = '',
    this.tag = '',
    this.commissionePerc = -1,
    int? createdAt,
    int? updatedAt,
  })  : createdAt = createdAt ?? adesso(),
        updatedAt = updatedAt ?? adesso();

  int id;
  String nome, cognome, telefono, email, piva, codiceFiscale, codiceSdi, pec;
  String indirizzo, cap, citta, provincia, note, tag;

  /// Commissione % propria del cliente; -1 = usa la percentuale predefinita delle Impostazioni.
  double commissionePerc;
  int createdAt, updatedAt;

  String get nominativo => [nome, cognome].where((s) => s.trim().isNotEmpty).join(' ');

  /// «Via Roma 1 – 80100 Napoli NA»
  String get indirizzoCompleto =>
      [indirizzo, '$cap $citta $provincia'.trim()].where((s) => s.trim().isNotEmpty).join(' – ');

  factory Cliente.daRiga(Map<String, Object?> r) => Cliente(
        id: _i(r['id']),
        nome: _s(r['nome']),
        cognome: _s(r['cognome']),
        telefono: _s(r['telefono']),
        email: _s(r['email']),
        piva: _s(r['piva']),
        codiceFiscale: _s(r['codiceFiscale']),
        codiceSdi: _s(r['codiceSdi']),
        pec: _s(r['pec']),
        indirizzo: _s(r['indirizzo']),
        cap: _s(r['cap']),
        citta: _s(r['citta']),
        provincia: _s(r['provincia']),
        note: _s(r['note']),
        tag: _s(r['tag']),
        commissionePerc: _d(r['commissionePerc'], -1),
        createdAt: _i(r['createdAt'], adesso()),
        updatedAt: _i(r['updatedAt'], adesso()),
      );

  /// Riga del database e del file clienti.json (stesso ordine dei campi della versione Kotlin).
  Map<String, Object?> perDb({bool conId = true}) => {
        if (conId) 'id': id,
        'nome': nome,
        'cognome': cognome,
        'telefono': telefono,
        'email': email,
        'piva': piva,
        'codiceFiscale': codiceFiscale,
        'codiceSdi': codiceSdi,
        'pec': pec,
        'indirizzo': indirizzo,
        'cap': cap,
        'citta': citta,
        'provincia': provincia,
        'note': note,
        'tag': tag,
        'commissionePerc': commissionePerc,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  Cliente copia() => Cliente.daRiga(perDb());
}

// ───────────────────────── articolo e magazzino ─────────────────────────

const origineManuale = 'manuale';
const origineListino = 'listino';

class Articolo {
  Articolo({
    this.id = 0,
    this.codice = '',
    this.descrizione = '',
    this.prezzoListino = 0,
    this.prezzoRivenditore = 0,
    this.pagina,
    this.ean13 = '',
    this.giacenza = 0,
    this.unitaMisura = 'PZ',
    this.categoria = '',
    this.note = '',
    this.origine = origineManuale,
    int? createdAt,
    int? updatedAt,
  })  : createdAt = createdAt ?? adesso(),
        updatedAt = updatedAt ?? adesso();

  int id;
  String codice, descrizione;
  double prezzoListino, prezzoRivenditore;
  int? pagina;
  String ean13;
  double giacenza;
  String unitaMisura, categoria, note;

  /// «listino» = arriva dal file XLSX/CSV (la sincronizzazione può aggiornarlo o toglierlo);
  /// «manuale» = aggiunto a mano, la sincronizzazione non lo tocca.
  String origine;
  int createdAt, updatedAt;

  /// Prezzo proposto nel preventivo: il rivenditore se c'è, altrimenti il listino.
  double get prezzoVendita => prezzoRivenditore > 0 ? prezzoRivenditore : prezzoListino;

  factory Articolo.daRiga(Map<String, Object?> r) => Articolo(
        id: _i(r['id']),
        codice: _s(r['codice']),
        descrizione: _s(r['descrizione']),
        prezzoListino: _d(r['prezzoListino']),
        prezzoRivenditore: _d(r['prezzoRivenditore']),
        pagina: r['pagina'] is num ? (r['pagina'] as num).toInt() : null,
        ean13: _s(r['ean13']),
        giacenza: _d(r['giacenza']),
        unitaMisura: _s(r['unitaMisura'], 'PZ'),
        categoria: _s(r['categoria']),
        note: _s(r['note']),
        origine: _s(r['origine'], origineManuale),
        createdAt: _i(r['createdAt'], adesso()),
        updatedAt: _i(r['updatedAt'], adesso()),
      );

  Map<String, Object?> perDb({bool conId = true}) => {
        if (conId) 'id': id,
        'codice': codice,
        'descrizione': descrizione,
        'prezzoListino': prezzoListino,
        'prezzoRivenditore': prezzoRivenditore,
        'pagina': pagina,
        'ean13': ean13,
        'giacenza': giacenza,
        'unitaMisura': unitaMisura,
        'categoria': categoria,
        'note': note,
        'origine': origine,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  Articolo copia() => Articolo.daRiga(perDb());
}

class Movimento {
  Movimento({
    this.id = 0,
    this.articoloId = 0,
    this.tipo = 'CARICO',
    this.quantita = 0,
    this.giacenzaPrecedente = 0,
    this.giacenzaNuova = 0,
    this.causale = '',
    this.riferimento = '',
    int? data,
  }) : data = data ?? adesso();

  int id, articoloId;
  String tipo;
  double quantita, giacenzaPrecedente, giacenzaNuova;
  String causale, riferimento;
  int data;

  factory Movimento.daRiga(Map<String, Object?> r) => Movimento(
        id: _i(r['id']),
        articoloId: _i(r['articoloId']),
        tipo: _s(r['tipo']),
        quantita: _d(r['quantita']),
        giacenzaPrecedente: _d(r['giacenzaPrecedente']),
        giacenzaNuova: _d(r['giacenzaNuova']),
        causale: _s(r['causale']),
        riferimento: _s(r['riferimento']),
        data: _i(r['data'], adesso()),
      );

  Map<String, Object?> perDb({bool conId = true}) => {
        if (conId) 'id': id,
        'articoloId': articoloId,
        'tipo': tipo,
        'quantita': quantita,
        'giacenzaPrecedente': giacenzaPrecedente,
        'giacenzaNuova': giacenzaNuova,
        'causale': causale,
        'riferimento': riferimento,
        'data': data,
      };
}

// ───────────────────────── preventivo ─────────────────────────

const statiPreventivo = ['BOZZA', 'INVIATO', 'ACCETTATO', 'RIFIUTATO'];

class Preventivo {
  Preventivo({
    this.id = 0,
    this.numero = '',
    this.clienteId = 0,
    int? data,
    this.validita = 30,
    this.ivaPercentuale = 22,
    this.scontoGlobale = 0,
    this.totaleImponibile = 0,
    this.totaleIva = 0,
    this.totale = 0,
    this.note = '',
    this.stato = 'BOZZA',
    this.commissionePerc = -1,
    int? createdAt,
    int? updatedAt,
  })  : data = data ?? adesso(),
        createdAt = createdAt ?? adesso(),
        updatedAt = updatedAt ?? adesso();

  int id;
  String numero;
  int clienteId, data, validita;
  double ivaPercentuale, scontoGlobale, totaleImponibile, totaleIva, totale;
  String note, stato;

  /// Commissione % con cui è stato fatto (solo per la nota nel dettaglio); -1 = fatto prima delle commissioni.
  double commissionePerc;
  int createdAt, updatedAt;

  factory Preventivo.daRiga(Map<String, Object?> r) => Preventivo(
        id: _i(r['id']),
        numero: _s(r['numero']),
        clienteId: _i(r['clienteId']),
        data: _i(r['data'], adesso()),
        validita: _i(r['validita'], 30),
        ivaPercentuale: _d(r['ivaPercentuale'], 22),
        scontoGlobale: _d(r['scontoGlobale']),
        totaleImponibile: _d(r['totaleImponibile']),
        totaleIva: _d(r['totaleIva']),
        totale: _d(r['totale']),
        note: _s(r['note']),
        stato: _s(r['stato'], 'BOZZA'),
        commissionePerc: _d(r['commissionePerc'], -1),
        createdAt: _i(r['createdAt'], adesso()),
        updatedAt: _i(r['updatedAt'], adesso()),
      );

  Map<String, Object?> perDb({bool conId = true}) => {
        if (conId) 'id': id,
        'numero': numero,
        'clienteId': clienteId,
        'data': data,
        'validita': validita,
        'ivaPercentuale': ivaPercentuale,
        'scontoGlobale': scontoGlobale,
        'totaleImponibile': totaleImponibile,
        'totaleIva': totaleIva,
        'totale': totale,
        'note': note,
        'stato': stato,
        'commissionePerc': commissionePerc,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  Preventivo copia() => Preventivo.daRiga(perDb());
}

class RigaPreventivo {
  RigaPreventivo({
    this.id = 0,
    this.preventivoId = 0,
    this.ordine = 0,
    this.codice = '',
    this.descrizione = '',
    this.quantita = 1,
    this.unitaMisura = 'PZ',
    this.prezzoUnitario = 0,
    this.scontoPercentuale = 0,
    this.articoloId,
  });

  int id, preventivoId, ordine;
  String codice, descrizione;
  double quantita;
  String unitaMisura;
  double prezzoUnitario, scontoPercentuale;
  int? articoloId;

  double get totaleRiga {
    final lordo = quantita * prezzoUnitario;
    return lordo - (lordo * scontoPercentuale / 100.0);
  }

  factory RigaPreventivo.daRiga(Map<String, Object?> r) => RigaPreventivo(
        id: _i(r['id']),
        preventivoId: _i(r['preventivoId']),
        ordine: _i(r['ordine']),
        codice: _s(r['codice']),
        descrizione: _s(r['descrizione']),
        quantita: _d(r['quantita'], 1),
        unitaMisura: _s(r['unitaMisura'], 'PZ'),
        prezzoUnitario: _d(r['prezzoUnitario']),
        scontoPercentuale: _d(r['scontoPercentuale']),
        articoloId: r['articoloId'] is num ? (r['articoloId'] as num).toInt() : null,
      );

  Map<String, Object?> perDb({bool conId = true}) => {
        if (conId) 'id': id,
        'preventivoId': preventivoId,
        'ordine': ordine,
        'codice': codice,
        'descrizione': descrizione,
        'quantita': quantita,
        'unitaMisura': unitaMisura,
        'prezzoUnitario': prezzoUnitario,
        'scontoPercentuale': scontoPercentuale,
        'articoloId': articoloId,
      };

  RigaPreventivo copia() => RigaPreventivo.daRiga(perDb());
}

class PreventivoConRighe {
  PreventivoConRighe(this.preventivo, this.righe);
  final Preventivo preventivo;
  final List<RigaPreventivo> righe;
}

/// (imponibile, iva, totale) come PreventivoRepository.calcolaTotali.
(double, double, double) calcolaTotali(List<RigaPreventivo> righe, double ivaPercentuale, double scontoGlobalePerc) {
  final lordo = righe.fold<double>(0, (s, r) => s + r.totaleRiga);
  final imponibile = lordo - (lordo * scontoGlobalePerc / 100.0);
  final iva = imponibile * ivaPercentuale / 100.0;
  return (imponibile, iva, imponibile + iva);
}

// ───────────────────────── intestazione PDF ─────────────────────────

class Intestazione {
  Intestazione({
    this.ragioneSociale = '',
    this.indirizzo = '',
    this.cap = '',
    this.citta = '',
    this.provincia = '',
    this.piva = '',
    this.codiceFiscale = '',
    this.telefono = '',
    this.email = '',
    this.pec = '',
    this.sito = '',
    this.iban = '',
    this.noteFooter = '',
  });

  String ragioneSociale, indirizzo, cap, citta, provincia, piva, codiceFiscale;
  String telefono, email, pec, sito, iban, noteFooter;

  /// Per il file clienti.json (ordine dei campi della versione Kotlin).
  Map<String, Object?> perJson() => {
        'ragioneSociale': ragioneSociale,
        'indirizzo': indirizzo,
        'cap': cap,
        'citta': citta,
        'provincia': provincia,
        'piva': piva,
        'codiceFiscale': codiceFiscale,
        'telefono': telefono,
        'email': email,
        'pec': pec,
        'sito': sito,
        'iban': iban,
        'noteFooter': noteFooter,
      };

  factory Intestazione.daJson(Map<String, Object?> j) => Intestazione(
        ragioneSociale: _s(j['ragioneSociale']),
        indirizzo: _s(j['indirizzo']),
        cap: _s(j['cap']),
        citta: _s(j['citta']),
        provincia: _s(j['provincia']),
        piva: _s(j['piva']),
        codiceFiscale: _s(j['codiceFiscale']),
        telefono: _s(j['telefono']),
        email: _s(j['email']),
        pec: _s(j['pec']),
        sito: _s(j['sito']),
        iban: _s(j['iban']),
        noteFooter: _s(j['noteFooter']),
      );

  Intestazione copia() => Intestazione.daJson(perJson());
}

// ───────────────────────── commissione agente ─────────────────────────

const baseImponibile = 'imponibile';
const baseTotale = 'totale';

class ConfigCommissione {
  const ConfigCommissione({this.percentualeDefault = 0, this.baseCalcolo = baseImponibile});

  final double percentualeDefault;

  /// Su cosa si calcola: imponibile netto oppure totale IVA inclusa.
  final String baseCalcolo;
}

/// Percentuale effettiva: quella del cliente se l'ha (≥ 0), altrimenti la predefinita.
double percentualeEffettiva(double clientePerc, ConfigCommissione cfg) =>
    clientePerc >= 0 ? clientePerc : cfg.percentualeDefault;

double baseCommissione(Preventivo p, ConfigCommissione cfg) =>
    cfg.baseCalcolo == baseTotale ? p.totale : p.totaleImponibile;

/// Commissione in euro con la percentuale ATTUALE del cliente (o la predefinita).
double commissionePreventivo(Preventivo p, double clientePerc, ConfigCommissione cfg) =>
    baseCommissione(p, cfg) * percentualeEffettiva(clientePerc, cfg) / 100.0;
