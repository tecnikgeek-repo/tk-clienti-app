// tk-clienti per Android e iPhone — TecnikGeek (pietrodefilippis.it)
// Clienti, listino prodotti con magazzino, preventivi in PDF, commissioni agente;
// si sincronizza con i file collegati su Drive o Dropbox.
// Copyright (C) 2026 Pietro De Filippis (TecnikGeek) — AGPL-3.0-or-later, vedi COPYING
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

import 'app.dart';
import 'dati/archivio.dart';
import 'dati/database.dart';
import 'dati/impostazioni.dart';
import 'dati/sincronia.dart';
import 'schermate/home.dart';
import 'tema.dart';
import 'tk_licenza.dart';
import 'tk_pro.dart';

/// Errore non gestito dell'ultima volta (mostrato al riavvio per mandarlo a TecnikGeek).
String? crashPrecedente;
File? _fileCrash;

void _salvaCrash(Object errore, StackTrace? traccia) {
  try {
    _fileCrash?.writeAsStringSync('tk-clienti\n\n$errore\n\n${traccia ?? ''}');
  } catch (_) {}
}

Future<void> _inizializza() async {
  try {
    final supporto = await getApplicationSupportDirectory();
    _fileCrash = File('${supporto.path}/last_crash.txt');
    if (_fileCrash!.existsSync()) {
      final t = _fileCrash!.readAsStringSync();
      if (t.trim().isNotEmpty) crashPrecedente = t;
      _fileCrash!.deleteSync();
    }
  } catch (_) {}
  impostazioni = await Impostazioni.carica();
  await _copiaDiSicurezza();
  archivio = Archivio(await apriDatabase());
  await archivio.ricarica();
  sincronia = Sincronia(archivio, impostazioni);
  archivio.onModifica = sincronia.pianifica;
}

/// Al primo avvio della versione Flutter copia il database della versione Kotlin (una volta sola):
/// se qualcosa andasse storto i dati di prima restano recuperabili.
Future<void> _copiaDiSicurezza() async {
  try {
    final cartellaDb = await getDatabasesPath();
    final db = File('$cartellaDb/$nomeDatabase');
    if (!db.existsSync()) return;
    final supporto = await getApplicationSupportDirectory();
    final dest = Directory('${supporto.path}/copia-versione-kotlin');
    if (dest.existsSync()) return;
    dest.createSync(recursive: true);
    for (final suffisso in ['', '-wal', '-shm']) {
      final f = File('${db.path}$suffisso');
      if (f.existsSync()) f.copySync('${dest.path}/$nomeDatabase$suffisso');
    }
  } catch (_) {}
}

/// Benvenuto, statistiche (solo col consenso) e invito al caffè: tutte le funzioni sono per tutti.
Future<void> _avviaLicenza() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final lic = Licenza(slug: 'tk-clienti', versione: info.version);
    await lic.carica();
    proTk = ProTk(lic);
    lic.avvia(); // segnale del giorno in sottofondo, SOLO se l'utente ha detto sì alle statistiche
  } catch (_) {
    proTk = null; // senza memoria niente benvenuto né statistiche: l'app funziona lo stesso
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configTk = configClienti;
  registraLicenzaAgpl();
  await _avviaLicenza();
  FlutterError.onError = (d) {
    FlutterError.presentError(d);
    _salvaCrash(d.exception, d.stack);
  };
  PlatformDispatcher.instance.onError = (e, s) {
    _salvaCrash(e, s);
    return false;
  };
  runApp(AppClienti(avvio: _inizializza()));
}

class AppClienti extends StatelessWidget {
  const AppClienti({super.key, required this.avvio});

  final Future<void> avvio;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'tk-clienti',
        debugShowCheckedModeBanner: false,
        theme: temaKit(),
        locale: const Locale('it'),
        supportedLocales: const [Locale('it')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ConAvvio(
          child: FutureBuilder<void>(
            future: avvio,
            builder: (_, s) {
              if (s.hasError) return _ErroreAvvio('${s.error}');
              if (s.connectionState != ConnectionState.done) return const SchermataAvvio();
              return _CicloVita(child: SchermataHome(crash: crashPrecedente));
            },
          ),
        ),
      );
}

/// Secondo piano → salva subito i file in attesa; di nuovo in primo piano → scarica se un altro telefono ha salvato.
class _CicloVita extends StatefulWidget {
  const _CicloVita({required this.child});

  final Widget child;

  @override
  State<_CicloVita> createState() => _CicloVitaState();
}

class _CicloVitaState extends State<_CicloVita> {
  late final AppLifecycleListener _ascolto;

  @override
  void initState() {
    super.initState();
    _ascolto = AppLifecycleListener(
      onHide: () => sincronia.salvaInAttesa(),
      onResume: () => sincronia.inPrimoPiano(),
    );
  }

  @override
  void dispose() {
    _ascolto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ErroreAvvio extends StatelessWidget {
  const _ErroreAvvio(this.errore);

  final String errore;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: navy,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.error_outline_rounded, color: rosso, size: 56),
              const SizedBox(height: 14),
              const Text('Non riesco ad aprire i dati',
                  style: TextStyle(color: bianco, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(errore, textAlign: TextAlign.center, style: const TextStyle(color: grigio300)),
              const SizedBox(height: 14),
              const Text('I dati non sono stati toccati. Scrivi a TecnikGeek con questo messaggio.',
                  textAlign: TextAlign.center, style: TextStyle(color: grigio400, fontSize: 13)),
            ]),
          ),
        ),
      );
}
