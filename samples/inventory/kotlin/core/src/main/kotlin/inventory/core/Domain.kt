package inventory.core

/** A product as the inventory backend reports it. */
data class Product(
    val id: String,
    val title: String,
    val sku: String,
    val price: String,
    val quantity: Int,
)

/** A failed service call, carrying the backend's first message. */
class ServiceError(message: String) : Exception(message)

/** The small result type the sample needs; a failure always carries a [ServiceError]. */
sealed interface ServiceResult<out T> {
    data class Success<T>(val value: T) : ServiceResult<T>
    data class Failure(val error: ServiceError) : ServiceResult<Nothing>
}

/** Everything the view models need from the outside world. Injected through constructors. */
interface InventoryService {
    fun fetchProducts(): ServiceResult<List<Product>>

    fun adjust(productId: String, delta: Int): ServiceResult<Unit>
}
