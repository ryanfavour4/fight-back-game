# FIGHT BACK — PROJECT DEVELOPMENT RULES

## 1. Project Integrity

Fight Back is an existing Godot project. Preserve its working functionality, architecture and assets unless an explicitly approved task requires changes.

Never assume that something is disposable because it appears unused, outdated, redundant or unrelated to the currently implemented game.

## 2. Permission Boundaries

Every task must be treated according to its explicitly stated permission level.

- **READ-ONLY:** Inspect, analyse and report. Do not modify anything.
- **PROPOSE CHANGES:** Identify proposed changes and explain their impact. Do not execute them.
- **IMPLEMENT:** Modify only the explicitly authorised scope.
- **CLEANUP:** Remove or reorganise only items individually covered by the approved cleanup plan.

An instruction to audit, review, analyse, inspect or investigate never grants permission to modify files.

## 3. Asset Protection

Do not delete, move, rename, overwrite, convert or reorganise assets without explicit approval.

This includes:

- Character sprites and animations.
- Character reference sheets.
- Backgrounds and stage artwork.
- UI kits and individual UI elements.
- Logos, fonts, icons and illustrations.
- Audio and sound effects.
- Source artwork, original files and reference materials.
- Version 2 assets, whether currently referenced by the game or not.

An asset being unused in the current implementation does not mean it is unnecessary.

## 4. Preserve Existing Functionality

Do not remove, merge, rewrite or replace existing managers, systems, scripts, scenes, resources, signals or networking implementations merely to simplify the architecture.

Identify dependencies and potential regressions before proposing structural changes.

## 5. No Unauthorised Scope Expansion

Do not introduce additional features, dependencies, frameworks, architectural patterns or refactoring outside the requested task.

Do not make product, gameplay, character roster or visual design decisions independently.

## 6. Verification

Before implementing an approved change:

- Inspect the relevant existing implementation.
- Identify affected files and dependencies.
- Explain potential risks.
- Establish how the change will be verified.

After implementation:

- List every modified, created, moved and deleted file.
- Report tests and verification results.
- Identify anything that could not be verified.
- Do not claim success without evidence.

## 7. Communication

If an instruction is ambiguous, stop and ask for clarification.

Never interpret silence, an audit request or a general improvement objective as permission to make changes.

The developer retains final authority over project structure, assets, gameplay, architecture and visual direction.
