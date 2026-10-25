// Database di tk-clienti: è LO STESSO FILE della versione Kotlin (tk_clienti.db, schema 3 di Room),
// così chi aggiorna ritrova clienti, articoli, preventivi e movimenti senza fare niente.
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

const nomeDatabase = 'tk_clienti.db';
const versioneDatabase = 3;

/// Schema identico a quello creato da Room alla versione 3 (per chi installa da zero).
const _schema = [
  'CREATE TABLE IF NOT EXISTS clienti (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, nome TEXT NOT NULL, '
      'cognome TEXT NOT NULL, telefono TEXT NOT NULL, email TEXT NOT NULL, piva TEXT NOT NULL, '
      'codiceFiscale TEXT NOT NULL, codiceSdi TEXT NOT NULL, pec TEXT NOT NULL, indirizzo TEXT NOT NULL, '
      'cap TEXT NOT NULL, citta TEXT NOT NULL, provincia TEXT NOT NULL, note TEXT NOT NULL, tag TEXT NOT NULL, '
      'commissionePerc REAL NOT NULL, createdAt INTEGER NOT NULL, updatedAt INTEGER NOT NULL)',
  'CREATE TABLE IF NOT EXISTS articoli (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, codice TEXT NOT NULL, '
      'descrizione TEXT NOT NULL, prezzoListino REAL NOT NULL, prezzoRivenditore REAL NOT NULL, pagina INTEGER, '
      'ean13 TEXT NOT NULL, giacenza REAL NOT NULL, unitaMisura TEXT NOT NULL, categoria TEXT NOT NULL, '
      'note TEXT NOT NULL, origine TEXT NOT NULL, createdAt INTEGER NOT NULL, updatedAt INTEGER NOT NULL)',
  'CREATE UNIQUE INDEX IF NOT EXISTS index_articoli_codice ON articoli (codice)',
  'CREATE TABLE IF NOT EXISTS preventivi (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, numero TEXT NOT NULL, '
      'clienteId INTEGER NOT NULL, data INTEGER NOT NULL, validita INTEGER NOT NULL, ivaPercentuale REAL NOT NULL, '
      'scontoGlobale REAL NOT NULL, totaleImponibile REAL NOT NULL, totaleIva REAL NOT NULL, totale REAL NOT NULL, '
      'note TEXT NOT NULL, stato TEXT NOT NULL, commissionePerc REAL NOT NULL, createdAt INTEGER NOT NULL, '
      'updatedAt INTEGER NOT NULL, '
      'FOREIGN KEY(clienteId) REFERENCES clienti(id) ON UPDATE NO ACTION ON DELETE RESTRICT )',
  'CREATE INDEX IF NOT EXISTS index_preventivi_clienteId ON preventivi (clienteId)',
  'CREATE UNIQUE INDEX IF NOT EXISTS index_preventivi_numero ON preventivi (numero)',
  'CREATE TABLE IF NOT EXISTS righe_preventivo (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'preventivoId INTEGER NOT NULL, ordine INTEGER NOT NULL, codice TEXT NOT NULL, descrizione TEXT NOT NULL, '
      'quantita REAL NOT NULL, unitaMisura TEXT NOT NULL, prezzoUnitario REAL NOT NULL, '
      'scontoPercentuale REAL NOT NULL, articoloId INTEGER, '
      'FOREIGN KEY(preventivoId) REFERENCES preventivi(id) ON UPDATE NO ACTION ON DELETE CASCADE )',
  'CREATE INDEX IF NOT EXISTS index_righe_preventivo_preventivoId ON righe_preventivo (preventivoId)',
  'CREATE TABLE IF NOT EXISTS movimenti_magazzino (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'articoloId INTEGER NOT NULL, tipo TEXT NOT NULL, quantita REAL NOT NULL, giacenzaPrecedente REAL NOT NULL, '
      'giacenzaNuova REAL NOT NULL, causale TEXT NOT NULL, riferimento TEXT NOT NULL, data INTEGER NOT NULL, '
      'FOREIGN KEY(articoloId) REFERENCES articoli(id) ON UPDATE NO ACTION ON DELETE CASCADE )',
  'CREATE INDEX IF NOT EXISTS index_movimenti_magazzino_articoloId ON movimenti_magazzino (articoloId)',
  'CREATE INDEX IF NOT EXISTS index_movimenti_magazzino_data ON movimenti_magazzino (data)',
];

/// Le migrazioni della versione Kotlin, per un telefono rimasto a una versione vecchia.
Future<void> _migra(Database db, int da) async {
  if (da < 2) {
    // 1 → 2 (2.4.1): articoli del listino distinti da quelli aggiunti a mano
    await db.execute("ALTER TABLE articoli ADD COLUMN origine TEXT NOT NULL DEFAULT 'listino'");
  }
  if (da < 3) {
    // 2 → 3: commissione agente per cliente e «fotografia» nel preventivo
    await db.execute('ALTER TABLE clienti ADD COLUMN commissionePerc REAL NOT NULL DEFAULT -1');
    await db.execute('ALTER TABLE preventivi ADD COLUMN commissionePerc REAL NOT NULL DEFAULT -1');
  }
}

/// Apre (o crea) il database. [percorso] serve ai test; di serie è quello della vecchia app.
Future<Database> apriDatabase({String? percorso, DatabaseFactory? fabbrica}) async {
  final f = fabbrica ?? databaseFactory;
  final file = percorso ?? p.join(await f.getDatabasesPath(), nomeDatabase);
  return f.openDatabase(
    file,
    options: OpenDatabaseOptions(
      version: versioneDatabase,
      // come Room: le cascate (preventivo → righe, articolo → movimenti) e il blocco sul cliente le fa SQLite
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        for (final s in _schema) {
          await db.execute(s);
        }
      },
      onUpgrade: (db, da, _) => _migra(db, da),
    ),
  );
}
