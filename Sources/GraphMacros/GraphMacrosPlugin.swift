import SwiftCompilerPlugin
import SwiftSyntaxMacros

/// Compiler plugin entry point for Graph macros
@main
struct GraphMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        OWLDataPropertyMacro.self,
        OWLClassMacro.self,
        OWLObjectPropertyMacro.self,
    ]
}
