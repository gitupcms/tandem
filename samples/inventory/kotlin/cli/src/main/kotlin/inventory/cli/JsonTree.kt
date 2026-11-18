package inventory.cli

import tandem.Json

/** Small read helpers over the kit's JSON tree. */
internal fun Json?.field(key: String): Json? = (this as? Json.Obj)?.get(key)

internal val Json?.array: List<Json>? get() = (this as? Json.Arr)?.items
