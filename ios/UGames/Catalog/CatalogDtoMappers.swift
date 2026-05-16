import Foundation

extension FeedResponseDTO {
    var feedWithBlocks: FeedWithBlocks {
        let mappedBlocks = feed.orEmpty.map { $0.domain }
        return FeedWithBlocks(
            blocks: mappedBlocks,
            flatGames: mappedBlocks.flatMap { $0.items },
            recentGames: recentGames.orEmpty.map { $0.domain },
            genres: [],
            nextPageId: pageInfo?.nextPageId,
            hasNext: pageInfo?.hasNextPage ?? (pageInfo?.nextPageId != nil)
        )
    }

    var feedPage: FeedPage {
        FeedPage(
            games: feed.orEmpty.flatMap { $0.items.orEmpty.map { $0.domain } },
            nextPageId: pageInfo?.nextPageId,
            hasNext: pageInfo?.hasNextPage ?? (pageInfo?.nextPageId != nil)
        )
    }
}

extension SimilarGamesResponseDTO {
    var gamesDomain: [Game] {
        if let games {
            return games.map { $0.domain }
        }
        return feed.orEmpty.flatMap { $0.items.orEmpty.map { $0.domain } }
    }
}

extension TagsResponseDTO {
    var categories: [GameCategory] {
        tags.orEmpty.compactMap { tag in
            guard !tag.slug.isEmpty, !tag.title.isEmpty else { return nil }
            return GameCategory(name: tag.slug, title: tag.title, gamesCount: tag.info?.gamesCount ?? 0)
        }
    }
}

extension GetGameResponseDTO {
    var appDetail: AppDetail? {
        guard let game else { return nil }
        return AppDetail(
            description: game.description,
            screenshots: game.media?.screenshots.orEmpty.values.flatMap { $0 }.compactMap { $0.prefixUrl ?? $0.url } ?? [],
            datePublished: game.datePublished,
            genres: game.categoriesNames.orEmpty,
            languages: game.inLanguage.orEmpty,
            author: game.developer?.name
        )
    }
}

extension ProfileResponseDTO {
    var userProfile: UserProfile? {
        guard let userData, !userData.uid.isEmpty else { return nil }
        return UserProfile(
            isAuthorized: true,
            displayName: userData.displayName ?? "",
            login: userData.login ?? "",
            avatarUrl: userData.avatarUrl ?? "",
            hasYaPlus: userData.yaplusEnabled ?? false
        )
    }
}

extension FeedBlockDTO {
    var domain: FeedBlock {
        FeedBlock(type: type, size: size, title: title ?? "", items: items.orEmpty.map { $0.domain })
    }
}

extension GameDTO {
    var domain: Game {
        let coverPrefix = media?.cover?.prefixUrl
        let iconPrefix = media?.icon?.prefixUrl
        return Game(
            appId: appID,
            title: title,
            rating: rating ?? 0,
            ratingCount: ratingCount ?? 0,
            coverUrl: coverPrefix ?? "",
            iconUrl: iconPrefix ?? coverPrefix ?? "",
            categories: categoriesNames.orEmpty,
            developer: developer?.name ?? "",
            mainColor: media?.cover?.mainColor,
            iconMainColor: media?.icon?.mainColor,
            videoUrl: media?.videos.orEmpty.first?.mp4StreamUrl,
            coverPrefixUrl: coverPrefix,
            ageRating: features?.ageRating
        )
    }
}
