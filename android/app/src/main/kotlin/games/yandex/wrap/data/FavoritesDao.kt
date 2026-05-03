package games.yandex.wrap.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface FavoritesDao {
    @Query("SELECT * FROM favorites ORDER BY addedAtMs DESC")
    fun observeAll(): Flow<List<FavoriteEntity>>

    @Query("SELECT EXISTS(SELECT 1 FROM favorites WHERE appId = :appId)")
    suspend fun isFavorite(appId: Long): Boolean

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: FavoriteEntity)

    @Query("DELETE FROM favorites WHERE appId = :appId")
    suspend fun delete(appId: Long)
}

@Dao
interface RecentGamesDao {
    @Query("SELECT * FROM recent_games ORDER BY openedAtMs DESC LIMIT :limit")
    fun observe(limit: Int = 20): kotlinx.coroutines.flow.Flow<List<RecentGameEntity>>

    @Query("SELECT * FROM recent_games ORDER BY openedAtMs DESC LIMIT :limit")
    suspend fun latest(limit: Int = 20): List<RecentGameEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: RecentGameEntity)

    @Query("DELETE FROM recent_games WHERE appId NOT IN (SELECT appId FROM recent_games ORDER BY openedAtMs DESC LIMIT :keep)")
    suspend fun trim(keep: Int = 50)
}

@Dao
interface GameCacheDao {
    @Query("SELECT * FROM game_cache WHERE updatedAtMs >= :sinceMs ORDER BY updatedAtMs DESC")
    suspend fun fresh(sinceMs: Long): List<GameCacheEntity>

    @Query("SELECT * FROM game_cache ORDER BY updatedAtMs DESC LIMIT :limit")
    suspend fun latest(limit: Int = 50): List<GameCacheEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(entities: List<GameCacheEntity>)

    @Query("DELETE FROM game_cache")
    suspend fun clear()
}
