// Archivio di tk-clienti: clienti e preventivi in memoria (sono pochi), articoli letti dal database
// a pagine (il listino può avere migliaia di righe). Le regole sono quelle della versione Kotlin
// (repository e DAO); in più gli import non rompono i vincoli tra le tabelle.
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'formati.dart';
import 'impostazioni.dart';
import 'modelli.dart';

class Archivio extends ChangeNotifier {
  Archivio(this.db);

  final Database db;

  List<Cliente> clienti = const [];
  List<Preventivo> preventivi = const [];
  int nArticoli = 0;

  /// Versione dei dati: cambia a ogni modifica (le schermate degli articoli la usano per rileggere).
  int giro = 0;

  /// Chiamata a ogni modifica fatta dall'utente: programma il salvataggio del file collegato.
  void Function(Dominio)? onModifica;

  void _modificato(Iterable<Dominio> domini) {
    for (final d in domini) {
      onModifica?.call(d);
    }
  }

  // ───────────────────────── lettura ─────────────────────────

  static int _perNome(Cliente a, Cliente b) {
    final c = a.cognome.toLowerCase().compareTo(b.cognome.toLowerCase());
    return c != 0 ? c : a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
  }

  Future<void> ricarica() async {
    clienti = [for (final r in await db.query('clienti')) Cliente.daRiga(r)]..sort(_perNome);
    preventivi = [for (final r in await db.query('preventivi')) Preventivo.daRiga(r)]
      ..sort((a, b) => b.data.compareTo(a.data));
    nArticoli = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM articoli')) ?? 0;
    giro++;
    notifyListeners();
  }

