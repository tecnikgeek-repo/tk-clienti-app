// Impostazioni di tk-clienti: intestazione del PDF, commissione agente e i tre file collegati
// (listino, clienti, preventivi). Al primo avvio dopo l'aggiornamento recupera quelle salvate
// dalla versione Kotlin (Preferences DataStore), così non si deve ricollegare né reinserire niente.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'modelli.dart';

/// Un file collegato su Drive, Dropbox o nel telefono.
class ConfigFile {
  ConfigFile({
    this.uri = '',
    this.nome = '',
    this.abilitato = false,
    this.ultimo = 0,
    this.modificato = 0,
    this.dimensione = 0,
    this.hash = '',
  });

  /// content://… del file scelto (il permesso resta al pacchetto dell'app).
  String uri;
  String nome;

  /// Sincronizzazione automatica accesa.
  bool abilitato;

  /// Ultimo salvataggio (clienti, preventivi) o ultima importazione (listino).
  int ultimo;

  /// Data di modifica e dimensione del file l'ultima volta che lo si è letto o scritto.
  int modificato, dimensione;

  /// Impronta SHA-256 di quanto scritto l'ultima volta: se il contenuto non cambia non si riscrive
  /// (niente «copie in conflitto» su Dropbox/Drive).
  String hash;

  bool get collegato => uri.isNotEmpty;

  Map<String, Object?> perJson() => {
        'uri': uri,
        'nome': nome,
        'abilitato': abilitato,
        'ultimo': ultimo,
        'modificato': modificato,
        'dimensione': dimensione,
        'hash': hash,
      };

  factory ConfigFile.daJson(Map<String, Object?> j) => ConfigFile(
        uri: '${j['uri'] ?? ''}',
        nome: '${j['nome'] ?? ''}',
        abilitato: j['abilitato'] == true,
        ultimo: (j['ultimo'] as num?)?.toInt() ?? 0,
        modificato: (j['modificato'] as num?)?.toInt() ?? 0,
        dimensione: (j['dimensione'] as num?)?.toInt() ?? 0,
        hash: '${j['hash'] ?? ''}',
      );
}

enum Dominio {
  listino('file_listino'),
  clienti('file_clienti'),
  preventivi('file_preventivi');

  const Dominio(this.chiave);
  final String chiave;
}

class Impostazioni {
  Impostazioni._(this._p);

  final SharedPreferences _p;

  late Intestazione intestazione;
  late ConfigCommissione commissione;
  final Map<Dominio, ConfigFile> _file = {};

  static Future<Impostazioni> carica() async {
    final i = Impostazioni._(await SharedPreferences.getInstance());
    if (!(i._p.getBool('migrato') ?? false)) await i._recuperaVecchie();
    i._leggi();
    return i;
  }

  void _leggi() {
    final t = _p.getString('intestazione');
    intestazione = t == null ? Intestazione() : Intestazione.daJson(jsonDecode(t) as Map<String, Object?>);
    commissione = ConfigCommissione(
      percentualeDefault: _p.getDouble('commissione_percentuale') ?? 0,
      baseCalcolo: _p.getString('commissione_base') ?? baseImponibile,
    );
    for (final d in Dominio.values) {
      final j = _p.getString(d.chiave);
      _file[d] = j == null
          ? ConfigFile(abilitato: d == Dominio.listino)
          : ConfigFile.daJson(jsonDecode(j) as Map<String, Object?>);
    }
  }

  ConfigFile file(Dominio d) => _file[d]!;

  Future<void> salvaFile(Dominio d, ConfigFile c) async {
    _file[d] = c;
    await _p.setString(d.chiave, jsonEncode(c.perJson()));
  }

  Future<void> scollega(Dominio d) => salvaFile(d, ConfigFile(abilitato: d == Dominio.listino));

  Future<void> salvaIntestazione(Intestazione i) async {
    intestazione = i;
    await _p.setString('intestazione', jsonEncode(i.perJson()));
  }

  Future<void> salvaCommissione(ConfigCommissione c) async {
    commissione = c;
    await _p.setDouble('commissione_percentuale', c.percentualeDefault);
    await _p.setString('commissione_base', c.baseCalcolo);
  }

  /// Le cifre della home nascoste (come in un'app della banca).
  bool get cifreNascoste => _p.getBool('cifre_nascoste') ?? true;
  Future<void> nascondiCifre(bool si) => _p.setBool('cifre_nascoste', si);

  // ───────────────────────── recupero dalla versione Kotlin ─────────────────────────

