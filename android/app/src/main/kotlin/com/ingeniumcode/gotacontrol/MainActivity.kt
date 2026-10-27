package com.ingeniumcode.gotacontrol

import android.os.Handler
import android.os.Looper
import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.mindrot.jbcrypt.BCrypt
import androidx.documentfile.provider.DocumentFile
import androidx.work.WorkManager
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val pinExecutor = Executors.newSingleThreadExecutor { task ->
        Thread(task, "gotacontrol-pin-hash").apply { isDaemon = true }
    }
    private val mainHandler = Handler(Looper.getMainLooper())
    private val backupExecutor = Executors.newSingleThreadExecutor { task ->
        Thread(task, "gotacontrol-local-backup").apply { isDaemon = true }
    }
    private var pendingBackupResult: MethodChannel.Result? = null
    private var pendingPickerMethod: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "gotacontrol/pin_hash",
        ).setMethodCallHandler { call, result ->
            val pin = call.argument<String>("pin")
            if (pin == null || !pin.matches(Regex("^\\d{4,6}$"))) {
                result.error("invalid_pin", "PIN must contain 4 to 6 digits.", null)
                return@setMethodCallHandler
            }

            when (call.method) {
                "hashPin" -> pinExecutor.execute {
                    try {
                        val hash = BCrypt.hashpw(pin, BCrypt.gensalt(12))
                        mainHandler.post { result.success(hash) }
                    } catch (error: Exception) {
                        mainHandler.post {
                            result.error("pin_hash_failed", error.message, null)
                        }
                    }
                }
                "verifyPin" -> {
                    val hash = call.argument<String>("hash")
                    if (hash == null) {
                        result.error("invalid_hash", "PIN hash is required.", null)
                    } else {
                        pinExecutor.execute {
                            try {
                                val valid = BCrypt.checkpw(pin, hash)
                                mainHandler.post { result.success(valid) }
                            } catch (error: Exception) {
                                mainHandler.post {
                                    result.error("pin_verify_failed", error.message, null)
                                }
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LocalBackupContract.CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "selectBackupFolder" -> launchPicker(
                    method = call.method,
                    result = result,
                    intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE),
                    requestCode = REQUEST_BACKUP_FOLDER,
                )
                "selectImportBackup" -> launchPicker(
                    method = call.method,
                    result = result,
                    intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                    },
                    requestCode = REQUEST_IMPORT_FILE,
                )
                "getBackupStatus" -> result.success(LocalBackupContract.status(this))
                "restoreLatestBackupIfMissing" -> {
                    val databasePath = call.argument<String>("databasePath")
                    if (databasePath == null) {
                        result.error("invalid_arguments", "Falta la ruta de la base local.", null)
                    } else {
                        backupExecutor.execute {
                            try {
                                val status = LocalBackupContract
                                    .restoreLatestDefaultBackupIfMissing(this, databasePath)
                                android.util.Log.i(
                                    "GotaControlBackup",
                                    "Startup restore check: $status",
                                )
                                mainHandler.post { result.success(status) }
                            } catch (error: Exception) {
                                LocalBackupContract.recordFailure(this, error.message)
                                mainHandler.post {
                                    result.error("startup_restore_failed", error.message, null)
                                }
                            }
                        }
                    }
                }
                "configureSchedule" -> {
                    val frequency = call.argument<String>("frequency")
                    val databasePath = call.argument<String>("databasePath")
                    if (frequency == null || databasePath == null) {
                        result.error("invalid_arguments", "Faltan datos para programar respaldos.", null)
                    } else {
                        try {
                            val scheduled = LocalBackupContract.configureSchedule(
                                this,
                                frequency,
                                databasePath,
                            )
                            result.success(mapOf("scheduled" to scheduled))
                        } catch (error: Exception) {
                            result.error("schedule_failed", error.message, null)
                        }
                    }
                }
                "cancelSchedule" -> {
                    WorkManager.getInstance(this)
                        .cancelUniqueWork(LocalBackupContract.UNIQUE_WORK_NAME)
                    result.success(null)
                }
                "runBackupNow" -> {
                    val databasePath = call.argument<String>("databasePath")
                    val treeUri = LocalBackupContract.storedTreeUri(this)
                    if (databasePath == null ||
                        (treeUri == null && Build.VERSION.SDK_INT < Build.VERSION_CODES.Q)
                    ) {
                        result.error(
                            "backup_destination_missing",
                            "No hay una ubicación compatible para guardar los respaldos.",
                            null,
                        )
                    } else {
                        backupExecutor.execute {
                            try {
                                val filename = LocalBackupContract.createBackup(
                                    this,
                                    databasePath,
                                    treeUri,
                                    automatic = false,
                                )
                                mainHandler.post { result.success(filename) }
                            } catch (error: Exception) {
                                LocalBackupContract.recordFailure(this, error.message)
                                mainHandler.post {
                                    result.error("backup_failed", error.message, null)
                                }
                            }
                        }
                    }
                }
                "restoreBackup" -> {
                    val selectedPath = call.argument<String>("selectedPath")
                    val databasePath = call.argument<String>("databasePath")
                    val treeUri = LocalBackupContract.storedTreeUri(this)
                    if (selectedPath == null || databasePath == null) {
                        result.error(
                            "restore_setup_missing",
                            "Faltan datos para restaurar la base de datos.",
                            null,
                        )
                    } else {
                        backupExecutor.execute {
                            try {
                                restoreDatabase(
                                    File(selectedPath),
                                    File(databasePath),
                                    treeUri,
                                )
                                mainHandler.post { result.success(true) }
                            } catch (error: Exception) {
                                mainHandler.post {
                                    result.error("restore_failed", error.message, null)
                                }
                            }
                        }
                    }
                }
                "discardImportBackup" -> {
                    val selectedPath = call.argument<String>("selectedPath")
                    if (selectedPath == null) {
                        result.error("invalid_arguments", "Falta el archivo importado.", null)
                    } else {
                        val candidate = File(selectedPath)
                        if (candidate.parentFile?.canonicalFile != cacheDir.canonicalFile) {
                            result.error("invalid_path", "El archivo temporal no pertenece a la app.", null)
                        } else {
                            candidate.delete()
                            result.success(null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun launchPicker(
        method: String,
        result: MethodChannel.Result,
        intent: Intent,
        requestCode: Int,
    ) {
        if (pendingBackupResult != null) {
            result.error("picker_busy", "Ya hay un selector de archivos abierto.", null)
            return
        }
        pendingBackupResult = result
        pendingPickerMethod = method
        try {
            startActivityForResult(intent, requestCode)
        } catch (error: Exception) {
            pendingBackupResult = null
            pendingPickerMethod = null
            result.error("picker_unavailable", error.message, null)
        }
    }

    @Deprecated("Deprecated in Android, retained for the FlutterActivity SAF result flow.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_BACKUP_FOLDER && requestCode != REQUEST_IMPORT_FILE) return

        val result = pendingBackupResult ?: return
        val method = pendingPickerMethod
        pendingBackupResult = null
        pendingPickerMethod = null
        if (resultCode != RESULT_OK || data?.data == null) {
            result.success(null)
            return
        }
        val uri = data.data!!

        if (requestCode == REQUEST_BACKUP_FOLDER) {
            try {
                val flags = data.flags and
                    (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                contentResolver.takePersistableUriPermission(uri, flags)
                LocalBackupContract.storeTreeUri(this, uri)
                val displayName = DocumentFile.fromTreeUri(this, uri)?.name ?: "Documentos"
                LocalBackupContract.scheduleSavedFrequency(this, uri)
                result.success(mapOf("uri" to uri.toString(), "name" to displayName))
            } catch (error: Exception) {
                result.error("folder_access_failed", error.message, null)
            }
            return
        }

        if (method != "selectImportBackup") {
            result.error("invalid_picker_result", "Respuesta de selector no válida.", null)
            return
        }
        backupExecutor.execute {
            val selectedFile = File(cacheDir, "import-${System.nanoTime()}.db")
            try {
                val flags = data.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION
                if (flags != 0) contentResolver.takePersistableUriPermission(uri, flags)
                contentResolver.openInputStream(uri).use { input ->
                    if (input == null) {
                        throw IllegalArgumentException("No se pudo leer el archivo seleccionado.")
                    }
                    selectedFile.outputStream().use { output -> input.copyTo(output) }
                }
                val details = LocalBackupContract.validateDatabase(selectedFile)
                val response = details + mapOf("selectedPath" to selectedFile.absolutePath)
                mainHandler.post { result.success(response) }
            } catch (error: Exception) {
                selectedFile.delete()
                mainHandler.post {
                    result.error("invalid_backup", error.message, null)
                }
            }
        }
    }

    private fun restoreDatabase(selectedFile: File, databaseFile: File, treeUri: Uri?) {
        synchronized(LocalBackupContract.operationLock) {
            restoreDatabaseLocked(selectedFile, databaseFile, treeUri)
        }
    }

    private fun restoreDatabaseLocked(selectedFile: File, databaseFile: File, treeUri: Uri?) {
        LocalBackupContract.validateDatabase(selectedFile)
        LocalBackupContract.createBackup(
            this,
            databaseFile.absolutePath,
            treeUri,
            automatic = false,
            prefixOverride = LocalBackupContract.PRE_RESTORE_PREFIX,
        )

        val replacement = File(databaseFile.parentFile, "restore-${System.nanoTime()}.db")
        val previous = File(databaseFile.parentFile, "previous-${System.nanoTime()}.db")
        selectedFile.copyTo(replacement, overwrite = false)
        try {
            LocalBackupContract.validateDatabase(replacement)
            val wal = File(databaseFile.path + "-wal")
            val shm = File(databaseFile.path + "-shm")
            if (databaseFile.exists() && !databaseFile.renameTo(previous)) {
                throw IllegalStateException("No se pudo resguardar la base local actual.")
            }
            wal.delete()
            shm.delete()
            if (!replacement.renameTo(databaseFile)) {
                if (previous.exists()) previous.renameTo(databaseFile)
                throw IllegalStateException("No se pudo instalar la base importada.")
            }
            try {
                LocalBackupContract.validateDatabase(databaseFile)
            } catch (error: Exception) {
                databaseFile.delete()
                if (previous.exists() && !previous.renameTo(databaseFile)) {
                    throw IllegalStateException(
                        "Falló la validación y no se pudo recuperar la base previa.",
                        error,
                    )
                }
                throw error
            }
            previous.delete()
            // selectedFile.delete()
        } finally {
            replacement.delete()
            if (previous.exists() && databaseFile.exists()) previous.delete()
            selectedFile.delete() // <--- LO PONEMOS AQUÍ (Se borrará siempre)

        }
    }

    companion object {
        private const val REQUEST_BACKUP_FOLDER = 8401
        private const val REQUEST_IMPORT_FILE = 8402
    }
}