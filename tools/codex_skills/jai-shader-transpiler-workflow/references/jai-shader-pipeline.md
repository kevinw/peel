# Shader Pipeline Policy

## Preferred Pipeline

- Default path: Jai -> IR -> SPIR-V text -> SPIR-V tools -> SPIRV-Cross -> target source.
- Legacy Slang path only when explicitly enabled.

## Backend Priorities

- Primary targets: Metal and Vulkan GLSL.
- Keep behavior fail-fast during active backend development.

## Testing Strategy

1. Use headless compute and graphics tests for semantic parity (CPU vs GPU).
2. Expand coverage incrementally with minimal shader cases.
3. Run full transpiler suite once headless changes are green.

## Code Quality Guidance

- Avoid test-specific brittle string matching in core lowering.
- Prefer representation changes that generalize across compute/vertex/fragment.
- Keep diagnostics explicit (location + reason) at lowering/emission failure points.
