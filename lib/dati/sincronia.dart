// Sincronizzazione dei tre file collegati, come la versione Kotlin (modello 2.8.0):
//  - LISTINO (articoli)  → file Excel/CSV modificato sul PC; l'app lo rilegge e riscrive l'Excel con gli articoli manuali
//  - CLIENTI (+ intestazione PDF) → clienti.json
//  - PREVENTIVI (+ righe + movimenti) → preventivi.json
// Ogni modifica programma un salvataggio dopo 2 minuti (Dropbox/Drive finiscono di caricare il precedente);
// quando l'app va in secondo piano si salva subito; quando torna in primo piano si scarica se il file è più nuovo.
// Impronta SHA-256: se il contenuto non cambia non si riscrive (niente copie in conflitto).
import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'archivio.dart';
import 'backup.dart';
import 'file_collegati.dart';
import 'formati.dart';
import 'impostazioni.dart';
import 'listino.dart';

class Esito {
  const Esito(this.ok, this.messaggio, [this.conteggi = const {}]);

  final bool ok;
  final String messaggio;
  final Map<String, int> conteggi;
}

class Sincronia extends ChangeNotifier {
  Sincronia(this.archivio, this.impostazioni);

  final Archivio archivio;
  final Impostazioni impostazioni;

  static const ritardo = Duration(minutes: 2);

  final Map<Dominio, Timer> _timer = {};
  final Set<Dominio> _inAttesa = {};
  final Map<Dominio, Future<void>> _fila = {};

  /// Domini con un'operazione in corso (la card nelle Impostazioni mostra la barra).
  final Set<Dominio> occupati = {};

  /// Le operazioni sullo stesso file vanno una alla volta.
  Future<T> _inFila<T>(Dominio d, Future<T> Function() lavoro) {
    final c = Completer<T>();
    final prima = _fila[d] ?? Future.value();
    _fila[d] = prima.then((_) async {
      occupati.add(d);
      notifyListeners();
      try {
        c.complete(await lavoro());
      } catch (e, s) {
        c.completeError(e, s);
      } finally {
        occupati.remove(d);
        notifyListeners();
      }
    });
    return c.future;
  }

  // ───────────────────────── salvataggio programmato ─────────────────────────

  /// Dopo una modifica: salva il file tra 2 minuti (le modifiche ravvicinate fanno un salvataggio solo).
  void pianifica(Dominio d) {
    if (!fileCollegabili || !impostazioni.file(d).collegato) return;
    _inAttesa.add(d);
    _timer[d]?.cancel();
    _timer[d] = Timer(ritardo, () => salva(d, forza: false));
  }

  /// App in secondo piano: salva subito quello che aspettava.
  Future<void> salvaInAttesa() async {
    for (final d in [..._inAttesa]) {
      _timer[d]?.cancel();
      try {
        await salva(d, forza: false);
      } catch (_) {}
    }
  }

  /// All'avvio: rilegge il listino se il file è cambiato, poi scarica clienti e preventivi se più nuovi.
  Future<void> allAvvio() async {
    if (!fileCollegabili) return;
    try {
      await listinoDaFile(forza: false);
    } catch (_) {}
    await inPrimoPiano();
  }

  /// App di nuovo in primo piano: un altro telefono può aver salvato i file.
  Future<void> inPrimoPiano() async {
    if (!fileCollegabili) return;
    for (final d in [Dominio.clienti, Dominio.preventivi]) {
      try {
        await scaricaSePiuNuovo(d);
      } catch (_) {}
    }
  }

  // ───────────────────────── contenuti ─────────────────────────

  Future<Contenuto> contenuto(Dominio d) async => switch (d) {
        Dominio.clienti => serializzaClienti(await archivio.tuttiClienti(), impostazioni.intestazione),
        Dominio.preventivi => serializzaPreventivi(
            await archivio.tuttiPreventivi(), await archivio.tutteRighe(), await archivio.tuttiMovimenti()),
        Dominio.listino => throw StateError('Il listino non è un file JSON'),
      };

