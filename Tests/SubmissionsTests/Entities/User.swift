import Submissions
import Validation
import Vapor

struct User: Content, Equatable, Reflectable {
    let name: String
    let requiredButOptional: Int?
    let emptyStringMeansAbsent: String
    let unique: String

    init(
        name: String = "",
        requiredButOptional: Int? = nil,
        emptyStringMeansAbsent: String = "",
        unique: String = "unique"
    ) {
        self.name = name
        self.requiredButOptional = requiredButOptional
        self.emptyStringMeansAbsent = emptyStringMeansAbsent
        self.unique = unique
    }
}

extension User: FieldsRepresentable {
    static func makeFields(for user: User? = nil) throws -> [Field] {
        return try [
            Field(
                keyPath: \.name,
                instance: user,
                type: .text,
                label: "Name",
                validators: [.count(2...)]
            ),
            Field(
                keyPath: \.requiredButOptional,
                instance: user,
                type: .text,
                isRequired: true
            ),
            Field(
                keyPath: \.emptyStringMeansAbsent,
                instance: user,
                type: .text,
                isRequired: true,
                isAbsentWhen: .equal(to: "")
            ),
            Field(
                keyPath: \.unique,
                instance: user,
                type: .text,
                asyncValidators: [{ req, _ in
                    guard user?.unique != "unique" else {
                        return req.future([BasicValidationError("must be unique")])
                    }
                    return req.future([])
                }]
            )
        ]
    }
}
