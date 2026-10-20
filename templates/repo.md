# Repo profile

Written by the legwork agent at setup, reviewed once by a human, kept fresh
by the verify stage when an executor or qa report says the profile is wrong.
Every command below must come from evidence in the repo. `unknown` is a valid
value; a guessed command is not.

## Basics

- main branch:
- merge policy (squash or merge):
- PR template path:
- ticket prefix:
- package manager / task runner:

## Commands

- install:
- build:
- test (all):
- test (one file):
- type check:
- lint:
- codegen:
- after checkout or rebase (what must run before the repo is usable again):

## Running and capturing

- launch the app:
- capture a screenshot of a screen (command taking `<route> <out.png>`):
- notes (simulators, devices, env vars, seed data):

## Worktrees

- setup command to run inside a fresh worktree:
- things that break in a worktree:

## Rules the repo already has

- instructions files (CLAUDE.md, AGENTS.md, rules dirs):
- test style and test-quality rules:
- skills worth naming (path and what for):
- PR conventions (title format, required sections):

## Tracker mirror

Leave all three `unknown` when the repo has no connected tracker.

- create ticket (command or skill that returns the new id):
- fetch ticket by id (command or skill):
- attach PR link to a ticket (command or skill):

## Profile feedback

Appended by the lead when a report says the profile was wrong or incomplete.
Newest last.

