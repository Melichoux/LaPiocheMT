@testable import App
import XCTVapor

final class GameTests: XCTestCase {
    func testCreateGameReturnsCreated() async throws {
        try await withApp { app in
            try await app.test(.POST, "games", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "Catan", minPlayers: 3, maxPlayers: 4, durationMinutes: 90
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .created)
                let game = try res.content.decode(GameDTO.self)
                XCTAssertEqual(game.title, "Catan")
                XCTAssertTrue(game.isAvailable)
            })
        }
    }

    func testCreateGameWithEmptyTitleIsRejected() async throws {
        try await withApp { app in
            try await app.test(.POST, "games", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "", minPlayers: 3, maxPlayers: 4, durationMinutes: 90
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testCreateGameWithInvertedPlayerBoundsIsRejected() async throws {
        try await withApp { app in
            try await app.test(.POST, "games", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "Catan", minPlayers: 5, maxPlayers: 2, durationMinutes: 90
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testListGames() async throws {
        try await withApp { app in
            _ = try await createGame(app, title: "Catan")
            _ = try await createGame(app, title: "Dixit")

            try await app.test(.GET, "games", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(try res.content.decode([GameDTO].self).count, 2)
            })
        }
    }

    func testShowGame() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let id = try XCTUnwrap(game.id)

            try await app.test(.GET, "games/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(try res.content.decode(GameDTO.self).id, id)
            })
        }
    }

    func testShowUnknownGameReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.GET, "games/\(UUID())", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }

    func testShowGameWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.GET, "games/not-a-uuid", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testPreflightRequestFromAnotherOriginIsAllowed() async throws {
        try await withApp { app in
            try await app.test(.OPTIONS, "games", beforeRequest: { req in
                req.headers.replaceOrAdd(name: .origin, value: "http://localhost:8080")
                req.headers.replaceOrAdd(name: .accessControlRequestMethod, value: "POST")
                req.headers.replaceOrAdd(name: .accessControlRequestHeaders, value: "content-type")
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(res.headers.first(name: .accessControlAllowOrigin), "*")
                XCTAssertTrue(res.headers[.accessControlAllowMethods].joined(separator: ",").contains("POST"))
            })
        }
    }

    func testErrorResponsesCarryTheCorsHeaders() async throws {
        try await withApp { app in
            try await app.test(.GET, "games/not-a-uuid", beforeRequest: { req in
                req.headers.replaceOrAdd(name: .origin, value: "http://localhost:8080")
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
                XCTAssertEqual(res.headers.first(name: .accessControlAllowOrigin), "*")
            })
        }
    }

// Tests on PUT
    func testUpdateGameReplacesItsInformation() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let id = try XCTUnwrap(game.id)

            try await app.test(.PUT, "games/\(id)", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "7 Wonders", minPlayers: 2, maxPlayers: 7, durationMinutes: 30
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let updated = try res.content.decode(GameDTO.self)
                XCTAssertEqual(updated.id, id)
                XCTAssertEqual(updated.title, "7 Wonders")
            })
        }
    }

    func testUpdateUnknownGameReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.PUT, "games/\(UUID())", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "7 Wonders", minPlayers: 2, maxPlayers: 7, durationMinutes: 30
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }

    func testUpdateGameWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.PUT, "games/not-a-uuid", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "7 Wonders", minPlayers: 2, maxPlayers: 7, durationMinutes: 30
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testUpdateGameWithInvertedPlayerBoundsIsRejected() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let id = try XCTUnwrap(game.id)

            try await app.test(.PUT, "games/\(id)", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "7 Wonders", minPlayers: 7, maxPlayers: 2, durationMinutes: 30
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }
    
// Tests on DELETE
    func testDeleteGameReturnsNoContent() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let id = try XCTUnwrap(game.id)

            try await app.test(.DELETE, "games/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .noContent)
            })
            try await app.test(.GET, "games/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }

    func testDeleteUnknownGameReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.DELETE, "games/\(UUID())", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }

    func testDeleteGameWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.DELETE, "games/uuid", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testDeleteGameWithOngoingLoanReturnsConflict() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let gameID = try XCTUnwrap(game.id)
            let memberID = try XCTUnwrap(member.id)
            let now = Date()
            try await insertLoan(app, gameID: gameID, memberID: memberID,
                                 borrowedAt: now, dueAt: try Loan.dueDate(from: now))

            try await app.test(.DELETE, "games/\(gameID)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
            })
        }
    }

    func testDeleteGameWithFinishedLoanReturnsConflict() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let gameID = try XCTUnwrap(game.id)
            let memberID = try XCTUnwrap(member.id)
            let now = Date()
            try await insertLoan(app, gameID: gameID, memberID: memberID,
                                 borrowedAt: now, dueAt: try Loan.dueDate(from: now),
                                 returnedAt: now)

            try await app.test(.DELETE, "games/\(gameID)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
            })
        }
    }
    
