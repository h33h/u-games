package games.yandex.wrap.util

fun <T, K> Iterable<T>.dedupeBy(key: (T) -> K): List<T> {
    val seen = LinkedHashSet<K>()
    val out = ArrayList<T>()
    for (item in this) {
        if (seen.add(key(item))) out.add(item)
    }
    return out
}

fun <T, K> Collection<T>.appendUniqueBy(items: Iterable<T>, key: (T) -> K): List<T> {
    val seen = LinkedHashSet<K>()
    val out = ArrayList<T>(size)
    for (item in this) {
        seen.add(key(item))
        out.add(item)
    }
    for (item in items) {
        if (seen.add(key(item))) out.add(item)
    }
    return out
}
