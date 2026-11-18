package tandem

/**
 * Marks a class whose stored properties are exposed as one screen-state object on the wire.
 *
 * Every primary-constructor property becomes a state key with the property's own name, which is why
 * a state class needs a primary constructor made only of `val`/`var` properties. `tandem-ksp`
 * generates an extension function `fun X.toJson(): tandem.Json` in the declaration's package.
 */
@Target(AnnotationTarget.CLASS)
@Retention(AnnotationRetention.SOURCE)
annotation class Introspectable

/**
 * Marks a `sealed interface` whose direct subclasses are the screen's actions.
 *
 * `tandem-ksp` generates `object <EnclosingType><Interface>Introspection` in the declaration's
 * package, with `fun actions(send: (T) -> Unit): List<tandem.Action>` in declaration order. Each
 * subclass contributes one kit action named after the subclass, and its constructor parameters
 * become the action's input object.
 */
@Target(AnnotationTarget.CLASS)
@Retention(AnnotationRetention.SOURCE)
annotation class IntrospectableActions

/**
 * Marks an `enum class` that travels as a string. The wire value is the constant's name, exactly as
 * declared.
 */
@Target(AnnotationTarget.CLASS)
@Retention(AnnotationRetention.SOURCE)
annotation class IntrospectableEnum
