# tk-clienti per Android e iPhone

Clienti, listino prodotti con magazzino, preventivi in PDF e andamento con le commissioni dell'agente, sul
telefono. Si sincronizza con i file che colleghi tu (nel tuo spazio cloud o nel telefono), anche tra più telefoni.
Tutte le funzioni sono gratis, per tutti.

- **Piattaforme:** Android (APK) e iPhone.
- **Licenza:** software libero sotto [GNU AGPL-3.0](COPYING), fornito così com'è, senza alcuna garanzia.
- **Privacy:** clienti, listino e preventivi restano sul telefono e nei file che colleghi tu. Le statistiche
  anonime (una volta al giorno: nome, versione, sistema e un codice casuale) partono solo se dici sì nel
  benvenuto o in Informazioni.

## Compilare dal sorgente

Serve [Flutter](https://flutter.dev) (versione indicata in `.github/workflows/android.yml`):

```
flutter pub get
flutter test
flutter build apk --release
```

Senza la variabile `ANDROID_KEYSTORE` l'APK si firma con la chiave di debug di Flutter.

Il nome «tk-clienti» e il logo non sono coperti dalla licenza (AGPL sez. 7): una versione modificata deve avere
un nome diverso.

© 2026 Pietro De Filippis (TecnikGeek) — [pietrodefilippis.it](https://pietrodefilippis.it)
