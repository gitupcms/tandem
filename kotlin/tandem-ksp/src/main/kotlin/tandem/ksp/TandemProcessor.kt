package tandem.ksp

import com.google.devtools.ksp.processing.CodeGenerator
import com.google.devtools.ksp.processing.KSPLogger
import com.google.devtools.ksp.processing.Resolver
import com.google.devtools.ksp.processing.SymbolProcessor
import com.google.devtools.ksp.symbol.ClassKind
import com.google.devtools.ksp.symbol.FileLocation
import com.google.devtools.ksp.symbol.KSAnnotated
import com.google.devtools.ksp.symbol.KSClassDeclaration
import com.google.devtools.ksp.symbol.Modifier

/**
 * Generates the introspection code described in `.orkestra/f7-ortak.md`: `toJson` for
 * `@Introspectable` state classes and one `...Introspection` object for `@IntrospectableActions`
 * interfaces. `@IntrospectableEnum` only marks a type; its constants travel by name.
 */
internal class TandemProcessor(
    private val codeGenerator: CodeGenerator,
    private val logger: KSPLogger,
) : SymbolProcessor {
    private val types = TypeResolver(logger)

    override fun process(resolver: Resolver): List<KSAnnotated> {
        generateStates(resolver)
        checkEnums(resolver)
        generateActions(resolver)
        return emptyList()
    }

    private fun generateStates(resolver: Resolver) {
        resolver.getSymbolsWithAnnotation(INTROSPECTABLE)
            .filterIsInstance<KSClassDeclaration>()
            .forEach { declaration ->
                val name = declaration.qualifiedName?.asString() ?: return@forEach
                if (declaration.classKind != ClassKind.CLASS) {
                    logger.error("tandem: @Introspectable needs a class, not $name", declaration)
                    return@forEach
                }
                val fields = types.recordFields(declaration, name) ?: return@forEach
                writeStateJson(
                    codeGenerator = codeGenerator,
                    record = Wire.Record(name, declaration.packageName.asString(), fields),
                    packageName = declaration.packageName.asString(),
                    source = declaration.containingFile,
                )
            }
    }

    private fun checkEnums(resolver: Resolver) {
        resolver.getSymbolsWithAnnotation(INTROSPECTABLE_ENUM)
            .filterIsInstance<KSClassDeclaration>()
            .forEach { declaration ->
                if (declaration.classKind != ClassKind.ENUM_CLASS) {
                    logger.error(
                        "tandem: @IntrospectableEnum needs an enum class, not " +
                            "${declaration.qualifiedName?.asString()}",
                        declaration,
                    )
                }
            }
    }

    private fun generateActions(resolver: Resolver) {
        resolver.getSymbolsWithAnnotation(INTROSPECTABLE_ACTIONS)
            .filterIsInstance<KSClassDeclaration>()
            .forEach { declaration ->
                val name = declaration.qualifiedName?.asString() ?: return@forEach
                if (declaration.classKind != ClassKind.INTERFACE) {
                    logger.error("tandem: @IntrospectableActions needs a sealed interface, not $name", declaration)
                    return@forEach
                }
                if (Modifier.SEALED !in declaration.modifiers) {
                    logger.error("tandem: @IntrospectableActions interface $name must be sealed", declaration)
                    return@forEach
                }
                val subclasses = declaration.getSealedSubclasses()
                    .sortedWith(
                        compareBy(
                            { it.containingFile?.filePath ?: "" },
                            { (it.location as? FileLocation)?.lineNumber ?: 0 },
                        ),
                    )
                    .toList()
                val entries = subclasses.mapNotNull { subclass ->
                    val subclassName = subclass.qualifiedName?.asString() ?: return@mapNotNull null
                    types.inputFields(subclass, subclassName)?.let { ActionEntry(subclass, it) }
                }
                if (entries.size != subclasses.size) return@forEach
                writeActions(
                    codeGenerator = codeGenerator,
                    declaration = declaration,
                    entries = entries,
                    packageName = declaration.packageName.asString(),
                )
            }
    }
}
