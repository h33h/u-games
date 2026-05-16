import Foundation

struct TagDTO: Decodable {
    let slug: String
    let title: String
    let info: TagInfoDTO?
}
