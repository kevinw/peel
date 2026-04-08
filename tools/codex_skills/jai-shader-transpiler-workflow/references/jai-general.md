# Jai Programming

Prefer idioms that are common in `~/jai/how_to` and `~/jai/modules`.

## Language-first workflow

1. Start from known examples in `~/jai/how_to`.
- Core language and data:
  - `004_arrays.jai`, `005_strings.jai`, `006_structs.jai`, `007_struct_literals.jai`
- Control flow and expressions:
  - `019_looping.jai`, `022_if.jai`, `025_ifx.jai`, `027_if_case.jai`
- Advanced language:
  - `042_using.jai`, `080_scopes.jai`, `100_polymorphic_procedures.jai`, `200_memory_management.jai`, `225_comma_comma.jai`

2. Match patterns from standard modules in `~/jai/modules`.
- Core defaults and utilities: `~/jai/modules/Basic/module.jai`
- Arrays/strings/helpers from Basic subfiles loaded by that module.
- If a module exists, import it instead of reinventing utilities.

3. Prefer module boundaries over textual coupling.
- Use `#import "Module"` for isolated module scope.
- Use `Name :: #import "Module"` when namespacing helps clarity.
- Use `#load` only when you explicitly want textual inclusion semantics.
- For reusable/shared helpers (especially shared structs), prefer `#import`/`#import,file` + namespaced access instead of `#load` to avoid duplicate global declarations during refactors.

## Jai idioms and style

- Keep Jai edits idiomatic and direct; avoid porting C/C++ build-system habits.
- Prefer `#import "Basic"` for common runtime functionality unless the project intentionally avoids it.
- Use `context` intentionally:
  - treat allocator/log/assert behavior as contextual policy, not hidden globals.
  - use `push_allocator(...)` for scoped allocator changes.
- Manage allocations explicitly:
  - pair heap allocations with `defer free(...)`.
  - use temporary storage when lifetime is bounded to the current scope.
- Distinguish array-like types correctly:
  - fixed arrays (`[N]T`) for compile-time size,
  - dynamic arrays (`[..]T`) for growable ownership,
  - slices (`[]T`) for borrowed views.
- Use slice/array operations idiomatically:
  - iterate with `for`,
  - favor clear indexing and count checks,
  - avoid unnecessary casts/conversions.
- Use `using` to reduce boilerplate when it improves readability:
  - `using` parameters/struct fields for local access,
  - avoid wide `using` that obscures where names come from.
- Use `ifx` for expression-style branching where it is clearer than statement `if`.
- Use polymorphism and compile-time features for reusable, type-driven code:
  - polymorphic procedures/arguments where they simplify call sites,
  - avoid over-templating when concrete code is clearer.
- Keep procedures small and explicit about ownership/mutation.

## Fast lookup commands

- Find relevant how_to lesson:
  - `rg --files ~/jai/how_to | rg 'arrays|strings|using|memory|context|comma|ifx|polymorphic|scopes'`
- Find module API symbols:
  - `rg -n "symbol_name ::" ~/jai/modules`
- Find allocator/context helpers in Basic:
  - `rg -n "push_allocator|alloc\\(|free\\(|context\\." ~/jai/modules/Basic`

## Output expectations

When implementing Jai changes, provide:
- the exact files changed,
- the build/test command(s) run,

## Minimal metaprogram note

Only when the task is explicitly build/metaprogram related:
- use `~/jai/how_to/400_workspaces.jai` and `~/jai/how_to/450_basic_metaprogram/first.jai` as baseline patterns,
- keep metaprogram logic small and separate from core runtime code.
