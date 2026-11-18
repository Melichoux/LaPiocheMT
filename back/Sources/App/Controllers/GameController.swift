import Fluent
import Vapor

struct GameController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let games = routes.grouped("games")
        games.get(use: index)
        games.post(use: create)
        
        games.group(":gameID") {game in
            game.get(use: show)
            game.put(use: update)
            game.delete(use: delete)
        }
    }

    @Sendable
    func index(req: Request) async throws -> [GameDTO] {
        let players = try positiveInt("players", in: req)
        let maxDuration = try positiveInt("maxDuration", in: req)
        let available = try availabilityFilter(in: req)

        let query = Game.query(on: req.db).with(\.$loans)

        if let q = req.query[String.self, at: "q"] {
            query.filter(\.$title ~~ q)
        }
        if let players {
            query.filter(\.$minPlayers <= players)
            query.filter(\.$maxPlayers >= players)
        }
        if let maxDuration {
            query.filter(\.$durationMinutes <= maxDuration)
        }

        var games = try await query.all()
        if let available {
            games = games.filter { $0.isAvailable == available }
        }
        return games.map { $0.toDTO() }
    }

    @Sendable
    func create(req: Request) async throws -> Response {
        try CreateGameDTO.validate(content: req)
        let dto = try req.content.decode(CreateGameDTO.self)
        try dto.ensureConsistentPlayerCount()

        let game = dto.toModel()
        try await game.save(on: req.db)
        let response = try await game.toDTO().encodeResponse(for: req)
        response.status = .created
        return response
    }

    @Sendable
    func show(req: Request) async throws -> GameDTO {
        try await findGame(req).toDTO()
    }

    private func findGame(_ req: Request) async throws -> Game {
        guard let gameID = req.parameters.get("gameID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid game id")
        }
        guard let game = try await Game.query(on: req.db)
            .filter(\.$id == gameID)
            .with(\.$loans)
            .first()
        else {
            throw Abort(.notFound, reason: "Game not found")
        }
        return game
    }
    
    private func positiveInt(_ name: String, in req: Request) throws -> Int? {
        guard let raw = req.query[String.self, at: name] else {
            return nil
        }
        guard let value = Int(raw), value > 0 else {
            throw Abort(.badRequest, reason: "\(name) must be a positive integer")
        }
        return value
    }
    
    private func availabilityFilter(in req: Request) throws -> Bool? {
        guard let raw = req.query[String.self, at: "available"] else {
            return nil
        }
        switch raw {
        case "true":
            return true
        case "false":
            return false
        default:
            throw Abort(.badRequest, reason: "available must be true or false")
        }
    }
    
    @Sendable
    func update(req: Request) async throws -> GameDTO {
        let game = try await findGame(req)
        try CreateGameDTO.validate(content: req)
        let dto = try req.content.decode(CreateGameDTO.self)
        try dto.ensureConsistentPlayerCount()

        game.title = dto.title
        game.minPlayers = dto.minPlayers
        game.maxPlayers = dto.maxPlayers
        game.durationMinutes = dto.durationMinutes
        try await game.update(on: req.db)
        return game.toDTO()
    }
    
    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        let game = try await findGame(req)
        guard game.loans.isEmpty else {
            throw Abort(.conflict, reason: "Game has loans and cannot be deleted")
        }
        try await game.delete(on: req.db)
        return .noContent
    }
}