  static String _nome(Dominio d) => switch (d) {
        Dominio.listino => 'Listino',
        Dominio.clienti => 'Clienti',
        Dominio.preventivi => 'Preventivi',
      };

  // ───────────────────────── scrittura ─────────────────────────

  /// Scrive il file del dominio. [forza] = anche con la sincronizzazione automatica spenta (pulsante).
  Future<Esito> salva(Dominio d, {bool forza = true}) =>
      _inFila(d, () => d == Dominio.listino ? _salvaListino(forza) : _salvaJson(d, forza));

  Future<Esito> _salvaJson(Dominio d, bool forza) async {
    final cfg = impostazioni.file(d);
    final nome = _nome(d);
    if (!cfg.collegato) return Esito(false, 'File ${nome.toLowerCase()} non collegato');
    if (!cfg.abilitato && !forza) return Esito(false, 'Sincronizzazione ${nome.toLowerCase()} spenta');
    // dopo una reinstallazione il telefono è vuoto: non si cancella il file, prima lo si scarica
    if (d == Dominio.clienti && archivio.clienti.isEmpty) {
      return const Esito(false, 'Bloccato: nessun cliente nel telefono. Usa «Scarica dal file» per riprenderli dal cloud.');
    }
    if (d == Dominio.preventivi && archivio.preventivi.isEmpty && (await archivio.tuttiMovimenti()).isEmpty) {
      return const Esito(
          false, 'Bloccato: nessun preventivo nel telefono. Usa «Scarica dal file» per riprenderli dal cloud.');
    }
    _inAttesa.remove(d);
    final c = await contenuto(d);
    final hash = c.hash;
    if (hash == cfg.hash) {
      cfg.ultimo = adesso();
      await impostazioni.salvaFile(d, cfg);
      return Esito(true, '$nome già aggiornati', c.conteggi);
    }
    final info = await scriviFile(cfg.uri, c.byte);
    cfg
      ..ultimo = info?.modificato ?? adesso()
      ..hash = hash;
    await impostazioni.salvaFile(d, cfg);
    return Esito(true, '$nome salvati sul cloud', c.conteggi);
  }

  Future<Esito> _salvaListino(bool forza) async {
    final cfg = impostazioni.file(Dominio.listino);
    if (!cfg.collegato) return const Esito(false, 'Nessun file del listino collegato');
    if (!cfg.abilitato && !forza) return const Esito(false, 'Sincronizzazione del listino spenta');
    _inAttesa.remove(Dominio.listino);
    final articoli = await archivio.tuttiArticoli();
    if (articoli.isEmpty) return const Esito(false, 'Nessun articolo da scrivere');
    if (!cfg.nome.toLowerCase().endsWith('.xlsx')) {
      return const Esito(false, 'Si può riscrivere solo un file Excel (.xlsx): il CSV si aggiorna dal PC');
    }
    final hash = hashArticoli(articoli);
    if (hash == cfg.hash) {
      return Esito(true, 'Listino già aggiornato (${articoli.length} articoli)', {'articoli': articoli.length});
    }
    final info = await scriviFile(cfg.uri, scriviXlsx(articoli));
    cfg
      ..modificato = info?.modificato ?? adesso()
      ..dimensione = info?.dimensione ?? 0
      ..hash = hash;
    await impostazioni.salvaFile(Dominio.listino, cfg);
    return Esito(true, 'File Excel aggiornato (${articoli.length} articoli)', {'articoli': articoli.length});
  }

  // ───────────────────────── lettura ─────────────────────────

