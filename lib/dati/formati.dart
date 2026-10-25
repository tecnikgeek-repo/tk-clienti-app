// Numeri e date come nella versione Kotlin (Locale.ITALY): «1.234,56 €», «12/10/2026», «12/10/2026 18:42».

const mesiBrevi = ['gen', 'feb', 'mar', 'apr', 'mag', 'giu', 'lug', 'ago', 'set', 'ott', 'nov', 'dic'];

int adesso() => DateTime.now().millisecondsSinceEpoch;

String _migliaia(String cifre) {
  final b = StringBuffer();
  for (var i = 0; i < cifre.length; i++) {
    if (i > 0 && (cifre.length - i) % 3 == 0) b.write('.');
    b.write(cifre[i]);
  }
  return b.toString();
}

/// «1.234,56» (sempre due decimali).
String numero(double v) {
  final negativo = v < 0;
  final centesimi = (v.abs() * 100).round();
  final t = '${_migliaia('${centesimi ~/ 100}')},${(centesimi % 100).toString().padLeft(2, '0')}';
  return negativo && centesimi > 0 ? '-$t' : t;
}

/// «1.234,56 €» (spazio non separabile prima del simbolo, come NumberFormat italiano).
String euro(double v) => '${numero(v)} €';

/// «12.400 €» senza decimali se intero: per le cifre grandi della home.
String euroTondo(double v) => v % 1 == 0 ? '${v < 0 ? '-' : ''}${_migliaia('${v.abs().toInt()}')} €' : euro(v);

/// Percentuale pulita: 5 → «5», 5,5 → «5,5», 5,25 → «5,25».
String percentuale(double v) {
  if (v % 1 == 0) return v.toInt().toString();
  var t = numero(v);
  while (t.endsWith('0')) {
    t = t.substring(0, t.length - 1);
  }
  if (t.endsWith(',')) t = t.substring(0, t.length - 1);
  return t;
}

String _due(int n) => n.toString().padLeft(2, '0');

/// «12/10/2026»
String data(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_due(d.day)}/${_due(d.month)}/${d.year}';
}

/// «12/10/2026 18:42»
String dataOra(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${data(ms)} ${_due(d.hour)}:${_due(d.minute)}';
}

/// «12 ott 2026» (PDF)
String dataLunga(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_due(d.day)} ${mesiBrevi[d.month - 1]} ${d.year}';
}

/// Numero scritto a mano: «1.234,56», «1234,56», «1234.56», «12,5 €» → numero (0 se non si capisce).
double leggiNumero(String s) {
  var t = s.trim().replaceAll('€', '').replaceAll(' ', '').replaceAll(' ', '').replaceAll('%', '');
  if (t.isEmpty) return 0;
  final virgola = t.contains(','), punto = t.contains('.');
  if (virgola && punto) {
    t = t.replaceAll('.', '').replaceAll(',', '.');
  } else if (virgola) {
    t = t.replaceAll(',', '.');
  } else if (punto && RegExp(r'^-?\d{1,3}(\.\d{3})+$').hasMatch(t)) {
    t = t.replaceAll('.', ''); // «1.500» = millecinquecento
  }
  return double.tryParse(t) ?? 0;
}

/// Numero nel campo di modifica: intero senza decimali, altrimenti con la virgola.
String perCampo(double v) {
  if (v % 1 == 0) return v.toInt().toString();
  var t = v.toString().replaceAll('.', ',');
  if (t.contains('e')) t = v.toStringAsFixed(4).replaceAll('.', ',');
  return t;
}
