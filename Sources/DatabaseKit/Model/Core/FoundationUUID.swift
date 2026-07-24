#if canImport(FoundationEssentials)
import FoundationEssentials

package typealias FoundationUUID = FoundationEssentials.UUID
#else
import Foundation

package typealias FoundationUUID = Foundation.UUID
#endif
