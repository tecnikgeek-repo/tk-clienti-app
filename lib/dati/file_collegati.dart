// File collegati su Drive, Dropbox o nel telefono, tramite il canale nativo (MainActivity.kt).
// Su Android il permesso resta al pacchetto: i file scelti con la versione Kotlin funzionano ancora.
// Su iPhone i file non restano collegati: si importa scegliendo il file e si esporta condividendolo.
import 'dart:io';

import 'package:flutter/services.dart';

const _canale = MethodChannel('it.pietrodefilippis.tkclienti/file');

/// Il collegamento permanente a un file c'è solo su Android.
bool get fileCollegabili => provaCollegabili ?? Platform.isAndroid;

/// Solo per le anteprime nei test (che girano sul PC).
bool? provaCollegabili;

class InfoFile {
  InfoFile(this.uri, this.nome, this.esiste, this.leggibile, this.dimensione, this.modificato);

  final String uri, nome;
  final bool esiste, leggibile;
  final int dimensione, modificato;

  static InfoFile? da(Object? r) {
    if (r is! Map) return null;
    return InfoFile(
      '${r['uri'] ?? ''}',
      '${r['nome'] ?? ''}',
      r['esiste'] == true,
      r['leggibile'] == true,
      (r['dimensione'] as num?)?.toInt() ?? 0,
      (r['modificato'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Fa scegliere un file esistente; null se si annulla. [scrittura] = l'app lo riscriverà.
Future<InfoFile?> scegliFile(List<String> tipi, {bool scrittura = false}) async =>
    InfoFile.da(await _canale.invokeMethod('apri', {'tipi': tipi, 'scrittura': scrittura}));

/// Fa creare un file nuovo (cartella a scelta: Drive, Dropbox, telefono); null se si annulla.
Future<InfoFile?> creaFile(String nome, String tipo) async =>
    InfoFile.da(await _canale.invokeMethod('crea', {'nome': nome, 'tipo': tipo}));

Future<InfoFile?> infoFile(String uri) async {
  try {
    return InfoFile.da(await _canale.invokeMethod('info', {'uri': uri}));
  } catch (_) {
    return null;
  }
}

Future<Uint8List> leggiFile(String uri) async {
  final r = await _canale.invokeMethod<Uint8List>('leggi', {'uri': uri});
  if (r == null) throw 'Impossibile leggere il file';
  return r;
}

/// Sovrascrive il file e ne restituisce i dati aggiornati (data di modifica, dimensione).
Future<InfoFile?> scriviFile(String uri, List<int> dati) async =>
    InfoFile.da(await _canale.invokeMethod('scrivi', {'uri': uri, 'dati': Uint8List.fromList(dati)}));

/// Condivide un file: prima prova le app in [pacchetti] (WhatsApp), poi la scelta di Android.
Future<void> condividiFile(String percorso,
        {String tipo = 'application/pdf',
        String? oggetto,
        String? testo,
        List<String> pacchetti = const [],
        String? email,
        String titolo = 'Condividi'}) =>
    _canale.invokeMethod('condividi', {
      'percorso': percorso,
      'tipo': tipo,
      'oggetto': oggetto,
      'testo': testo,
      'pacchetti': pacchetti,
      'email': email,
      'titolo': titolo,
    });

/// Apre il file con l'app del telefono (per il PDF: da lì si stampa).
Future<void> apriFileLocale(String percorso, {String tipo = 'application/pdf'}) =>
    _canale.invokeMethod('apriFile', {'percorso': percorso, 'tipo': tipo});
