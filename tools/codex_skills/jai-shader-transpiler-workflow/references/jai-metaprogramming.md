# Jai Metaprogramming Notes

## Goal

Capture durable patterns for compile-time shader code generation and symbol insertion.

## Preferred Patterns

- Collect note-driven declarations/calls first, then emit generated declarations in one controlled pass.
- Use a stable generated module as a known insertion/lookup scope.
- Inject lookup symbols with `#poke_name` when cross-scope linking is required.
- Keep `lookup_transpiled` typed and resolve generated constants from the generated module body.

## `add_build_string` Guidance

- Prefer the scoped overload that takes `(data, workspace, message, ...)` when targeting specific scopes.
- Use `message` only when the scope source is stable and valid.
- Avoid passing stale/derived AST context pointers that may become invalid during compile-time phases.

## Practical Rule

- If generation order matters, stage the data in notes/tables and emit once in a deterministic pass.
