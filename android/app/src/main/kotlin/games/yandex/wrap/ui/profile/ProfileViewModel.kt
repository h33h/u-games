package games.yandex.wrap.ui.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import games.yandex.wrap.catalog.ProfileRepository
import games.yandex.wrap.catalog.UserProfile
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Backs ProfileScreen. Resilience (Session_id wait + retry back-off) lives
 * in [ProfileRepository.userProfileWithRetry] so Home and Profile share
 * the exact same recovery path post-auth.
 */
class ProfileViewModel(private val repository: ProfileRepository) : ViewModel() {

    private val _profile = MutableStateFlow<UserProfile?>(null)
    val profile: StateFlow<UserProfile?> = _profile.asStateFlow()

    init { refresh() }

    fun refresh() {
        viewModelScope.launch {
            val p = runCatching { repository.userProfileWithRetry() }.getOrNull()
            if (p != null) _profile.value = p
        }
    }

    fun signOut(onDone: () -> Unit = {}) {
        viewModelScope.launch {
            runCatching { repository.clearSession() }
            _profile.value = null
            onDone()
        }
    }
}