  Future<void> _recuperaVecchie() async {
    try {
      if (Platform.isAndroid) {
        final files = await getApplicationSupportDirectory(); // /data/user/0/<pacchetto>/files
        Map<String, Object?> leggi(String nome) {
          final f = File('${files.path}/datastore/$nome.preferences_pb');
          return f.existsSync() ? leggiDataStore(f.readAsBytesSync()) : const {};
        }

        String s(Map<String, Object?> m, String k) => m[k] is String ? m[k] as String : '';
        int n(Map<String, Object?> m, String k) => m[k] is int ? m[k] as int : 0;

        final it = leggi('tk_intestazione');
        if (it.isNotEmpty) {
          await _p.setString(
              'intestazione',
              jsonEncode(Intestazione(
                ragioneSociale: s(it, 'ragione_sociale'),
                indirizzo: s(it, 'indirizzo'),
                cap: s(it, 'cap'),
                citta: s(it, 'citta'),
                provincia: s(it, 'provincia'),
                piva: s(it, 'piva'),
                codiceFiscale: s(it, 'cf'),
                telefono: s(it, 'telefono'),
                email: s(it, 'email'),
                pec: s(it, 'pec'),
                sito: s(it, 'sito'),
                iban: s(it, 'iban'),
                noteFooter: s(it, 'note_footer'),
              ).perJson()));
        }

        final co = leggi('tk_commissione');
        final perc = co['percentuale_default'];
        if (perc is num) await _p.setDouble('commissione_percentuale', perc.toDouble());
        if (s(co, 'base_calcolo').isNotEmpty) await _p.setString('commissione_base', s(co, 'base_calcolo'));

        final li = leggi('tk_listino_sync');
        if (s(li, 'uri').isNotEmpty) {
          await _p.setString(
              Dominio.listino.chiave,
              jsonEncode(ConfigFile(
                uri: s(li, 'uri'),
                nome: s(li, 'nome_file'),
                abilitato: li['abilitato'] != false, // di serie acceso
                ultimo: n(li, 'ultimo_import'),
                modificato: n(li, 'ultimo_file_modified'),
                dimensione: n(li, 'ultimo_file_size'),
                hash: s(li, 'ultimo_hash_scritto'),
              ).perJson()));
        }

        for (final (d, nome) in [(Dominio.clienti, 'tk_clienti_sync'), (Dominio.preventivi, 'tk_preventivi_sync')]) {
          final m = leggi(nome);
          if (s(m, 'file_uri').isEmpty) continue;
          await _p.setString(
              d.chiave,
              jsonEncode(ConfigFile(
                uri: s(m, 'file_uri'),
                nome: s(m, 'nome_visualizzato'),
                abilitato: m['abilitato'] == true,
                ultimo: n(m, 'ultimo_backup'),
                hash: s(m, 'ultimo_hash_scritto'),
              ).perJson()));
        }
      }
    } catch (_) {
      // se non si riescono a leggere si ricollegano a mano: i dati sono nel database
    }
    await _p.setBool('migrato', true);
  }
}

/// Legge un file Preferences DataStore (protobuf PreferenceMap): chiave → bool / int / double / testo.
Map<String, Object?> leggiDataStore(Uint8List dati) {
  var i = 0;
  late Uint8List b;

  int varint() {
    var risultato = 0, scorrimento = 0;
    while (true) {
      final x = b[i++];
      risultato |= (x & 0x7f) << scorrimento;
      if (x & 0x80 == 0) return risultato;
      scorrimento += 7;
    }
  }

  Uint8List pezzo() {
    final n = varint();
    final r = Uint8List.sublistView(b, i, i + n);
    i += n;
    return r;
  }

  void salta(int tipo) {
    switch (tipo) {
      case 0:
        varint();
      case 1:
        i += 8;
      case 2:
        pezzo();
      case 5:
        i += 4;
    }
  }

  // legge un messaggio annidato e poi torna al punto di prima
  T dentro<T>(Uint8List m, T Function() lettura) {
    final bPrima = b, iPrima = i;
    b = m;
    i = 0;
    try {
      return lettura();
    } finally {
      b = bPrima;
      i = iPrima;
    }
  }

  Object? valore(Uint8List v) => dentro(v, () {
        Object? r;
        while (i < b.length) {
          final t = varint();
          final campo = t >> 3, tipo = t & 7;
          if (campo == 1 && tipo == 0) {
            r = varint() != 0; // boolean
          } else if (campo == 2 && tipo == 5) {
            r = ByteData.sublistView(b, i, i + 4).getFloat32(0, Endian.little); // float
            i += 4;
          } else if ((campo == 3 || campo == 4) && tipo == 0) {
            r = varint(); // integer / long
          } else if (campo == 5 && tipo == 2) {
            r = utf8.decode(pezzo()); // string
          } else if (campo == 7 && tipo == 1) {
            r = ByteData.sublistView(b, i, i + 8).getFloat64(0, Endian.little); // double
            i += 8;
          } else {
            salta(tipo);
          }
        }
        return r;
      });

  final out = <String, Object?>{};
  b = dati;
  while (i < b.length) {
    final tag = varint();
    if (tag >> 3 == 1 && tag & 7 == 2) {
      final voce = pezzo();
      dentro(voce, () {
        String? chiave;
        Object? v;
        while (i < b.length) {
          final t = varint();
          if (t >> 3 == 1 && t & 7 == 2) {
            chiave = utf8.decode(pezzo());
          } else if (t >> 3 == 2 && t & 7 == 2) {
            v = valore(pezzo());
          } else {
            salta(t & 7);
          }
        }
        if (chiave != null) out[chiave] = v;
      });
    } else {
      salta(tag & 7);
    }
  }
  return out;
}
