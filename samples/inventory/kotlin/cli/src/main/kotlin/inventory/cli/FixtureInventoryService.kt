package inventory.cli

import inventory.core.InventoryService
import inventory.core.Product
import inventory.core.ServiceError
import inventory.core.ServiceResult
import tandem.Json
import tandem.JsonError
import java.io.IOException
import java.nio.file.Files
import java.nio.file.Path

/**
 * Reads the sample's fixtures from [directory]. Everything is synchronous, as the contract says;
 * failures keep the backend's first message.
 */
class FixtureInventoryService(private val directory: Path) : InventoryService {

    override fun fetchProducts(): ServiceResult<List<Product>> {
        val document = read(PRODUCTS)
            ?: return failure("cannot read ${directory.resolve(PRODUCTS)}")
        document.field("errors").array?.firstOrNull().field("message")?.string?.let {
            return ServiceResult.Failure(ServiceError(it))
        }
        val nodes = document.field("data").field("products").field("nodes").array
            ?: return failure("$PRODUCTS has no data.products.nodes")
        val products = nodes.mapNotNull(::product)
        if (products.size != nodes.size) return failure("$PRODUCTS has an invalid product")
        return ServiceResult.Success(products)
    }

    override fun adjust(productId: String, delta: Int): ServiceResult<Unit> {
        val document = read(ADJUST)
            ?: return failure("cannot read ${directory.resolve(ADJUST)}")
        document.field("errors").array?.firstOrNull().field("message")?.string?.let {
            return ServiceResult.Failure(ServiceError(it))
        }
        val userErrors = document.field("data").field("inventoryAdjust").field("userErrors").array
            ?: return failure("$ADJUST has no data.inventoryAdjust.userErrors")
        val first = userErrors.firstOrNull() ?: return ServiceResult.Success(Unit)
        return ServiceResult.Failure(ServiceError(first.field("message")?.string ?: ""))
    }

    private fun product(node: Json): Product? {
        val id = node.field("id")?.string ?: return null
        val title = node.field("title")?.string ?: return null
        val sku = node.field("sku")?.string ?: return null
        val price = node.field("price")?.string ?: return null
        val quantity = node.field("quantity")?.long?.toInt() ?: return null
        return Product(id, title, sku, price, quantity)
    }

    private fun read(name: String): Json? = try {
        Json.decode(Files.readAllBytes(directory.resolve(name)))
    } catch (_: IOException) {
        null
    } catch (_: JsonError) {
        null
    }

    private fun <T> failure(message: String): ServiceResult<T> =
        ServiceResult.Failure(ServiceError(message))

    private companion object {
        const val PRODUCTS = "products.json"
        const val ADJUST = "adjust.json"
    }
}
