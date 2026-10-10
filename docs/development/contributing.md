# Contributing

> How to make a change: the workflow, the tests and warnings checks to run, and the conventions for code and documentation.

**Source:** `.github/workflows/test.yml`, `gutconfig.json`, `Makefile`

---

## Workflow

1. Work on a branch, not `main`.
2. Make the change, and add or update tests in `tests/unit/` for logic, or in `tests/integration/` for a flow through the game.
3. Run the checks below until they pass.
4. Update the documentation for any system you changed. See [Documentation Conventions](#documentation-conventions).
5. Open a pull request with a clear description of what changed and why.

## Checks

```bash
make test       # unit tests (GUT)
make warnings   # GDScript warnings must be zero
```

Continuous integration runs both on Ubuntu 24.04, in two jobs named `unit` and `warnings`. See `.github/workflows/test.yml`.

The integration scenes in `tests/integration/` and the scenes in `tests/harness/` are not run by CI. Run them by hand when a change touches their area. See [Testing](testing.md).

## Code Conventions

- **GDScript** with static typing where it helps. Keep logic in systems and managers, and keep the scene scripts thin.
- **Signals on `EventBus`** for anything that crosses systems. Name events in the past tense when they describe something that happened, and in the present tense when they describe state.
- **Data in `data/`** for content such as buildings, decorations and visitors. Terrain behaviour is defined in `terrain_types.gd`.
- **Save compatibility.** Save format changes must still load older saves. Append new terrain ids to the end of the enum, because saves store them as numbers.
- **Warnings are errors.** Fix every GDScript warning. `make warnings` checks this.

## Documentation Conventions

Each system doc in `docs/systems/` follows the same template:

1. A title and a one-paragraph blockquote summary.
2. A **Source** line that lists the scripts and a **Tests** line.
3. **Plain English**: what the player sees, in everyday words.
4. **Algorithm**: the rules, with code-style blocks for formulas and the names of the functions that run them.
5. **Tuning Levers**: a table of the constants and their current values, with the file that holds each one.
6. **Related**: links to the docs a reader will likely need next.

Rules for keeping docs accurate:

- Name functions and constants, not line numbers. Line numbers go stale.
- Check numbers against the code before writing them down.
- Keep one topic per doc. Link to other docs rather than repeating their rules.
- Use the heading names above exactly, so the docs look the same.

## Related

- [Building & Running](building.md) covers setup.
- [Testing](testing.md) covers the test suites.
- [Architecture](../architecture.md) explains how the pieces fit together.
