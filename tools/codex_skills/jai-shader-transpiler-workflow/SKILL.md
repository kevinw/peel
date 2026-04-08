---
name: jai-shader-transpiler-workflow
description: Use for Jai metaprogramming plugin work, especially shader transpilation and IR/backend changes in peel. Apply when editing Jai AST-lowering code, #scope/#load module organization, note collection and code insertion (#poke_name, add_build_string), or validating Jai->IR->SPIR-V->SPIRV-Cross shader outputs and headless compute parity tests.
---

# Jai Shader Transpiler Workflow

Use this skill to keep Jai transpiler work consistent, fast, and debuggable.

## Follow This Workflow

1. Confirm the target path first.
- Prefer `/Users/kev/src/peel/modules/Jai-Shader-Transpiler/ir_pipeline` for new backend/lowering work.
- Keep broad policy in shared files and stage-specific logic in backend files.

2. Respect Jai module/scope rules.
- Use `#import "Basic";` directly unless a named namespace is required.
- Treat `#load` as textual insertion.
- For reusable/shared helpers (especially structs used across plugin/runtime), prefer module ownership via `#import`/`#import,file` and namespace access (e.g. `M.Type`) instead of `#load`; this avoids duplicate global declarations during refactors.
- Use `#scope_export` only for public API.
- Use `#scope_module` for cross-file internal helpers.
- Use `#scope_file` only for truly local helpers (and place it near the bottom when practical).

3. Keep metaprogram insertion patterns safe.
- Prefer a known generated module scope for emitted compile-time declarations.
- Use `#poke_name` when inserting symbols into a target scope.
- Use scoped `add_build_string(..., message=...)` only with safe message/scope context.
- Avoid holding fragile AST-derived pointers across unsafe boundaries.

4. Prefer assert-driven invariants.
- Use `assert(...)` for required preconditions.
- Return failure only for real alternate/error paths.
- Emit diagnostic context on fail-fast paths.

5. Validate quickly and repeatedly.
- Use the headless compute path first for semantics checks.
- Then run plugin tests.
- Keep generated shader diagnostics readable.

6. Prefer compiler and IR truth over reparsing emitted text.
- If the compiler or lowering phase already has parsed AST, lowered IR, resolved declarations, or concrete type info, use that data directly.
- Do not add ad hoc parsers for formatted shader text or pretty-printed expressions unless there is a specific upstream representation gap that cannot be closed cleanly.
- For constant evaluation, specialize, fold, or inspect the lowered IR instead of reparsing `*_text` fields in a backend.
- Treat “parse our own generated text back into semantics” as a code smell and justify it explicitly before proceeding.

## Learned Cleanup Patterns

- Move large helper domains (timings, manifest IO, reload metadata, formatting helpers) into dedicated files and `#load` them.
- Keep top-level plugin flow readable: message handling, request routing, emission orchestration.

2. Standardize file layout.
- Put API-facing declarations first.
- Keep local helpers under `#scope_file` near the bottom.
- Group file-local imports with local helper scope (bottom placement is preferred when practical).

3. Centralize external tool execution.
- Route `slangc`, `spirv-link`, `spirv-opt`, `spirv-cross` invocations through shared checked wrappers.
- Avoid ad-hoc `run_command` calls in feature code paths.

4. Prefer single-pass string normalization.
- For identifier/path cleanup, use one mutation loop where possible instead of repeated `replace(...)` chains.

5. Gate optional pipeline stages explicitly.
- Add top-level feature flags (e.g. `USE_SPIRV_OPT`) and define a deterministic fallback path when disabled.

6. Share manifest schema across producer/consumer.
- Keep manifest structs/types in a shared module.
- Make writer/reader code depend on shared types instead of duplicating field lists.

7. Use local `using` in dense state-reset/report code.
- In cleanup/report blocks, use scoped `using` to reduce repetitive `plugin.` or other local access while keeping ownership obvious.

8. Prefer inline struct literals for one-off IR statement construction.
- When appending `IR_Stmt` values, prefer `array_add(*dst, .{ ... })`/`array_add(*dst, { ... })` over declaring a mutable temp and assigning fields line-by-line.

9. Preserve source/IR provenance when lowering.
- When constructing lowered IR nodes, keep `origin_node` and other already-available provenance unless there is a deliberate reason not to.
- Before inventing fallback heuristics, check whether the lowering path accidentally dropped information that downstream passes actually need.

## Run Commands

- Full transpiler tests:
  - `cd /Users/kev/src/peel/modules/Jai-Shader-Transpiler && jai -quiet build.jai - -run_tests`
- Peel (the game prototyping app we're developing using the transpiler) app builds:
  - `cd /Users/kev/src/peel && jai build.jai`

## References

- General Jai programming: [references/jai-general.md](references/jai-general.md)
- Metaprogramming patterns: [references/jai-metaprogramming.md](references/jai-metaprogramming.md)
- Scope/module rules: [references/jai-scope-rules.md](references/jai-scope-rules.md)
- Shader backend policy: [references/jai-shader-pipeline.md](references/jai-shader-pipeline.md)
