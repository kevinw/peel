# Jai Scope and Module Rules

## Imports

- `#import "Basic";` already brings `using Basic;` behavior unless the import is named.
- Name imports only when namespace qualification is intentional.

## Module Behavior

- Modules are deduplicated by module name by the compiler.
- `#load` is textual insertion into the current compilation scope.

## Scope Usage

- `#scope_export`: public API consumed outside the file.
- `#scope_module`: internal shared symbols across files in the module.
- `#scope_file`: file-local helpers only.

## Organization Convention

- Keep public entry points near top under `#scope_export`.
- Keep implementation helpers under `#scope_module`.
- Place purely local helper tails under `#scope_file`.
