package tandem

/** One action a node accepts. [perform] gets the checked input, or null when [input] is null. */
class Action(val name: String, val input: Schema? = null, val perform: (Json?) -> Unit)

/** A node only reports state and forwards actions to its view model; it holds no logic. */
class Node(
    val name: String,
    val state: Json = Json.obj(),
    val actions: List<Action> = emptyList(),
    val child: Node? = null,
)
