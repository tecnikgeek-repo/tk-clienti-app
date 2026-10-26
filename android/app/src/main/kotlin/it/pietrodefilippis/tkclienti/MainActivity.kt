package it.pietrodefilippis.tkclienti

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Canale «file» di tk-clienti: i file collegati su Drive, Dropbox o nel telefono (listino XLSX/CSV,
 * clienti.json, preventivi.json) restano quelli scelti con la versione Kotlin, perché il permesso
 * salvato appartiene al pacchetto e sopravvive all'aggiornamento. Qui si aprono, leggono e riscrivono.
 * In più: condivisione del PDF (anche diretta a WhatsApp) e apertura per la stampa.
 */
class MainActivity : FlutterActivity() {

    private var inAttesa: MethodChannel.Result? = null
    private var scritturaRichiesta = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        TkAggiornamento.registra(flutterEngine, this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "it.pietrodefilippis.tkclienti/file")
            .setMethodCallHandler { call, result -> gestisci(call, result) }
    }

    private fun gestisci(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "apri" -> {
                if (inAttesa != null) { result.error("occupato", "Scelta file già aperta", null); return }
                val tipi = call.argument<List<String>>("tipi") ?: listOf("*/*")
                scritturaRichiesta = call.argument<Boolean>("scrittura") ?: false
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                    putExtra(Intent.EXTRA_MIME_TYPES, tipi.toTypedArray())
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                    if (scritturaRichiesta) addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                }
                inAttesa = result
                startActivityForResult(intent, RICHIESTA_APRI)
            }
            "crea" -> {
                if (inAttesa != null) { result.error("occupato", "Scelta file già aperta", null); return }
                scritturaRichiesta = true
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = call.argument<String>("tipo") ?: "application/json"
                    putExtra(Intent.EXTRA_TITLE, call.argument<String>("nome") ?: "file.json")
                }
                inAttesa = result
                startActivityForResult(intent, RICHIESTA_CREA)
            }
            "info" -> inSecondoPiano(result) { info(Uri.parse(call.argument<String>("uri")!!)) }
            "leggi" -> inSecondoPiano(result) {
                contentResolver.openInputStream(Uri.parse(call.argument<String>("uri")!!))?.use { it.readBytes() }
                    ?: throw IllegalStateException("Impossibile leggere il file")
            }
            "scrivi" -> inSecondoPiano(result) {
                val uri = Uri.parse(call.argument<String>("uri")!!)
                val dati = call.argument<ByteArray>("dati")!!
                contentResolver.openOutputStream(uri, "wt")?.use { it.write(dati) }
                    ?: throw IllegalStateException("Impossibile scrivere il file")
                info(uri)
            }
            "installata" -> {
                val pacchetto = call.argument<String>("pacchetto")!!
                result.success(try { packageManager.getPackageInfo(pacchetto, 0); true } catch (_: Exception) { false })
            }
            "condividi" -> {
                try { condividi(call); result.success(true) } catch (e: Exception) { result.error("condividi", e.message, null) }
            }
            "apriFile" -> {
                try { apriFile(call); result.success(true) } catch (e: Exception) { result.error("apri", e.message, null) }
            }
            else -> result.notImplemented()
        }
    }

    /** Lavoro su file (anche di rete, Drive) fuori dal thread dell'interfaccia. */
    private fun inSecondoPiano(result: MethodChannel.Result, lavoro: () -> Any?) {
        Thread {
            try {
                val r = lavoro()
                runOnUiThread { result.success(r) }
            } catch (e: Exception) {
                runOnUiThread { result.error("file", e.message ?: e.toString(), null) }
            }
        }.start()
    }

    private fun info(uri: Uri): Map<String, Any?> {
        val doc = try { DocumentFile.fromSingleUri(this, uri) } catch (_: Exception) { null }
        val esiste = try { doc?.exists() == true } catch (_: Exception) { false }
        return mapOf(
            "uri" to uri.toString(),
            "esiste" to esiste,
            "leggibile" to (esiste && try { doc?.canRead() == true } catch (_: Exception) { false }),
            "nome" to (try { doc?.name } catch (_: Exception) { null } ?: ""),
            "dimensione" to (try { doc?.length() } catch (_: Exception) { null } ?: 0L),
            "modificato" to (try { doc?.lastModified() } catch (_: Exception) { null } ?: 0L),
        )
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != RICHIESTA_APRI && requestCode != RICHIESTA_CREA) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = inAttesa ?: return
        inAttesa = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(null); return }
        // permesso persistente: il file resta collegato anche dopo il riavvio del telefono
        val conScrittura = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        try {
            contentResolver.takePersistableUriPermission(uri, if (scritturaRichiesta) conScrittura else Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (_: Exception) {
            try { contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: Exception) { }
        }
        inSecondoPiano(result) { info(uri) }
    }

    private fun uriCondivisibile(percorso: String): Uri =
        FileProvider.getUriForFile(this, "$packageName.fileprovider", File(percorso))

    /** Invia il file: a un'app precisa (WhatsApp) se c'è, altrimenti con la scelta di Android. */
    private fun condividi(call: MethodCall) {
        val uri = uriCondivisibile(call.argument<String>("percorso")!!)
        val pacchetti = call.argument<List<String>>("pacchetti") ?: emptyList()
        val email = call.argument<String>("email")
        fun intento(pacchetto: String?) = Intent(Intent.ACTION_SEND).apply {
            type = call.argument<String>("tipo") ?: "application/pdf"
            putExtra(Intent.EXTRA_STREAM, uri)
            call.argument<String>("oggetto")?.let { putExtra(Intent.EXTRA_SUBJECT, it) }
            call.argument<String>("testo")?.let { putExtra(Intent.EXTRA_TEXT, it) }
            if (!email.isNullOrBlank()) putExtra(Intent.EXTRA_EMAIL, arrayOf(email))
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            if (pacchetto != null) setPackage(pacchetto)
        }
        val pacchetto = pacchetti.firstOrNull { p ->
            try { packageManager.getPackageInfo(p, 0); true } catch (_: Exception) { false }
        }
        if (pacchetto != null) {
            try { startActivity(intento(pacchetto)); return } catch (_: Exception) { }
        }
        startActivity(Intent.createChooser(intento(null), call.argument<String>("titolo") ?: "Condividi"))
    }

    /** Apre il PDF con il lettore del telefono (da lì si stampa). */
    private fun apriFile(call: MethodCall) {
        val uri = uriCondivisibile(call.argument<String>("percorso")!!)
        val tipo = call.argument<String>("tipo") ?: "application/pdf"
        val vedi = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, tipo)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            startActivity(vedi)
        } catch (_: Exception) {
            val invia = Intent(Intent.ACTION_SEND).apply {
                type = tipo
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(invia, "Apri PDF"))
        }
    }

    companion object {
        private const val RICHIESTA_APRI = 4101
        private const val RICHIESTA_CREA = 4102
    }
}
