package games.yandex.wrap.data

import android.content.Context
import androidx.room.Database
import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverter
import androidx.room.TypeConverters

@Entity(tableName = "favorites")
data class FavoriteEntity(
    @PrimaryKey val appId: Long,
    val title: String,
    val coverUrl: String,
    val addedAtMs: Long,
)

@Entity(tableName = "game_cache")
data class GameCacheEntity(
    @PrimaryKey val appId: Long,
    val title: String,
    val rating: Float,
    val ratingCount: Int,
    val coverUrl: String,
    val iconUrl: String,
    val categories: List<String>,
    val developer: String,
    val updatedAtMs: Long,
)

class StringListConverter {
    @TypeConverter
    fun toJson(value: List<String>): String = value.joinToString("|")

    @TypeConverter
    fun fromJson(value: String): List<String> =
        if (value.isEmpty()) emptyList() else value.split("|")
}

@Database(
    entities = [FavoriteEntity::class, GameCacheEntity::class],
    version = 1,
    exportSchema = false,
)
@TypeConverters(StringListConverter::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun favoritesDao(): FavoritesDao
    abstract fun gameCacheDao(): GameCacheDao

    companion object {
        fun create(context: Context): AppDatabase = Room.databaseBuilder(
            context.applicationContext,
            AppDatabase::class.java,
            "u-games.db",
        ).build()
    }
}
