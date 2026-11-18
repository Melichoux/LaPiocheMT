import Fluent
import Vapor

struct MemberController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let members = routes.grouped("members")
        members.get(use: index)
        members.post(use: create)
        members.group(":memberID") { member in
            member.get(use: show)
            member.put(use: update)
            member.delete(use: delete)
        }
    }

    @Sendable
    func index(req: Request) async throws -> [MemberDTO] {
        try await Member.query(on: req.db).all().map { $0.toDTO() }
    }

    @Sendable
    func create(req: Request) async throws -> Response {
        try CreateMemberDTO.validate(content: req)
        let dto = try req.content.decode(CreateMemberDTO.self)

        let emailTaken = try await Member.query(on: req.db)
            .filter(\.$email == dto.email)
            .count() > 0
        guard !emailTaken else {
            throw Abort(.conflict, reason: "A member with this email already exists")
        }

        let member = dto.toModel()
        try await member.save(on: req.db)
        return try await member.toDTO().encodeResponse(status: .created, for: req)
    }

    @Sendable
    func show(req: Request) async throws -> MemberDTO {
        guard let memberID = req.parameters.get("memberID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid member id")
        }
        guard let member = try await Member.find(memberID, on: req.db) else {
            throw Abort(.notFound, reason: "Member not found")
        }
        return member.toDTO()
    }
    
    private func findMember(_ req: Request) async throws -> Member {
        guard let memberID = req.parameters.get("memberID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid member id")
        }
        guard let member = try await Member.find(memberID, on: req.db) else {
            throw Abort(.notFound, reason: "Member not found")
        }
        return member
    }
    
    @Sendable
    func update(req: Request) async throws -> MemberDTO {
        let member = try await findMember(req)
        try CreateMemberDTO.validate(content: req)
        let dto = try req.content.decode(CreateMemberDTO.self)

        let memberID = try member.requireID()
        let emailTakenByAnother = try await Member.query(on: req.db)
            .filter(\.$email == dto.email)
            .filter(\.$id != memberID)
            .count() > 0
        guard !emailTakenByAnother else {
            throw Abort(.conflict, reason: "this email already exists")
        }

        member.name = dto.name
        member.email = dto.email
        try await member.update(on: req.db)
        return member.toDTO()
    }
    
    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        let member = try await findMember(req)
        let memberID = try member.requireID()
        let hasLoans = try await Loan.query(on: req.db)
            .filter(\.$member.$id == memberID)
            .count() > 0
        guard !hasLoans else {
            throw Abort(.conflict, reason: "Member has loans and cannot be deleted")
        }
        try await member.delete(on: req.db)
        return .noContent
    }
}