  /// Rilegge il listino dal file collegato; senza [forza] solo se il file è cambiato.
  Future<Esito> listinoDaFile({bool forza = true}) => _inFila(Dominio.listino, () async {
        final cfg = impostazioni.file(Dominio.listino);
        if (!cfg.collegato) return const Esito(false, 'Nessun file collegato');
        if (!cfg.abilitato && !forza) return const Esito(true, 'Sincronizzazione spenta');
        final info = await infoFile(cfg.uri);
        if (info == null || !info.esiste || !info.leggibile) return const Esito(false, 'File non accessibile');
        // Drive spesso dà la data di modifica a 0: si guarda anche la dimensione
        if (!forza && cfg.ultimo > 0) {
          final stessaData = info.modificato > 0 && info.modificato <= cfg.modificato;
          final stessaDimensione = info.dimensione > 0 && info.dimensione == cfg.dimensione;
          if (stessaData && (stessaDimensione || cfg.dimensione == 0)) {
            return const Esito(true, 'Listino già aggiornato');
          }
        }
        final nome = info.nome.isNotEmpty ? info.nome : cfg.nome;
        final esito = await _importaListino(await leggiFile(cfg.uri), nome);
        cfg
          ..nome = nome
          ..ultimo = adesso()
          ..modificato = info.modificato
          ..dimensione = info.dimensione;
        await impostazioni.salvaFile(Dominio.listino, cfg);
        return esito;
      });

  Future<Esito> _importaListino(Uint8List dati, String nome) async {
    final lettura = leggiListino(dati, nome, await archivio.articoliPerCodice());
    if (lettura.articoli.isEmpty && lettura.errori.isNotEmpty && lettura.codiciVisti.isEmpty) {
      return Esito(false, lettura.errori.first);
    }
    final scritti = await archivio.scriviListino(lettura.articoli);
    // tolti solo gli articoli del listino spariti dal file; quelli aggiunti a mano restano
    var tolti = 0;
    if (lettura.codiciVisti.isNotEmpty && lettura.errori.isEmpty) {
      tolti = await archivio.togliListinoAssenti(lettura.codiciVisti);
    }
    if (lettura.errori.isNotEmpty) {
      return Esito(false, 'Aggiornato con avvisi: ${lettura.errori.length} righe ignorate (${lettura.errori.first})',
          {'articoli': scritti, 'righe': lettura.totali});
    }
    return Esito(
        true,
        'Listino aggiornato: $scritti articoli su ${lettura.totali} righe'
        '${tolti > 0 ? ', tolti $tolti non più nel file' : ''}',
        {'articoli': scritti, 'righe': lettura.totali});
  }

  /// Listino scelto al volo (iPhone): lo legge senza collegarlo.
  Future<Esito> importaListinoByte(Uint8List dati, String nome) =>
      _inFila(Dominio.listino, () => _importaListino(dati, nome));

  /// Collega un file del listino appena scelto e lo legge.
  Future<Esito> collegaListino(InfoFile f) async {
    await impostazioni.salvaFile(Dominio.listino, ConfigFile(uri: f.uri, nome: f.nome, abilitato: true));
    return listinoDaFile();
  }

  /// Importa clienti o preventivi dal file collegato (sovrascrive quelli del telefono).
  Future<Esito> scarica(Dominio d) => _inFila(d, () => _scarica(d));

  Future<Esito> _scarica(Dominio d) async {
    final cfg = impostazioni.file(d);
    if (!cfg.collegato) return Esito(false, 'File ${_nome(d).toLowerCase()} non collegato');
    final dati = await leggiFile(cfg.uri);
    final esito = await importaByte(d, dati);
    if (!esito.ok) return esito;
    final info = await infoFile(cfg.uri);
    final c = await contenuto(d);
    // se nel telefono è rimasto qualcosa in più del file, l'impronta resta quella del file: verrà salvato
    cfg
      ..ultimo = info?.modificato ?? adesso()
      ..hash = esito.conteggi['tenuti'] == 0 ? c.hash : sha256.convert(dati).toString();
    await impostazioni.salvaFile(d, cfg);
    return esito;
  }

