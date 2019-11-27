import Validation
import Vapor

/// Wraps a (string representation of a) value including validation metadata. Can be validated.
public struct Field {
    
    /// Available field types.
    public enum FieldType {
        case text
        case password
        case email
    }

    /// The key that references this field.
    public let key: String
    
    /// The type of field.
    public let type: FieldType

    /// The value for this field represented as a `String`.
    public let value: String?

    /// A label describing this field. Used by Tags to render alongside an input field.
    public let label: String?
    
    /// The placeholder for this field.
    public let placeholder: String?

    /// Whether or not values are allowed to be absent.
    public let isRequired: Bool

    /// Performs the validations.
    public let validate: Validate

    /// Can validate asyncronously.
    public typealias Validate = (Request, ValidationContext) throws -> Future<[ValidationError]>

    /// Creates a new `Field`.
    ///
    /// - Parameters:
    ///   - key: The key that references this field.
    ///   - value: The value of this field.
    ///   - label: A label describing this field.
    ///   - validators: The validators to use when validating the value.
    ///   - asyncValidators: A closure to perform any additional validation that requires async.
    ///       Takes a request. See `Field.AsyncValidate`.
    ///   - isRequired: Whether or not the value is allowed to be absent. Defaults to `false`.
    ///   - requiredStrategy: Determines whether a field is required given a validation context.
    ///   - errorOnAbsence: The error to be thrown in the `create` context when value is absent as
    ///       determined by `absentValueStrategy` and `isRequired` is `true`.
    ///   - absentValueStrategy: Determines which values to treat as absent.
    public init<V: CustomStringConvertible>(
        key: String,
        type: FieldType,
        value: V? = nil,
        label: String? = nil,
        placeholder: String? = nil,
        validators: [Validator<V>] = [],
        asyncValidators: [Validate] = [],
        isRequired: Bool = false,
        requiredStrategy: RequiredStrategy = .onCreateOrUpdate,
        errorOnAbsence: ValidationError = BasicValidationError("is absent"),
        isAbsentWhen absentValueStrategy: AbsentValueStrategy<V> = .nil
    ) {
        let valueIfPresent = value.flatMap(absentValueStrategy.valueIfPresent)

        self.key = key
        self.type = type
        self.value = valueIfPresent?.description
        self.label = label
        self.placeholder = placeholder
        self.isRequired = isRequired

        validate = { req, context in
            let errors: [ValidationError]
            if let value = valueIfPresent {
                do {
                    errors = try validators.compactMap { validator in
                        do {
                            try validator.validate(value)
                            return nil
                        } catch let error as ValidationError {
                            return error
                        }
                    }
                } catch {
                    return req.future(error: error)
                }
            } else if isRequired, requiredStrategy.isRequired(context) {
                errors = [errorOnAbsence]
            } else {
                errors = []
            }

            return try asyncValidators
                .map { validator in try validator(req, context) }
                .flatten(on: req)
                .map {
                    $0.flatMap { $0 } + errors
                }
        }
    }
}

// MARK: - "Convenience" initializers

extension Field {

    /// Creates a new `Field` from an instance and keyPath.
    ///
    /// - Parameters:
    ///   - keyPath: The key path that references the value for this field.
    ///   - instance: The instance containing the value to be validated at `keyPath`.
    ///   - label: A label describing this field.
    ///   - validators: The validators to use when validating the value.
    ///   - asyncValidators: A closure to perform any additional validation that requires async.
    ///       Takes a request. See `Field.AsyncValidate`.
    ///   - isRequired: Whether or not the value is allowed to be absent.
    ///   - requiredStrategy: Determines whether a field is required given a validation context.
    ///   - errorOnAbsence: The error to be thrown in the `create` context when value is absent as
    ///       determined by `absentValueStrategy` and `isRequired` is `true`.
    ///   - absentValueStrategy: Determines which values to treat as absent.
    public init<S: Reflectable, V: CustomStringConvertible>(
        keyPath: KeyPath<S, V>,
        instance: S? = nil,
        type: FieldType,
        label: String? = nil,
        placeholder: String? = nil,
        validators: [Validator<V>] = [],
        asyncValidators: [Validate] = [],
        isRequired: Bool = false,
        requiredStrategy: RequiredStrategy = .onCreateOrUpdate,
        errorOnAbsence: ValidationError = BasicValidationError("is absent"),
        isAbsentWhen absentValueStrategy: AbsentValueStrategy<V> = .nil
    ) throws {
        self.init(
            key: try S.key(for: keyPath),
            type: type,
            value: instance?[keyPath: keyPath],
            label: label,
            placeholder: placeholder,
            validators: validators,
            asyncValidators: asyncValidators,
            isRequired: isRequired,
            requiredStrategy: requiredStrategy,
            errorOnAbsence: errorOnAbsence,
            isAbsentWhen: absentValueStrategy
        )
    }

    /// Creates a new `Field` from an instance and keyPath with an optional value.
    ///
    /// - Parameters:
    ///   - keyPath: The key path that references the value for this field.
    ///   - instance: The instance containing the value to be validated at `keyPath`.
    ///   - label: A label describing this field.
    ///   - validators: The validators to use when validating the value.
    ///   - asyncValidators: A closure to perform any additional validation that requires async.
    ///       Takes a request. See `Field.AsyncValidate`.
    ///   - isRequired: Whether or not the value is allowed to be absent.
    ///   - requiredStrategy: Determines whether a field is required given a validation context.
    ///   - errorOnAbsence: The error to be thrown in the `create` context when value is absent as
    ///       determined by `absentValueStrategy` and `isRequired` is `true`.
    ///   - absentValueStrategy: Determines which values to treat as absent.
    public init<S: Reflectable, V: CustomStringConvertible>(
        keyPath: KeyPath<S, V?>,
        instance: S? = nil,
        type: FieldType,
        label: String? = nil,
        placeholder: String? = nil,
        validators: [Validator<V>] = [],
        asyncValidators: [Validate] = [],
        isRequired: Bool = false,
        requiredStrategy: RequiredStrategy = .onCreateOrUpdate,
        errorOnAbsence: ValidationError = BasicValidationError("is absent"),
        isAbsentWhen absentValueStrategy: AbsentValueStrategy<V> = .nil
    ) throws {
        self.init(
            key: try S.key(for: keyPath),
            type: type,
            value: instance?[keyPath: keyPath],
            label: label,
            placeholder: placeholder,
            validators: validators,
            asyncValidators: asyncValidators,
            isRequired: isRequired,
            requiredStrategy: requiredStrategy,
            errorOnAbsence: errorOnAbsence,
            isAbsentWhen: absentValueStrategy
        )
    }
}

extension Reflectable {
    fileprivate static func key<T>(for keyPath: KeyPath<Self, T>) throws -> String {
        guard let paths = try Self.reflectProperty(forKey: keyPath)?.path, paths.count > 0 else {
            throw SubmissionError.invalidPathForKeyPath
        }

        return paths.joined(separator: ".")
    }
}