// Tests on GET /games (search)
    private func seedSearchGames(_ app: Application) async throws {
        _ = try await createGame(app, title: "Catan", minPlayers: 3, maxPlayers: 4, durationMinutes: 60)
        _ = try await createGame(app, title: "Dixit", minPlayers: 3, maxPlayers: 8, durationMinutes: 30)
        _ = try await createGame(app, title: "Uno", minPlayers: 2, maxPlayers: 10, durationMinutes: 20)
    }

    private func searchTitles(_ app: Application, _ path: String) async throws -> Set<String> {
        var titles: Set<String> = []
        try await app.test(.GET, path, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            titles = Set(try res.content.decode([GameDTO].self).map(\.title))
        })
        return titles
    }

    func testSearchByTitleIgnoresCase() async throws {
        try await withApp { app in
            try await seedSearchGames(app)
            let lower = try await searchTitles(app, "games?q=cat")
            let upper = try await searchTitles(app, "games?q=CAT")
            XCTAssertEqual(lower, ["Catan"])
            XCTAssertEqual(upper, ["Catan"])
        }
    }

    func testSearchByPlayerCount() async throws {
        try await withApp { app in
            try await seedSearchGames(app)
            let titles = try await searchTitles(app, "games?players=6")
            XCTAssertEqual(titles, ["Dixit", "Uno"])
        }
    }

    func testSearchByMaxDuration() async throws {
        try await withApp { app in
            try await seedSearchGames(app)
            let titles = try await searchTitles(app, "games?maxDuration=30")
            XCTAssertEqual(titles, ["Dixit", "Uno"])
        }
    }

    func testSearchCombinesFilters() async throws {
        try await withApp { app in
            try await seedSearchGames(app)
            let titles = try await searchTitles(app, "games?players=6&maxDuration=20")
            XCTAssertEqual(titles, ["Uno"])
        }
    }

    func testSearchWithNoMatchReturnsEmptyList() async throws {
        try await withApp { app in
            try await seedSearchGames(app)
            let titles = try await searchTitles(app, "games?q=zzz")
            XCTAssertTrue(titles.isEmpty)
        }
    }

    func testSearchWithInvalidParametersReturnsBadRequest() async throws {
        try await withApp { app in
            let queries = ["players=abc", "players=0", "players=-2", "maxDuration=abc", "maxDuration=0"]
            for query in queries {
                try await app.test(.GET, "games?\(query)", afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .badRequest, query)
                })
            }
        }
    }
    
// Tests on GET /games?available
    func testFilterAvailableAndUnavailableGames() async throws {
        try await withApp { app in
            let borrowed = try await createGame(app, title: "Catan")
            _ = try await createGame(app, title: "Dixit")
            let member = try await createMember(app)
            _ = try await createLoan(app, gameID: try XCTUnwrap(borrowed.id), memberID: try XCTUnwrap(member.id))

            let available = try await searchTitles(app, "games?available=true")
            let unavailable = try await searchTitles(app, "games?available=false")
            XCTAssertEqual(available, ["Dixit"])
            XCTAssertEqual(unavailable, ["Catan"])
        }
    }

    func testReturnedGameCountsAsAvailable() async throws {
        try await withApp { app in
            let game = try await createGame(app, title: "Catan")
            let member = try await createMember(app)
            let loan = try await createLoan(app, gameID: try XCTUnwrap(game.id), memberID: try XCTUnwrap(member.id))
            let loanID = try XCTUnwrap(loan.id)

            try await app.test(.POST, "loans/\(loanID)/return", afterResponse: { _ async throws in })

            let available = try await searchTitles(app, "games?available=true")
            XCTAssertEqual(available, ["Catan"])
        }
    }

    func testAvailabilityFilterCombinesWithSearchFilters() async throws {
        try await withApp { app in
            _ = try await createGame(app, title: "Catan", minPlayers: 3, maxPlayers: 4, durationMinutes: 60)
            let dixit = try await createGame(app, title: "Dixit", minPlayers: 3, maxPlayers: 8, durationMinutes: 30)
            _ = try await createGame(app, title: "Uno", minPlayers: 2, maxPlayers: 10, durationMinutes: 20)
            let member = try await createMember(app)
            _ = try await createLoan(app, gameID: try XCTUnwrap(dixit.id), memberID: try XCTUnwrap(member.id))

            let available = try await searchTitles(app, "games?players=6&available=true")
            let unavailable = try await searchTitles(app, "games?players=6&available=false")
            XCTAssertEqual(available, ["Uno"])
            XCTAssertEqual(unavailable, ["Dixit"])
        }
    }

    func testWithoutAvailabilityFilterReturnsAllGames() async throws {
        try await withApp { app in
            let borrowed = try await createGame(app, title: "Catan")
            _ = try await createGame(app, title: "Dixit")
            let member = try await createMember(app)
            _ = try await createLoan(app, gameID: try XCTUnwrap(borrowed.id), memberID: try XCTUnwrap(member.id))

            let titles = try await searchTitles(app, "games")
            XCTAssertEqual(titles, ["Catan", "Dixit"])
        }
    }

    func testInvalidAvailabilityReturnsBadRequest() async throws {
        try await withApp { app in
            for value in ["yes", "1", "TRUE", ""] {
                try await app.test(.GET, "games?available=\(value)", afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .badRequest, value)
                })
            }
        }
    }
}
