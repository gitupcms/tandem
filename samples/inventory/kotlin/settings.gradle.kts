rootProject.name = "inventory"

include("core", "cli")

// The kit lives in the repository's Kotlin build; use it as a composite build instead of a copy.
includeBuild("../../../kotlin")
