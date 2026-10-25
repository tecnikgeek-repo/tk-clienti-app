// Colori e pezzi propri di tk-clienti; testata, card, dialoghi, Informazioni e splash sono nel kit comune.
import 'package:flutter/material.dart';

import 'kit_tk.dart';

export 'kit_tk.dart';

const accento = Color(0xFF2563EB);
const accentoScuro = Color(0xFF1D4ED8);
const accentoChiaro = Color(0xFFDBEAFE);
const verdeChiaro = Color(0xFFDCFCE7);
const verdeScuro = Color(0xFF166534);
const ambra = Color(0xFFF59E0B);
const ambraChiaro = Color(0xFFFEF3C7);
const ambraScuro = Color(0xFF92400E);
const rossoChiaro = Color(0xFFFEE2E2);

/// Simbolo di tk-clienti: valigetta bianca (come il logo dei preventivi PDF).
Widget simboloClienti(double lato) => Icon(Icons.work_rounded, color: bianco, size: lato * .56);

const configClienti = ConfigTk(
  nome: 'tk-clienti',
  motto: 'Clienti e preventivi in tasca',
  descrizione: 'Clienti, listino e preventivi',
  accento: accento,
  accentoScuro: accentoScuro,
  simbolo: simboloClienti,
  manifestUrl:
      'https://dl.dropboxusercontent.com/scl/fi/osu6ero0dsv9wzkd6ajyl/clienti-version.json?rlkey=sdk0y2sm5y2mvgnlmg642xqu4',
);

Future<T?> vai<T>(BuildContext context, Widget schermata) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => schermata));

/// Spazio in fondo alle liste: barra di sistema + pulsante flottante.
double spazioFondo(BuildContext context, {bool pulsante = false}) =>
    (pulsante ? 100 : 24) + MediaQuery.of(context).padding.bottom;

/// Pulsante flottante delle app TK.
Widget pulsanteNuovo(String testo, VoidCallback onTap, {Color colore = accento}) => FloatingActionButton.extended(
      heroTag: testo,
      onPressed: onTap,
      backgroundColor: colore,
      foregroundColor: bianco,
      icon: const Icon(Icons.add_rounded),
      label: Text(testo.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
    );

/// Campo di testo dei moduli, con l'etichetta sopra.
Widget campo(String etichetta, TextEditingController c,
        {String? suggerimento,
        String? errore,
        ValueChanged<String>? onChanged,
        TextInputType? tastiera,
        int righe = 1,
        bool maiuscole = false,
        bool tuttoMaiuscolo = false,
        Widget? prefisso,
        double sotto = 12}) =>
    Padding(
      padding: EdgeInsets.only(bottom: sotto),
      child: TextField(
        controller: c,
        onChanged: onChanged,
        keyboardType: righe > 1 ? TextInputType.multiline : tastiera,
        minLines: righe > 1 ? 2 : 1,
        maxLines: righe > 1 ? righe + 3 : 1,
        textCapitalization: tuttoMaiuscolo
            ? TextCapitalization.characters
            : maiuscole
                ? TextCapitalization.words
                : (tastiera == null ? TextCapitalization.sentences : TextCapitalization.none),
        decoration: InputDecoration(labelText: etichetta, hintText: suggerimento, errorText: errore, prefixIcon: prefisso),
      ),
    );

const tastieraNumeri = TextInputType.numberWithOptions(decimal: true, signed: true);

/// Etichetta a sinistra, valore a destra (riepiloghi, contatti).
class InfoRiga extends StatelessWidget {
  const InfoRiga(this.etichetta, this.valore, {super.key, this.colore = navy, this.grande = false});

  final String etichetta, valore;
  final Color colore;
  final bool grande;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(etichetta,
              style: TextStyle(
                  color: grande ? navy : grigio500,
                  fontSize: grande ? 15 : 13.5,
                  fontWeight: grande ? FontWeight.w800 : FontWeight.w600)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(valore,
                textAlign: TextAlign.right,
                style: TextStyle(color: colore, fontSize: grande ? 18 : 13.5, fontWeight: FontWeight.w800)),
          ),
        ]),
      );
}

/// Riquadro «niente da mostrare» con icona.
class StatoVuoto extends StatelessWidget {
  const StatoVuoto(this.icona, this.titolo, this.sottotitolo, {super.key});

  final IconData icona;
  final String titolo, sottotitolo;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: accentoChiaro, borderRadius: BorderRadius.circular(20)),
            child: Icon(icona, color: accentoScuro, size: 32),
          ),
          const SizedBox(height: 12),
          Text(titolo, style: const TextStyle(color: navy, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(sottotitolo,
              textAlign: TextAlign.center,
              style: const TextStyle(color: grigio500, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      );
}

/// Titolo di una card con l'icona colorata.
class TitoloCard extends StatelessWidget {
  const TitoloCard(this.titolo, {super.key, this.icona, this.colore = accento, this.destra});

  final String titolo;
  final IconData? icona;
  final Color colore;
  final Widget? destra;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          if (icona != null) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: colore.withValues(alpha: .13), borderRadius: BorderRadius.circular(10)),
              child: Icon(icona, color: colore, size: 18),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(titolo, style: const TextStyle(color: navy, fontSize: 15, fontWeight: FontWeight.w800))),
          ?destra,
        ]),
      );
}

/// Codice articolo nel riquadrino navy.
class CodiceArticolo extends StatelessWidget {
  const CodiceArticolo(this.codice, {super.key});

  final String codice;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: navy, borderRadius: BorderRadius.circular(6)),
        child: Text(codice, style: const TextStyle(color: bianco, fontSize: 11.5, fontWeight: FontWeight.w800)),
      );
}

/// Stato del preventivo con il suo colore.
Widget pillaStato(String stato) => switch (stato.toUpperCase()) {
      'ACCETTATO' || 'APPROVATO' => Pilla(stato, verde),
      'RIFIUTATO' || 'ANNULLATO' => Pilla(stato, rosso),
      'INVIATO' => Pilla(stato, accento),
      _ => Pilla(stato, grigio500, piena: false),
    };

/// Scelta a pillole (Giorni/Mesi/Anni, Imponibile/Totale).
class Scelta<T> extends StatelessWidget {
  const Scelta({super.key, required this.voci, required this.valore, required this.onCambia, this.colore = navy});

  final List<(T, String)> voci;
  final T valore;
  final ValueChanged<T> onCambia;
  final Color colore;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: grigio200, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          for (final (v, testo) in voci)
            Expanded(
              child: Material(
                color: v == valore ? colore : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                child: InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: () => onCambia(v),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Text(testo,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: v == valore ? bianco : grigio500, fontSize: 13, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ),
        ]),
      );
}

/// Pulsante a contorno con icona (azioni secondarie delle schede).
class TastoSecondario extends StatelessWidget {
  const TastoSecondario(this.testo, this.icona, this.onTap, {super.key, this.colore = navy});

  final String testo;
  final IconData icona;
  final VoidCallback? onTap;
  final Color colore;

  @override
  Widget build(BuildContext context) => Material(
        color: bianco,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: grigio200)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icona, color: colore, size: 19),
              const SizedBox(width: 7),
              Flexible(
                child: Text(testo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colore, fontSize: 13.5, fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
        ),
      );
}
