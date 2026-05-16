import Foundation

struct GameMediaDTO: Decodable {
    let cover: ImageDTO?
    let icon: ImageDTO?
    let videos: [VideoDTO]?
}
