// JSON scritto ESATTAMENTE come org.json di Android (JSONObject.toString(2)) e numeri come Double.toString di Java.
// Serve perché i file clienti.json / preventivi.json collegati sul cloud hanno un'impronta SHA-256 salvata
// dalla versione Kotlin: scrivendo byte identici l'app riconosce che il file è già aggiornato e non crea
// copie in conflitto su Dropbox/Drive (e il controllo «modifiche non ancora caricate» resta valido).

/// Numero Java: `double` per i decimali, `int` per gli interi (Long/Integer di Kotlin).
/// Un double intero si scrive senza «.0», come JSONObject.numberToString.
String numeroJson(num n) {
  if (n is int) return n.toString();
  final d = n.toDouble();
  if (d.isNaN || d.isInfinite) throw ArgumentError('Numero non valido nel JSON: $d');
  if (d == 0 && d.isNegative) return '-0';
  if (d == d.truncateToDouble() && d.abs() < 9.2e18) return d.toInt().toString();
  return doubleJava(d);
}

/// Double.toString di Java: «12.5», «12.0», «1.0E7», «1.2345E-4».
String doubleJava(double d) {
  if (d.isNaN) return 'NaN';
  if (d.isInfinite) return d > 0 ? 'Infinity' : '-Infinity';
  if (d == 0) return d.isNegative ? '-0.0' : '0.0';
  final a = d.abs();
  if (a >= 1e-3 && a < 1e7) {
    final t = d.toString();
    return t.contains('.') ? t : '$t.0';
  }
  // notazione scientifica: mantissa con almeno un decimale, «E» ed esponente senza «+»
  final e = d.toStringAsExponential(); // «1.2345e+7»
  final i = e.indexOf('e');
  var mantissa = e.substring(0, i);
  if (!mantissa.contains('.')) mantissa = '$mantissa.0';
  final esponente = int.parse(e.substring(i + 1));
  return '${mantissa}E$esponente';
}

String _stringa(String s) {
  final b = StringBuffer('"');
  for (final c in s.codeUnits) {
    switch (c) {
      case 0x22: // "
      case 0x5C: // \
      case 0x2F: // /  (Android lo scrive come \/)
        b.write('\\');
        b.writeCharCode(c);
      case 0x09:
        b.write(r'\t');
      case 0x08:
        b.write(r'\b');
      case 0x0A:
        b.write(r'\n');
      case 0x0D:
        b.write(r'\r');
      case 0x0C:
        b.write(r'\f');
      default:
        if (c <= 0x1F) {
          b.write('\\u${c.toRadixString(16).padLeft(4, '0')}');
        } else {
          b.writeCharCode(c);
        }
    }
  }
  b.write('"');
  return b.toString();
}

/// JSONObject.toString(2) di Android. Le mappe mantengono l'ordine d'inserimento (come LinkedHashMap).
String jsonAndroid(Object? valore, {int rientro = 2}) {
  final b = StringBuffer();
  final passo = ' ' * rientro;
  void scrivi(Object? v, int livello) {
    if (v == null) {
      b.write('null');
    } else if (v is bool) {
      b.write(v ? 'true' : 'false');
    } else if (v is num) {
      b.write(numeroJson(v));
    } else if (v is String) {
      b.write(_stringa(v));
    } else if (v is Map) {
      if (v.isEmpty) {
        b.write('{}');
        return;
      }
      b.write('{');
      var primo = true;
      v.forEach((k, x) {
        if (!primo) b.write(',');
        primo = false;
        b.write('\n${passo * (livello + 1)}');
        b.write(_stringa('$k'));
        b.write(': ');
        scrivi(x, livello + 1);
      });
      b.write('\n${passo * livello}}');
    } else if (v is List) {
      if (v.isEmpty) {
        b.write('[]');
        return;
      }
      b.write('[');
      for (var i = 0; i < v.length; i++) {
        if (i > 0) b.write(',');
        b.write('\n${passo * (livello + 1)}');
        scrivi(v[i], livello + 1);
      }
      b.write('\n${passo * livello}]');
    } else {
      b.write(_stringa(v.toString()));
    }
  }

  scrivi(valore, 0);
  return b.toString();
}
