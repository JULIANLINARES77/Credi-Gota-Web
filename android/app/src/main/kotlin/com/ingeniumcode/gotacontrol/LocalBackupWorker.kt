package com.ingeniumcode.gotacontrol

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.documentfile.provider.DocumentFile
import androidx.work.Data
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

class LocalBackupWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val databasePath = inputData.getString(LocalBackupContract.DATABASE_PATH)
            ?: return Result.failure()
        val treeUri = inputData.getString(LocalBackupContract.TREE_URI)?.let(Uri::parse)
        if (treeUri == null && Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return Result.failure()
        }

        return try {
            LocalBackupContract.createBackup(
                applicationContext,
                databasePath,
                treeUri,
                automatic = true,
            )
            Result.success()
        } catch (error: Exception) {
            LocalBackupContract.recordFailure(applicationContext, error.message)
            if (runAttemptCount < 3) Result.retry() else Result.failure()
        }
    }
}

internal object LocalBackupContract {
    const val CHANNEL = "gotacontrol/local_backup"
    const val DATABASE_PATH = "database_path"
    const val TREE_URI = "tree_uri"
    const val CURRENT_DATABASE_VERSION = 8
    const val BACKUP_FOLDER = "GotaControl"
    const val AUTOMATIC_PREFIX = "GotaControl_auto_"
    const val MANUAL_PREFIX = "GotaControl_manual_"
    const val PRE_RESTORE_PREFIX = "GotaControl_pre_restore_"
    const val MAX_AUTOMATIC_BACKUPS = 30
    const val UNIQUE_WORK_NAME = "gotacontrol-database-backup"
    const val INITIAL_WORK_NAME = "gotacontrol-initial-database-backup"
    private val DOCUMENTS_BACKUP_PATH =
        "${Environment.DIRECTORY_DOCUMENTS}/$BACKUP_FOLDER/"
    private val LEGACY_DOWNLOADS_BACKUP_PATH =
        "${Environment.DIRECTORY_DOWNLOADS}/$BACKUP_FOLDER/"
    val operationLock = Any()

    private const val PREFERENCES = "gotacontrol_local_backup"
    private const val FREQUENCY = "frequency"
    private const val STORED_DATABASE_PATH = "database_path"
    private const val STORED_TREE_URI = "tree_uri"
    private const val LAST_SUCCESS = "last_success"
    private const val LAST_FILE = "last_file"
    private const val LAST_ERROR = "last_error"

