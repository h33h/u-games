import Foundation

struct DetailGameDTO: Decodable {
    let description: String?
    let media: DetailMediaDTO?
    let datePublished: String?
    let categoriesNames: [String]?
    let inLanguage: [String]?
    let developer: NamedDTO?
}
