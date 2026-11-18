package tandem.ksp

import com.google.devtools.ksp.processing.KSPLogger
import com.google.devtools.ksp.symbol.KSAnnotated
import com.google.devtools.ksp.symbol.KSClassDeclaration
import com.google.devtools.ksp.symbol.KSNode
import com.google.devtools.ksp.symbol.KSType

internal const val INTROSPECTABLE = "tandem.Introspectable"
internal const val INTROSPECTABLE_ACTIONS = "tandem.IntrospectableActions"
internal const val INTROSPECTABLE_ENUM = "tandem.IntrospectableEnum"

/**
 * The wire shape of one Kotlin type, following the mapping table in `.orkestra/f7-ortak.md`.
 * [Maybe] appears only around a whole field; its value is omitted from state JSON and left out of
 * the input's `required` list.
 */
internal sealed interface Wire {
    data object Text : Wire

    /** `kotlin.Int` or `kotlin.Long`; [kotlinType] decides how a checked value is read back. */
    data class Integer(val kotlinType: String) : Wire
    data object Flag : Wire

    /** An `@IntrospectableEnum`; [type] is its qualified name, [constants] keep declaration order. */
    data class Choice(val type: String, val constants: List<String>) : Wire

    /** An `@Introspectable` state class; its primary constructor is the shape. */
    data class Record(val type: String, val packageName: String, val fields: List<Field>) : Wire

    data class Sequence(val item: Wire) : Wire

    data class Maybe(val value: Wire) : Wire
}

/** One property of a [Wire.Record] or one input parameter of an action, in declaration order. */
internal class Field(val name: String, val wire: Wire) {
    val nullable: Boolean get() = wire is Wire.Maybe
}

internal fun KSAnnotated.hasAnnotation(qualifiedName: String): Boolean =
    annotations.any { it.annotationType.resolve().declaration.qualifiedName?.asString() == qualifiedName }

/** Turns Kotlin types into [Wire] shapes, logging one clear error per unsupported type. */
internal class TypeResolver(private val logger: KSPLogger) {

    fun wire(type: KSType, context: String, node: KSNode?): Wire? {
        val declaration = type.declaration as? KSClassDeclaration
            ?: return unsupported(type, context, node)
        val base = when (val qualified = declaration.qualifiedName?.asString()) {
            "kotlin.String" -> Wire.Text
            "kotlin.Int" -> Wire.Integer("kotlin.Int")
            "kotlin.Long" -> Wire.Integer("kotlin.Long")
            "kotlin.Boolean" -> Wire.Flag
            "kotlin.collections.List" -> {
                val itemType = type.arguments.firstOrNull()?.type?.resolve()
                    ?: return unsupported(type, context, node)
                val item = wire(itemType, context, node) ?: return null
                if (item is Wire.Maybe) {
                    logger.error(
                        "tandem: nullable list items are not supported at $context; " +
                            "use List<T> where T is never null",
                        node,
                    )
                    return null
                }
                Wire.Sequence(item)
            }

            else -> when {
                declaration.hasAnnotation(INTROSPECTABLE_ENUM) -> {
                    if (declaration.classKind != com.google.devtools.ksp.symbol.ClassKind.ENUM_CLASS) {
                        logger.error("tandem: @IntrospectableEnum needs an enum class at $context", node)
                        return null
                    }
                    Wire.Choice(qualified!!, enumConstants(declaration))
                }

                declaration.hasAnnotation(INTROSPECTABLE) ->
                    Wire.Record(
                        qualified!!,
                        declaration.packageName.asString(),
                        recordFields(declaration, context) ?: return null,
                    )

                else -> return unsupported(type, context, node)
            }
        }
        return if (type.isMarkedNullable) Wire.Maybe(base) else base
    }

    private fun enumConstants(declaration: KSClassDeclaration): List<String> =
        declaration.declarations
            .filterIsInstance<KSClassDeclaration>()
            .filter { it.classKind == com.google.devtools.ksp.symbol.ClassKind.ENUM_ENTRY }
            .map { it.simpleName.asString() }
            .toList()

    /** Primary-constructor properties of a state class, in declaration order. */
    fun recordFields(declaration: KSClassDeclaration, context: String): List<Field>? {
        val constructor = declaration.primaryConstructor
        if (constructor == null) {
            logger.error(
                "tandem: @Introspectable class ${declaration.qualifiedName?.asString()} needs a " +
                    "primary constructor so its state keys have a fixed order",
                declaration,
            )
            return null
        }
        val properties = declaration.getAllProperties().map { it.simpleName.asString() }.toSet()
        val fields = mutableListOf<Field>()
        var ok = true
        for (parameter in constructor.parameters) {
            val name = parameter.name?.asString()
            if (name == null) {
                logger.error("tandem: a state property without a name is not supported", parameter)
                ok = false
                continue
            }
            if (name !in properties) {
                logger.error(
                    "tandem: constructor parameter '$name' of ${declaration.qualifiedName?.asString()} " +
                        "must be a val/var property so it can travel as state",
                    parameter,
                )
                ok = false
                continue
            }
            val wire = wire(parameter.type.resolve(), "$context.$name", parameter)
            if (wire == null) ok = false else fields += Field(name, wire)
        }
        return if (ok) fields else null
    }

    /** Constructor parameters of one action subclass; each becomes an input property. */
    fun inputFields(subclass: KSClassDeclaration, context: String): List<Field>? {
        val constructor = subclass.primaryConstructor ?: return emptyList()
        val fields = mutableListOf<Field>()
        var ok = true
        for (parameter in constructor.parameters) {
            val name = parameter.name?.asString()
            if (name == null) {
                logger.error("tandem: an input property without a name is not supported at $context", parameter)
                ok = false
                continue
            }
            val wire = wire(parameter.type.resolve(), "$context.$name", parameter)
            if (wire == null) ok = false else fields += Field(name, wire)
        }
        return if (ok) fields else null
    }

    private fun unsupported(type: KSType, context: String, node: KSNode?): Wire? {
        logger.error(
            "tandem: unsupported type '$type' at $context; use String, Int, Long, Boolean, " +
                "an @IntrospectableEnum, an @Introspectable state class, or a List of those",
            node,
        )
        return null
    }
}
