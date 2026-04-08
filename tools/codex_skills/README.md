# Codex Skills

This directory holds repo-versioned Codex skills that we want to share across machines.

Codex does not auto-discover arbitrary repo-local `SKILL.md` files directly from the workspace. The normal discovery path is:

- `$CODEX_HOME/skills/<skill-name>`

So the intended setup is:

1. Keep the source-of-truth skill content in this repo.
2. Symlink each installed skill from `$CODEX_HOME/skills` to the matching directory here.

Current example:

```sh
ln -s /Users/kev/src/peel/tools/codex_skills/jai-shader-transpiler-workflow \
      /Users/kev/.codex/skills/jai-shader-transpiler-workflow
```

If the destination already exists and is a real directory, replace it:

```sh
rm -rf /Users/kev/.codex/skills/jai-shader-transpiler-workflow
ln -s /Users/kev/src/peel/tools/codex_skills/jai-shader-transpiler-workflow \
      /Users/kev/.codex/skills/jai-shader-transpiler-workflow
```

Notes:

- Commit changes in this repo directory, not in `$CODEX_HOME/skills`.
- Keep each skill self-contained: `SKILL.md`, optional `agents/`, optional `references/`, optional `scripts/`.
- If you clone Peel on another machine, recreate the symlink there after the repo is present.