  /// Importa il contenuto di un file clienti/preventivi (anche scelto al volo, su iPhone).
  Future<Esito> importaByte(Dominio d, List<int> dati) async {
    try {
      if (d == Dominio.clienti) {
        final f = leggiFileClienti(dati);
        final tenuti = await archivio.sostituisciClienti(f.clienti);
        if (f.intestazione != null) await impostazioni.salvaIntestazione(f.intestazione!);
        return Esito(
            true,
            'Clienti ripresi dal file: ${f.clienti.length}'
            '${tenuti > 0 ? ' (+ $tenuti che hanno preventivi nel telefono)' : ''}',
            {'clienti': f.clienti.length, 'tenuti': tenuti});
      }
      final f = leggiFilePreventivi(dati);
      final saltati = await archivio.sostituisciPreventivi(f.preventivi, f.righe, f.movimenti);
      return Esito(
          true,
          'Preventivi ripresi dal file: ${f.preventivi.length} (${f.righe.length} righe)'
          '${saltati > 0 ? ' · $saltati movimenti di articoli che qui non ci sono' : ''}',
          {'preventivi': f.preventivi.length, 'righe': f.righe.length, 'tenuti': 0});
    } catch (e) {
      return Esito(false, '$e');
    }
  }

  /// Se il file sul cloud è più nuovo e nel telefono non ci sono modifiche da caricare, lo importa.
  Future<Esito?> scaricaSePiuNuovo(Dominio d) => _inFila(d, () async {
        final cfg = impostazioni.file(d);
        if (!cfg.collegato || !cfg.abilitato) return null;
        final info = await infoFile(cfg.uri);
        if (info == null || !info.esiste) return null;
        if (info.modificato <= cfg.ultimo + 1000) return null;
        final locale = (await contenuto(d)).hash;
        if (cfg.hash.isNotEmpty && locale != cfg.hash) {
          return Esito(false,
              '${_nome(d)} del telefono non ancora salvati: prima «Carica nel file ora», poi «Scarica dal file»');
        }
        final e = await _scarica(d);
        return e.ok ? Esito(true, '${_nome(d)} aggiornati dal cloud', e.conteggi) : e;
      });

  /// Collega un file clienti/preventivi esistente; se nel telefono non c'è niente lo importa subito.
  Future<Esito> collegaEsistente(Dominio d, InfoFile f) async {
    final cfg = impostazioni.file(d)
      ..uri = f.uri
      ..nome = f.nome.isEmpty ? '${d.name}.json' : f.nome
      ..abilitato = true;
    await impostazioni.salvaFile(d, cfg);
    final vuoto = d == Dominio.clienti ? archivio.clienti.isEmpty : archivio.preventivi.isEmpty;
    if (vuoto) return scarica(d);
    return const Esito(true, 'File collegato. Usa «Scarica dal file» per prenderne i dati.');
  }

  /// Collega un file nuovo appena creato e ci scrive i dati del telefono.
  Future<Esito> collegaNuovo(Dominio d, InfoFile f) async {
    final cfg = impostazioni.file(d)
      ..uri = f.uri
      ..nome = f.nome.isEmpty ? '${d.name}.json' : f.nome
      ..abilitato = true
      ..hash = '';
    await impostazioni.salvaFile(d, cfg);
    return salva(d);
  }

  // ───────────────────────── tutto insieme (trascina giù per aggiornare) ─────────────────────────

  Future<String> sincronizzaTutto() async {
    if (!fileCollegabili) return 'Su iPhone i dati si importano ed esportano dalle Impostazioni';
    final parti = <String>[];
    final l = impostazioni.file(Dominio.listino);
    if (l.collegato) {
      final letto = await listinoDaFile();
      parti.add(letto.ok ? 'Listino: ${letto.conteggi['articoli'] ?? 0} articoli' : 'Listino: ${letto.messaggio}');
      if (l.nome.toLowerCase().endsWith('.xlsx')) {
        final scritto = await salva(Dominio.listino);
        if (!scritto.ok) parti.add(scritto.messaggio);
      }
    }
    for (final d in [Dominio.clienti, Dominio.preventivi]) {
      if (!impostazioni.file(d).collegato) continue;
      final giu = await scaricaSePiuNuovo(d);
      if (giu != null) parti.add(giu.ok ? '${_nome(d)} scaricati' : giu.messaggio);
      final su = await salva(d);
      parti.add(su.ok ? '${_nome(d)}: ok' : su.messaggio);
    }
    return parti.isEmpty ? 'Nessun file collegato: collegali dalle Impostazioni' : parti.join(' · ');
  }
}
