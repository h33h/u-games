import Foundation

struct PageInfoDTO: Decodable {
    let nextPageId: String?
    let hasNextPage: Bool?
}
