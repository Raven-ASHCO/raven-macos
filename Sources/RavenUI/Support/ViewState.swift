import SwiftUI

/// Local view state, equivalent to SwiftUI's `@State`.
///
/// In the macOS 27 SDK `@State` is a macro whose implementation ships only with Xcode, so a package
/// built with the Command Line Tools cannot use it. `@ViewState` stores a plain `State` value inside a
/// `DynamicProperty`; SwiftUI finds and manages it exactly like `@State`. It also works under Xcode.
@propertyWrapper
public struct ViewState<Value>: DynamicProperty {
    private let storage: State<Value>

    public init(wrappedValue: Value) {
        storage = State(initialValue: wrappedValue)
    }

    public var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }

    public var projectedValue: Binding<Value> { storage.projectedValue }
}