    fun configureSchedule(context: Context, frequency: String, databasePath: String): Boolean {
        val preferences = preferences(context)
        preferences.edit()
            .putString(FREQUENCY, frequency)
            .putString(STORED_DATABASE_PATH, databasePath)
            .apply()

        val treeUri = storedTreeUri(context)?.toString()
        if (treeUri.isNullOrBlank() && Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            WorkManager.getInstance(context).cancelUniqueWork(UNIQUE_WORK_NAME)
            return false
        }

        val intervalDays = when (frequency) {
            "daily" -> 1L
            "weekly" -> 7L
            "fortnightly" -> 15L
            else -> throw IllegalArgumentException("Frecuencia de respaldo no válida.")
        }
        val request = PeriodicWorkRequestBuilder<LocalBackupWorker>(
            intervalDays,
            TimeUnit.DAYS,
        )
            .setInputData(
                Data.Builder()
                    .putString(DATABASE_PATH, databasePath)
                    .putString(TREE_URI, treeUri)
                    .build(),
            )
            .build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            UNIQUE_WORK_NAME,
            ExistingPeriodicWorkPolicy.UPDATE,
            request,
        )
        if (preferences.getLong(LAST_SUCCESS, 0L) == 0L) {
            val initialRequest = OneTimeWorkRequestBuilder<LocalBackupWorker>()
                .setInputData(
                    Data.Builder()
                        .putString(DATABASE_PATH, databasePath)
                        .putString(TREE_URI, treeUri)
                        .build(),
                )
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(
                INITIAL_WORK_NAME,
                androidx.work.ExistingWorkPolicy.KEEP,
                initialRequest,
            )
        }
        return true
    }

    fun scheduleSavedFrequency(context: Context, treeUri: Uri) {
        val preferences = preferences(context)
        val frequency = preferences.getString(FREQUENCY, "daily") ?: "daily"
        val databasePath = preferences.getString(STORED_DATABASE_PATH, null) ?: return
        configureSchedule(context, frequency, databasePath)
    }

    fun backupFolder(context: Context, treeUri: Uri): DocumentFile {
        val root = DocumentFile.fromTreeUri(context, treeUri)
            ?: throw IllegalStateException("No se pudo abrir la carpeta elegida.")
        if (!root.canWrite()) {
            throw IllegalStateException("La carpeta elegida no permite guardar respaldos.")
        }
        if (root.name == BACKUP_FOLDER) return root
        return root.findFile(BACKUP_FOLDER)
            ?: root.createDirectory(BACKUP_FOLDER)
            ?: throw IllegalStateException("No se pudo crear la carpeta de respaldos.")
    }

    fun createBackup(
        context: Context,
        databasePath: String,
        treeUri: Uri?,
        automatic: Boolean,
        prefixOverride: String? = null,
    ): String = synchronized(operationLock) {
        val destinationTreeUri = usableTreeUri(context, treeUri)
        val source = File(databasePath)
        if (!source.isFile) {
            throw IllegalStateException("No se encontró la base de datos local.")
        }
        val snapshot = File(context.cacheDir, "backup-${System.nanoTime()}.db")
        try {
            createConsistentSnapshot(source, snapshot)
            val prefix = prefixOverride ?: if (automatic) AUTOMATIC_PREFIX else MANUAL_PREFIX
            val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
            val name = "$prefix$timestamp.db"
            if (destinationTreeUri == null) {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                    throw IllegalStateException(
                        "La carpeta seleccionada no está disponible y el respaldo "
                            + "automático requiere Android 10 o posterior.",
                    )
                }
                createMediaStoreBackup(context, snapshot, name)
                recordDatabaseBackup(databasePath)
                if (automatic) pruneMediaStoreBackups(context)
            } else {
                val directory = backupFolder(context, destinationTreeUri)
                val destination = directory.createFile("application/vnd.sqlite3", name)
                    ?: throw IllegalStateException("No se pudo crear el archivo de respaldo.")
                try {
                    context.contentResolver.openOutputStream(destination.uri, "w").use { output ->
                        if (output == null) {
                            throw IllegalStateException("No se pudo escribir el respaldo.")
                        }
                        snapshot.inputStream().use { input -> input.copyTo(output) }
                        output.flush()
                    }
                } catch (error: Exception) {
                    destination.delete()
                    throw error
                }
                recordDatabaseBackup(databasePath)
                if (automatic) pruneAutomaticBackups(directory)
            }
            preferences(context).edit()
                .putLong(LAST_SUCCESS, System.currentTimeMillis())
                .putString(LAST_FILE, name)
                .remove(LAST_ERROR)
                .apply()
            name
        } finally {
            snapshot.delete()
        }
    }

    fun validateDatabase(file: File): Map<String, Any> {
        if (!file.isFile || file.length() < 100) {
            throw IllegalArgumentException("El archivo no parece una copia SQLite válida.")
        }
        val database = SQLiteDatabase.openDatabase(
            file.absolutePath,
            null,
            SQLiteDatabase.OPEN_READONLY,
        )
        try {
            val integrity = database.rawQuery("PRAGMA integrity_check", null).use { cursor ->
                if (!cursor.moveToFirst()) "" else cursor.getString(0)
            }
            if (integrity != "ok") {
                throw IllegalArgumentException("La copia está dañada: $integrity")
            }
            val version = database.rawQuery("PRAGMA user_version", null).use { cursor ->
                if (!cursor.moveToFirst()) 0 else cursor.getInt(0)
            }
            if (version !in 1..CURRENT_DATABASE_VERSION) {
                throw IllegalArgumentException(
                    "La versión de la copia ($version) no es compatible con esta app.",
                )
            }
            val requiredTables = setOf("clientes", "prestamos", "cuotas", "pagos", "configuracion")
            val tables = database.rawQuery(
                "SELECT name FROM sqlite_master WHERE type = 'table'",
                null,
            ).use { cursor ->
                buildSet {
                    while (cursor.moveToNext()) add(cursor.getString(0))
                }
            }
            if (!tables.containsAll(requiredTables)) {
                throw IllegalArgumentException("La copia no contiene todas las tablas de GotaControl.")
            }
            val requiredColumns = mapOf(
                "clientes" to setOf("id", "nombre", "telefono"),
                "prestamos" to setOf("id", "cliente_id", "monto_capital"),
                "cuotas" to setOf("id", "prestamo_id", "numero_cuota"),
                "pagos" to setOf("id", "prestamo_id", "monto"),
                "configuracion" to setOf("id", "nombre_negocio"),
            )
            for ((table, expectedColumns) in requiredColumns) {
                val columns = database.rawQuery("PRAGMA table_info('$table')", null).use { cursor ->
                    buildSet {
                        while (cursor.moveToNext()) add(cursor.getString(1))
                    }
                }
                if (!columns.containsAll(expectedColumns)) {
                    throw IllegalArgumentException(
                        "La tabla $table no tiene las columnas requeridas por GotaControl.",
                    )
                }
            }
            val foreignKeyErrors = database.rawQuery("PRAGMA foreign_key_check", null).use { cursor ->
                cursor.count
            }
            if (foreignKeyErrors > 0) {
                throw IllegalArgumentException("La copia contiene relaciones de datos inválidas.")
            }
            return mapOf("version" to version, "sizeBytes" to file.length())
        } finally {
            database.close()
        }
    }

    fun recordFailure(context: Context, error: String?) {
        preferences(context).edit()
            .putString(LAST_ERROR, error ?: "Error no especificado.")
            .apply()
    }

    fun status(context: Context): Map<String, Any?> {
        val preferences = preferences(context)
        val treeUri = storedTreeUri(context)?.toString()
        val automaticDestination = treeUri.isNullOrBlank() &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
        val folder = treeUri?.let {
            DocumentFile.fromTreeUri(context, Uri.parse(it))?.name
        } ?: if (automaticDestination) "Documentos/GotaControl" else null
        return mapOf(
            "folderUri" to (
                treeUri ?: if (automaticDestination) "mediastore:documents/gotacontrol" else null
            ),
            "folderName" to folder,
            "automaticDestination" to automaticDestination,
            "frequency" to preferences.getString(FREQUENCY, "daily"),
            "lastSuccess" to preferences.getLong(LAST_SUCCESS, 0L),
            "lastFile" to preferences.getString(LAST_FILE, null),
            "lastError" to preferences.getString(LAST_ERROR, null),
        )
    }

    fun storeTreeUri(context: Context, uri: Uri) {
        val preferences = preferences(context)
        if (preferences.getString(STORED_TREE_URI, null) != uri.toString()) {
            preferences.edit()
                .remove(LAST_SUCCESS)
                .remove(LAST_FILE)
                .remove(LAST_ERROR)
                .apply()
        }
        preferences.edit().putString(STORED_TREE_URI, uri.toString()).apply()
    }

    fun storedTreeUri(context: Context): Uri? {
        val preferences = preferences(context)
        val stored = preferences.getString(STORED_TREE_URI, null)
            ?.let(Uri::parse) ?: return null
        if (usableTreeUri(context, stored) != null) return stored
        preferences.edit().remove(STORED_TREE_URI).apply()
        return null
    }

    private fun usableTreeUri(context: Context, treeUri: Uri?): Uri? {
        if (treeUri == null) return null
        return try {
            val directory = DocumentFile.fromTreeUri(context, treeUri)
            treeUri.takeIf { directory?.isDirectory == true && directory.canWrite() }
        } catch (_: SecurityException) {
            null
        }
    }

    fun restoreLatestDefaultBackupIfMissing(
        context: Context,
        databasePath: String,
    ): Map<String, Any> = synchronized(operationLock) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return@synchronized mapOf("restored" to false)
        }
        val databaseFile = File(databasePath)
        var lastError: Exception? = null
        val localHasBusinessData = if (databaseFile.isFile && databaseFile.length() > 0L) {
            try {
                databaseHasBusinessData(databaseFile)
            } catch (error: Exception) {
                lastError = error
                recordFailure(context, "No se pudo validar la base local antes de restaurar: ${error.message}")
                false
            }
        } else {
            false
        }
        if (localHasBusinessData) {
            return@synchronized mapOf(
                "restored" to false,
                "reason" to "local_database_has_business_data",
                "databaseExisted" to true,
                "candidateCount" to 0,
            )
        }
        val savedTreeUri = storedTreeUri(context)
        var treeAccessFailed = false
        var savedTreeStatus: Map<String, Any>? = null
        if (savedTreeUri != null) {
            try {
                val treeStatus = restoreLatestBackupFromTree(
                    context,
                    databasePath,
                    savedTreeUri,
                )
                savedTreeStatus = treeStatus
                if (treeStatus["restored"] == true) return@synchronized treeStatus
            } catch (error: Exception) {
                lastError = error
                treeAccessFailed = true
                recordFailure(context, "No se pudo leer la carpeta de respaldos guardada: ${error.message}")
            }
        }
        val backups = mediaStoreBackups(context)
        if (backups.isEmpty()) {
            val priorTreeStatus = savedTreeStatus
            if (priorTreeStatus?.get("reason") == "only_empty_backups") {
                return@synchronized priorTreeStatus
            }
            if (lastError != null && savedTreeUri != null && !treeAccessFailed) {
                throw IllegalStateException(
                    "La base local no se pudo validar y no hay copias predeterminadas disponibles.",
                    lastError,
                )
            }
            return@synchronized mapOf(
                "restored" to false,
                "reason" to "no_accessible_public_backups",
                "databaseExisted" to databaseFile.isFile,
                "candidateCount" to 0,
                "needsFolderAccess" to (savedTreeUri == null || treeAccessFailed),
            )
        }

        var newestEmptyBackup: MediaStoreBackup? = null
        for (backup in backups) {
            val candidate = File(context.cacheDir, "startup-${System.nanoTime()}.db")
            try {
                context.contentResolver.openInputStream(backup.uri).use { input ->
                    if (input == null) throw IllegalStateException("No se pudo leer ${backup.name}.")
                    candidate.outputStream().use { output -> input.copyTo(output) }
                }
                validateDatabase(candidate)
                if (!databaseHasBusinessData(candidate)) {
                    if (newestEmptyBackup == null) newestEmptyBackup = backup
                    continue
                }
                installDatabaseAtomically(candidate, databaseFile)
                preferences(context).edit()
                    .putLong(LAST_SUCCESS, backup.modifiedSeconds * 1000L)
                    .putString(LAST_FILE, backup.name)
                    .remove(LAST_ERROR)
                    .apply()
                return@synchronized mapOf(
                    "restored" to true,
                    "fileName" to backup.name,
                    "reason" to "restored_business_data",
                    "candidateCount" to backups.size,
                )
            } catch (error: Exception) {
                lastError = error
                recordFailure(context, "${backup.name}: ${error.message}")
            } finally {
                candidate.delete()
            }
        }
        if (newestEmptyBackup != null) {
            if (savedTreeUri == null || treeAccessFailed) {
                return@synchronized mapOf(
                    "restored" to false,
                    "reason" to "only_empty_backups",
                    "candidateCount" to backups.size,
                    "needsFolderAccess" to true,
                )
            }
            preferences(context).edit()
                .putLong(LAST_SUCCESS, newestEmptyBackup.modifiedSeconds * 1000L)
                .putString(LAST_FILE, newestEmptyBackup.name)
                .remove(LAST_ERROR)
                .apply()
            return@synchronized mapOf(
                "restored" to false,
                "reason" to "only_empty_backups",
                "candidateCount" to backups.size,
            )
        }
        if (lastError == null) return@synchronized mapOf("restored" to false)
        if (savedTreeUri == null || treeAccessFailed) {
            return@synchronized mapOf(
                "restored" to false,
                "reason" to "public_backups_unreadable",
                "candidateCount" to backups.size,
                "needsFolderAccess" to true,
            )
        }
        throw IllegalStateException(
            "Se encontraron respaldos, pero ninguno pudo validarse; no se reemplazó la base local.",
            lastError,
        )
    }

    fun restoreLatestBackupFromTree(
        context: Context,
        databasePath: String,
        treeUri: Uri,
    ): Map<String, Any> = synchronized(operationLock) {
        val databaseFile = File(databasePath)
        val root = DocumentFile.fromTreeUri(context, treeUri)
            ?: throw IllegalStateException("No se pudo abrir la carpeta seleccionada.")
        val directories = buildList {
            add(root)
            root.findFile(BACKUP_FOLDER)?.takeIf { it.isDirectory }?.let(::add)
        }.distinctBy { it.uri }
        val backups = directories
            .flatMap { it.listFiles().asList() }
            .filter { file ->
                file.isFile && file.name?.let { name ->
                    name.startsWith(AUTOMATIC_PREFIX) ||
                        name.startsWith(MANUAL_PREFIX) ||
                        name.startsWith(PRE_RESTORE_PREFIX)
                } == true
            }
            .sortedWith(
                compareByDescending<DocumentFile> { it.lastModified() }
                    .thenByDescending { it.name },
            )
        if (backups.isEmpty()) {
            return@synchronized mapOf(
                "restored" to false,
                "reason" to "no_backup_in_selected_folder",
                "candidateCount" to 0,
            )
        }

        var lastError: Exception? = null
        for (backup in backups) {
            val candidate = File(context.cacheDir, "tree-startup-${System.nanoTime()}.db")
            try {
                context.contentResolver.openInputStream(backup.uri).use { input ->
                    if (input == null) {
                        throw IllegalStateException("No se pudo leer ${backup.name}.")
                    }
                    candidate.outputStream().use { output -> input.copyTo(output) }
                }
                validateDatabase(candidate)
                if (!databaseHasBusinessData(candidate)) continue
                installDatabaseAtomically(candidate, databaseFile)
                preferences(context).edit()
                    .putLong(LAST_SUCCESS, backup.lastModified())
                    .putString(LAST_FILE, backup.name)
                    .remove(LAST_ERROR)
                    .apply()
                return@synchronized mapOf(
                    "restored" to true,
                    "fileName" to (backup.name ?: "respaldo"),
                    "reason" to "restored_business_data_from_tree",
                    "candidateCount" to backups.size,
                )
            } catch (error: Exception) {
                lastError = error
                recordFailure(context, "${backup.name}: ${error.message}")
            } finally {
                candidate.delete()
            }
        }
        if (lastError != null) {
            throw IllegalStateException(
                "Se encontraron archivos, pero ninguno pudo validarse; no se reemplazó la base local.",
                lastError,
            )
        }
        mapOf(
            "restored" to false,
            "reason" to "only_empty_backups",
            "candidateCount" to backups.size,
        )
    }

    private data class MediaStoreBackup(
        val uri: Uri,
        val name: String,
        val modifiedSeconds: Long,
        val relativePath: String,
    )

    private fun databaseHasBusinessData(file: File): Boolean {
        val database = SQLiteDatabase.openDatabase(
            file.absolutePath,
            null,
            SQLiteDatabase.OPEN_READONLY,
        )
        return try {
            listOf("clientes", "prestamos", "cuotas", "pagos").any { table ->
                database.rawQuery("SELECT EXISTS(SELECT 1 FROM $table LIMIT 1)", null)
                    .use { cursor -> cursor.moveToFirst() && cursor.getInt(0) != 0 }
            }
        } finally {
            database.close()
        }
    }

    private fun createMediaStoreBackup(context: Context, snapshot: File, name: String) {
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, "application/vnd.sqlite3")
            put(
                MediaStore.MediaColumns.RELATIVE_PATH,
                DOCUMENTS_BACKUP_PATH,
            )
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val collection = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = context.contentResolver.insert(collection, values)
            ?: throw IllegalStateException(
                "No se pudo crear Documentos/$BACKUP_FOLDER. "
                    + "Comprueba el espacio disponible en el dispositivo.",
            )
        try {
            context.contentResolver.openOutputStream(uri, "w").use { output ->
                if (output == null) throw IllegalStateException("No se pudo escribir el respaldo.")
                snapshot.inputStream().use { input -> input.copyTo(output) }
                output.flush()
            }
            val published = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            if (context.contentResolver.update(uri, published, null, null) != 1) {
                throw IllegalStateException("No se pudo publicar el archivo en Documentos.")
            }
        } catch (error: Exception) {
            context.contentResolver.delete(uri, null, null)
            throw error
        }
    }

    private fun mediaStoreBackups(context: Context): List<MediaStoreBackup> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return emptyList()
        val collection = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.DATE_MODIFIED,
            MediaStore.MediaColumns.RELATIVE_PATH,
        )
        return listOf(DOCUMENTS_BACKUP_PATH)
            .flatMap { path ->
                context.contentResolver.query(
                    collection,
                    projection,
                    "${MediaStore.MediaColumns.RELATIVE_PATH} = ?",
                    arrayOf(path),
                    "${MediaStore.MediaColumns.DATE_MODIFIED} DESC",
                )?.use { cursor ->
                    val idColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                    val nameColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                    val modifiedColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
                    val pathColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.RELATIVE_PATH)
                    buildList {
                        while (cursor.moveToNext()) {
                            val name = cursor.getString(nameColumn) ?: continue
                            if (!name.startsWith(AUTOMATIC_PREFIX) &&
                                !name.startsWith(MANUAL_PREFIX) &&
                                !name.startsWith(PRE_RESTORE_PREFIX)
                            ) continue
                            add(
                                MediaStoreBackup(
                                    ContentUris.withAppendedId(
                                        collection,
                                        cursor.getLong(idColumn),
                                    ),
                                    name,
                                    cursor.getLong(modifiedColumn),
                                    cursor.getString(pathColumn),
                                ),
                            )
                        }
                    }
                } ?: emptyList()
            }
    }

    private fun pruneMediaStoreBackups(context: Context) {
        mediaStoreBackups(context)
            .filter {
                it.relativePath == DOCUMENTS_BACKUP_PATH &&
                    it.name.startsWith(AUTOMATIC_PREFIX)
            }
            .sortedByDescending { it.name }
            .drop(MAX_AUTOMATIC_BACKUPS)
            .forEach { backup ->
                if (context.contentResolver.delete(backup.uri, null, null) != 1) {
                    throw IllegalStateException("No se pudo limpiar un respaldo automático antiguo.")
                }
            }
    }

    private fun installDatabaseAtomically(source: File, destination: File) {
        val parent = destination.parentFile
            ?: throw IllegalStateException("No se encontró la carpeta de la base local.")
        if (!parent.exists() && !parent.mkdirs()) {
            throw IllegalStateException("No se pudo preparar la carpeta de la base local.")
        }
        val replacement = File(parent, "startup-restore-${System.nanoTime()}.db")
        val previous = File(parent, "startup-previous-${System.nanoTime()}.db")
        source.copyTo(replacement, overwrite = false)
        try {
            validateDatabase(replacement)
            if (destination.exists() && !destination.renameTo(previous)) {
                throw IllegalStateException("No se pudo conservar la base local existente.")
            }
            if (!replacement.renameTo(destination)) {
                if (previous.exists()) previous.renameTo(destination)
                throw IllegalStateException("No se pudo instalar el respaldo más reciente.")
            }
            try {
                validateDatabase(destination)
            } catch (error: Exception) {
                destination.delete()
                if (previous.exists() && !previous.renameTo(destination)) {
                    throw IllegalStateException("No se pudo recuperar la base previa.", error)
                }
                throw error
            }
            previous.delete()
        } finally {
            replacement.delete()
            if (previous.exists() && destination.exists()) previous.delete()
        }
    }

    private fun createConsistentSnapshot(source: File, destination: File) {
        val database = SQLiteDatabase.openDatabase(
            source.absolutePath,
            null,
            SQLiteDatabase.OPEN_READWRITE,
        )
        try {
            val checkpointBusy = database.rawQuery("PRAGMA wal_checkpoint(FULL)", null).use { cursor ->
                if (!cursor.moveToFirst()) 1 else cursor.getInt(0)
            }
            if (checkpointBusy != 0) {
                throw IllegalStateException("La base está ocupada; se reintentará el respaldo.")
            }
            database.beginTransaction()
            try {
                source.inputStream().use { input ->
                    destination.outputStream().use { output -> input.copyTo(output) }
                }
                database.setTransactionSuccessful()
            } finally {
                database.endTransaction()
            }
        } finally {
            database.close()
        }
        validateDatabase(destination)
    }

    private fun recordDatabaseBackup(databasePath: String) {
        val database = SQLiteDatabase.openDatabase(
            databasePath,
            null,
            SQLiteDatabase.OPEN_READWRITE,
        )
        try {
            database.execSQL(
                "UPDATE configuracion SET ultimo_respaldo = ?",
                arrayOf(System.currentTimeMillis()),
            )
        } finally {
            database.close()
        }
    }

    private fun pruneAutomaticBackups(directory: DocumentFile) {
        val automaticFiles = directory.listFiles()
            .filter { it.isFile && it.name?.startsWith(AUTOMATIC_PREFIX) == true }
            .sortedByDescending { it.name }
        automaticFiles.drop(MAX_AUTOMATIC_BACKUPS).forEach { file ->
            if (!file.delete()) {
                throw IllegalStateException("No se pudo limpiar un respaldo automático antiguo.")
            }
        }
    }

    private fun preferences(context: Context) =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
}