  Cliente? cliente(int id) {
    for (final c in clienti) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Ricerca come la versione Kotlin: nome e cognome (nei due ordini), telefono, email, P.IVA, città.
  List<Cliente> cercaClienti(String q) {
    final t = q.trim().toLowerCase();
    if (t.isEmpty) return clienti;
    return clienti
        .where((c) =>
            '${c.nome} ${c.cognome}'.toLowerCase().contains(t) ||
            '${c.cognome} ${c.nome}'.toLowerCase().contains(t) ||
            c.telefono.contains(t) ||
            c.email.toLowerCase().contains(t) ||
            c.piva.toLowerCase().contains(t) ||
            c.citta.toLowerCase().contains(t))
        .toList();
  }

  List<Preventivo> preventiviDi(int clienteId) => preventivi.where((p) => p.clienteId == clienteId).toList();

  String nomeCliente(int id) {
    final c = cliente(id);
    if (c == null) return 'Cliente eliminato';
    return c.nominativo.isEmpty ? '(senza nome)' : c.nominativo;
  }

  // ───────────────────────── clienti ─────────────────────────

  Future<int> salvaCliente(Cliente c) async {
    final ora = adesso();
    if (c.id == 0) {
      c.createdAt = ora;
      c.updatedAt = ora;
      c.id = await db.insert('clienti', c.perDb(conId: false));
    } else {
      c.updatedAt = ora;
      await db.update('clienti', c.perDb(conId: false), where: 'id = ?', whereArgs: [c.id]);
    }
    await ricarica();
    _modificato([Dominio.clienti]);
    return c.id;
  }

  /// Elimina il cliente; false se ha preventivi (il database lo impedisce, come nella versione Kotlin).
  Future<bool> eliminaCliente(Cliente c) async {
    if (preventiviDi(c.id).isNotEmpty) return false;
    await db.delete('clienti', where: 'id = ?', whereArgs: [c.id]);
    await ricarica();
    _modificato([Dominio.clienti]);
    return true;
  }

  // ───────────────────────── articoli ─────────────────────────

  /// Ricerca nel listino (codice, descrizione, EAN): prima il codice uguale, poi quelli che iniziano così.
  Future<List<Articolo>> cercaArticoli(String q, {int limite = 150}) async {
    final t = q.trim();
    final righe = t.isEmpty
        ? await db.rawQuery('SELECT * FROM articoli ORDER BY codice COLLATE NOCASE LIMIT ?', [limite])
        : await db.rawQuery('''
            SELECT * FROM articoli
            WHERE LOWER(codice) LIKE '%' || LOWER(?1) || '%'
               OR LOWER(descrizione) LIKE '%' || LOWER(?1) || '%'
               OR ean13 LIKE '%' || ?1 || '%'
            ORDER BY
              CASE WHEN LOWER(codice) = LOWER(?1) THEN 0
                   WHEN LOWER(codice) LIKE LOWER(?1) || '%' THEN 1
                   ELSE 2 END,
              codice COLLATE NOCASE
            LIMIT ?2''', [t, limite]);
    return [for (final r in righe) Articolo.daRiga(r)];
  }

  Future<Articolo?> articolo(int id) async {
    final r = await db.query('articoli', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : Articolo.daRiga(r.first);
  }

  Future<Articolo?> articoloPerCodice(String codice) async {
    final r = await db.query('articoli', where: 'codice = ?', whereArgs: [codice.trim()], limit: 1);
    return r.isEmpty ? null : Articolo.daRiga(r.first);
  }

  Future<List<Articolo>> tuttiArticoli() async =>
      [for (final r in await db.query('articoli', orderBy: 'codice COLLATE NOCASE')) Articolo.daRiga(r)];

  /// Salva un articolo; null se il codice è già di un altro articolo.
  Future<int?> salvaArticolo(Articolo a) async {
    final altro = await articoloPerCodice(a.codice);
    if (altro != null && altro.id != a.id) return null;
    final ora = adesso();
    if (a.id == 0) {
      a.createdAt = ora;
      a.updatedAt = ora;
      a.id = await db.insert('articoli', a.perDb(conId: false));
    } else {
      a.updatedAt = ora;
      await db.update('articoli', a.perDb(conId: false), where: 'id = ?', whereArgs: [a.id]);
    }
    await ricarica();
    _modificato([Dominio.listino]);
    return a.id;
  }

  Future<void> eliminaArticolo(Articolo a) async {
    await db.delete('articoli', where: 'id = ?', whereArgs: [a.id]); // i movimenti vanno via con lui
    await ricarica();
    _modificato([Dominio.listino, Dominio.preventivi]);
  }

  /// Svuota il magazzino (solo gli articoli): non riscrive il file del listino.
  Future<void> eliminaTuttiArticoli() async {
    await db.delete('articoli');
    await ricarica();
    _modificato([Dominio.preventivi]);
  }

  /// Carico/scarico: aggiorna la giacenza e registra il movimento.
  Future<Articolo> movimentaGiacenza(Articolo a, double delta, String tipo, String causale,
      {String riferimento = ''}) async {
    final precedente = a.giacenza;
    final nuova = precedente + delta;
    await db.transaction((t) async {
      await t.update('articoli', {'giacenza': nuova, 'updatedAt': adesso()}, where: 'id = ?', whereArgs: [a.id]);
      await t.insert(
          'movimenti_magazzino',
          Movimento(
            articoloId: a.id,
            tipo: tipo,
            quantita: delta,
            giacenzaPrecedente: precedente,
            giacenzaNuova: nuova,
            causale: causale,
            riferimento: riferimento,
          ).perDb(conId: false));
    });
    await ricarica();
    _modificato([Dominio.listino, Dominio.preventivi]);
    return (await articolo(a.id))!;
  }

  Future<List<Movimento>> movimenti(int articoloId) async => [
        for (final r in await db.query('movimenti_magazzino',
            where: 'articoloId = ?', whereArgs: [articoloId], orderBy: 'data DESC'))
          Movimento.daRiga(r)
      ];

  /// Articoli attuali per codice (la lettura del listino ne conserva i dati che il file non ha).
  Future<Map<String, Articolo>> articoliPerCodice() async {
    final m = <String, Articolo>{};
    for (final r in await db.query('articoli')) {
      final a = Articolo.daRiga(r);
      m[a.codice] = a;
    }
    return m;
  }

  /// Scrive gli articoli letti dal listino: aggiorna quelli che ci sono (id > 0, i movimenti restano),
  /// aggiunge i nuovi. Non avvisa la sincronizzazione: il file è già quello. Restituisce quanti ne ha scritti.
  Future<int> scriviListino(List<Articolo> articoli) async {
    await db.transaction((t) async {
      final b = t.batch();
      for (final a in articoli) {
        if (a.id > 0) {
          b.update('articoli', a.perDb(conId: false), where: 'id = ?', whereArgs: [a.id]);
        } else {
          b.insert('articoli', a.perDb(conId: false), conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
      await b.commit(noResult: true);
    });
    await ricarica();
    return articoli.length;
  }

  /// Toglie gli articoli del listino che non sono più nel file (quelli «manuali» restano).
  Future<int> togliListinoAssenti(Set<String> codiciPresenti) async {
    if (codiciPresenti.isEmpty) return 0;
    final daTogliere = [
      for (final r in await db.query('articoli', columns: ['id', 'codice'], where: 'origine = ?', whereArgs: [origineListino]))
        if (!codiciPresenti.contains(r['codice'])) r['id'] as int
    ];
    for (var i = 0; i < daTogliere.length; i += 500) {
      final pezzo = daTogliere.sublist(i, (i + 500).clamp(0, daTogliere.length));
      await db.delete('articoli', where: 'id IN (${List.filled(pezzo.length, '?').join(',')})', whereArgs: pezzo);
    }
    if (daTogliere.isNotEmpty) await ricarica();
    return daTogliere.length;
  }

  // ───────────────────────── preventivi ─────────────────────────

  Future<PreventivoConRighe?> preventivoConRighe(int id) async {
    final r = await db.query('preventivi', where: 'id = ?', whereArgs: [id]);
    if (r.isEmpty) return null;
    final righe = [
      for (final x in await db.query('righe_preventivo', where: 'preventivoId = ?', whereArgs: [id], orderBy: 'ordine'))
        RigaPreventivo.daRiga(x)
    ];
    return PreventivoConRighe(Preventivo.daRiga(r.first), righe);
  }

  /// Numero «2026-007»: il più alto dell'anno + 1 (mai il conteggio: con dei buchi ripeterebbe un numero).
  Future<String> generaNumero([DatabaseExecutor? e]) async {
    final prefisso = '${DateTime.now().year}-';
    final righe = await (e ?? db)
        .rawQuery("SELECT numero FROM preventivi WHERE numero LIKE ? || '%'", [prefisso]);
    var massimo = 0;
    for (final r in righe) {
      final n = int.tryParse('${r['numero']}'.substring(prefisso.length));
      if (n != null && n > massimo) massimo = n;
    }
    return '$prefisso${(massimo + 1).toString().padLeft(3, '0')}';
  }

  /// Salva testata e righe insieme; restituisce l'id del preventivo.
  Future<int> salvaPreventivo(Preventivo p, List<RigaPreventivo> righe) async {
    final ora = adesso();
    await db.transaction((t) async {
      if (p.id == 0) {
        if (p.numero.isEmpty) p.numero = await generaNumero(t);
        p.createdAt = ora;
        p.updatedAt = ora;
        p.id = await t.insert('preventivi', p.perDb(conId: false));
      } else {
        p.updatedAt = ora;
        await t.update('preventivi', p.perDb(conId: false), where: 'id = ?', whereArgs: [p.id]);
      }
      await t.delete('righe_preventivo', where: 'preventivoId = ?', whereArgs: [p.id]);
      for (var i = 0; i < righe.length; i++) {
        final r = righe[i].copia()
          ..preventivoId = p.id
          ..ordine = i;
        await t.insert('righe_preventivo', r.perDb(conId: false));
      }
    });
    await ricarica();
    _modificato([Dominio.preventivi]);
    return p.id;
  }

  Future<void> cambiaStato(Preventivo p, String stato) async {
    await db.update('preventivi', {'stato': stato, 'updatedAt': adesso()}, where: 'id = ?', whereArgs: [p.id]);
    await ricarica();
    _modificato([Dominio.preventivi]);
  }

  Future<void> eliminaPreventivo(Preventivo p) async {
    await db.delete('preventivi', where: 'id = ?', whereArgs: [p.id]); // le righe vanno via con lui
    await ricarica();
    _modificato([Dominio.preventivi]);
  }

  // ───────────────────────── copie complete (file clienti / preventivi) ─────────────────────────

  Future<List<Cliente>> tuttiClienti() async =>
      [for (final r in await db.query('clienti', orderBy: 'id')) Cliente.daRiga(r)];

  Future<List<Preventivo>> tuttiPreventivi() async =>
      [for (final r in await db.query('preventivi', orderBy: 'id')) Preventivo.daRiga(r)];

  Future<List<RigaPreventivo>> tutteRighe() async =>
      [for (final r in await db.query('righe_preventivo', orderBy: 'id')) RigaPreventivo.daRiga(r)];

  Future<List<Movimento>> tuttiMovimenti() async =>
      [for (final r in await db.query('movimenti_magazzino', orderBy: 'id')) Movimento.daRiga(r)];

  /// Sostituisce i clienti con quelli del file. Chi ha preventivi nel telefono ma non è nel file resta
  /// (altrimenti i preventivi resterebbero senza cliente). Restituisce quanti ne ha tenuti così.
  Future<int> sostituisciClienti(List<Cliente> nuovi) async {
    var tenuti = 0;
    await db.transaction((t) async {
      final ids = {for (final c in nuovi) c.id};
      final conPreventivi = {
        for (final r in await t.rawQuery('SELECT DISTINCT clienteId FROM preventivi')) (r['clienteId'] as num).toInt()
      };
      final presenti = {for (final r in await t.query('clienti', columns: ['id'])) r['id'] as int};
      for (final id in presenti) {
        if (ids.contains(id)) continue;
        if (conPreventivi.contains(id)) {
          tenuti++;
        } else {
          await t.delete('clienti', where: 'id = ?', whereArgs: [id]);
        }
      }
      for (final c in nuovi) {
        if (presenti.contains(c.id)) {
          await t.update('clienti', c.perDb(conId: false), where: 'id = ?', whereArgs: [c.id]);
        } else {
          await t.insert('clienti', c.perDb());
        }
      }
    });
    await ricarica();
    return tenuti;
  }

  /// Sostituisce preventivi, righe e movimenti con quelli del file. Se un preventivo è di un cliente
  /// che nel telefono non c'è, non tocca niente (prima vanno scaricati i clienti). I movimenti di articoli
  /// che qui non esistono si saltano. Restituisce quanti movimenti ha saltato.
  Future<int> sostituisciPreventivi(List<Preventivo> prev, List<RigaPreventivo> righe, List<Movimento> mov) async {
    final idClienti = {for (final r in await db.query('clienti', columns: ['id'])) r['id'] as int};
    final senzaCliente = prev.where((p) => !idClienti.contains(p.clienteId)).length;
    if (senzaCliente > 0) {
      throw 'Nel file ci sono $senzaCliente preventivi di clienti che non sono nel telefono: '
          'scarica prima il file dei clienti';
    }
    final idArticoli = {for (final r in await db.query('articoli', columns: ['id'])) r['id'] as int};
    final idPrev = {for (final p in prev) p.id};
    var saltati = 0;
    await db.transaction((t) async {
      await t.delete('righe_preventivo');
      await t.delete('preventivi');
      await t.delete('movimenti_magazzino');
      final b = t.batch();
      for (final p in prev) {
        b.insert('preventivi', p.perDb(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final r in righe) {
        if (idPrev.contains(r.preventivoId)) b.insert('righe_preventivo', r.perDb());
      }
      for (final m in mov) {
        if (idArticoli.contains(m.articoloId)) {
          b.insert('movimenti_magazzino', m.perDb());
        } else {
          saltati++;
        }
      }
      await b.commit(noResult: true);
    });
    await ricarica();
    return saltati;
  }
}
