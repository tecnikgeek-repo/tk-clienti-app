// File dei clienti (+ intestazione PDF) e dei preventivi (+ righe + movimenti), come la versione Kotlin
// (BackupManager): stesso formato, stesso ordine dei campi, stessa impronta SHA-256.
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'json_android.dart';
import 'modelli.dart';

const versioneBackup = 1;

class Contenuto {
  Contenuto(this.byte, this.conteggi);

  final List<int> byte;
  final Map<String, int> conteggi;

  String get hash => sha256.convert(byte).toString();
}

/// NB: niente data di esportazione dentro, se no l'impronta cambierebbe a ogni salvataggio.
Contenuto serializzaClienti(List<Cliente> clienti, Intestazione intestazione) {
  final ordinati = [...clienti]..sort((a, b) => a.id.compareTo(b.id));
  final radice = {
    'version': versioneBackup,
    'tipo': 'clienti',
    'intestazione': intestazione.perJson(),
    'clienti': [for (final c in ordinati) c.perDb()],
  };
  return Contenuto(utf8.encode(jsonAndroid(radice)), {'clienti': ordinati.length});
}

Contenuto serializzaPreventivi(List<Preventivo> prev, List<RigaPreventivo> righe, List<Movimento> mov) {
  final p = [...prev]..sort((a, b) => a.id.compareTo(b.id));
  final r = [...righe]..sort((a, b) => a.id.compareTo(b.id));
  final m = [...mov]..sort((a, b) => a.id.compareTo(b.id));
  final radice = {
    'version': versioneBackup,
    'tipo': 'solo-preventivi',
    'preventivi': [for (final x in p) x.perDb()],
    'righe_preventivo': [for (final x in r) x.perDb()],
    'movimenti': [for (final x in m) x.perDb()],
  };
  return Contenuto(utf8.encode(jsonAndroid(radice)), {
    'preventivi': p.length,
    'righe': r.length,
    'movimenti': m.length,
  });
}

Map<String, Object?> _radice(List<int> byte) {
  final testo = utf8.decode(byte, allowMalformed: true);
  final j = jsonDecode(testo.startsWith('﻿') ? testo.substring(1) : testo);
  if (j is! Map<String, Object?>) throw 'Il file non è un backup di tk-clienti';
  return j;
}

List<Map<String, Object?>> _lista(Object? v) =>
    v is List ? [for (final x in v) if (x is Map<String, Object?>) x] : const [];

class FileClienti {
  FileClienti(this.clienti, this.intestazione);
  final List<Cliente> clienti;
  final Intestazione? intestazione;
}

FileClienti leggiFileClienti(List<int> byte) {
  final j = _radice(byte);
  final versione = (j['version'] as num?)?.toInt() ?? 0;
  if (versione > versioneBackup) throw 'Versione del file ($versione) non supportata: aggiorna tk-clienti';
  if (j['clienti'] is! List) throw 'Nel file non ci sono clienti: forse hai scelto il file dei preventivi?';
  final it = j['intestazione'];
  return FileClienti(
    [for (final c in _lista(j['clienti'])) Cliente.daRiga(c)],
    it is Map<String, Object?> ? Intestazione.daJson(it) : null,
  );
}

class FilePreventivi {
  FilePreventivi(this.preventivi, this.righe, this.movimenti);
  final List<Preventivo> preventivi;
  final List<RigaPreventivo> righe;
  final List<Movimento> movimenti;
}

FilePreventivi leggiFilePreventivi(List<int> byte) {
  final j = _radice(byte);
  if (j['preventivi'] is! List) throw 'Nel file non ci sono preventivi: forse hai scelto il file dei clienti?';
  return FilePreventivi(
    [for (final x in _lista(j['preventivi'])) Preventivo.daRiga(x)],
    [for (final x in _lista(j['righe_preventivo'])) RigaPreventivo.daRiga(x)],
    [for (final x in _lista(j['movimenti'])) Movimento.daRiga(x)],
  );
}
