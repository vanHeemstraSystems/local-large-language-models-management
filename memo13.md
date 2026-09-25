# Memo 13: Continuous Automated Refactoring Loop

Status

Proposed architecture for vanHeemstraSystems/local-large-language-models-management.

Context

A local LLM can be used as a continuous refactoring worker for GitHub repositories, provided that refactoring is treated as a controlled feedback loop rather than unrestricted autonomous code modification.

The proposed system continuously observes a repository, identifies a refactoring opportunity, selects an appropriate implementation mechanism, applies the change in an isolated branch, verifies the result, and produces a pull request when the change satisfies defined quality gates.

GitHub Actions provides the orchestration layer. Workflows can be triggered by repository events, schedules, manual dispatches, and external repository_dispatch events. Jobs execute ordered steps on runners, making Actions suitable for coordinating detection, implementation, verification, and PR creation. GitHub Actions workflows and workflow syntax document these capabilities. (GitHub Docs)

Objective

Build a continuous refactoring loop that:

1. observes the current state of a codebase;
2. detects code smells and refactoring opportunities;
3. selects one bounded refactoring;
4. chooses the most appropriate implementation mechanism;
5. applies the change on an isolated branch;
6. runs automated verification;
7. measures the result against the pre-refactoring state;
8. creates a pull request when the change passes;
9. rejects or rolls back unsuccessful changes;
10. repeats on a subsequent iteration.

The system should optimize for safe, measurable improvement, not maximum autonomous activity.

Proposed Architecture

                         GitHub repository
                               │
                               ▼
                    ┌─────────────────────┐
                    │ Refactoring         │
                    │ Coordinator         │
                    └──────────┬──────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │ Observe             │
                    │                     │
                    │ smells              │
                    │ tests               │
                    │ complexity          │
                    │ duplication         │
                    │ architecture        │
                    └──────────┬──────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │ Select candidate    │
                    │                     │
                    │ one bounded change  │
                    └──────────┬──────────┘
                               │
                    ┌──────────┴──────────┐
                    ▼                     ▼
          ┌──────────────────┐   ┌──────────────────┐
          │ Deterministic    │   │ LLM refactoring  │
          │ transformation   │   │                  │
          │                  │   │ Local Qwen       │
          │ AST / recipes    │   │ Cloud escalation │
          └────────┬─────────┘   └────────┬─────────┘
                   │                      │
                   └──────────┬───────────┘
                              ▼
                    ┌─────────────────────┐
                    │ Verify              │
                    │                     │
                    │ tests               │
                    │ typecheck           │
                    │ lint                │
                    │ build               │
                    │ architecture        │
                    │ smell analysis      │
                    └──────────┬──────────┘
                               │
                       ┌───────┴────────┐
                       │                │
                     PASS             FAIL
                       │                │
                       ▼                ▼
                  Pull Request       discard
                       │
                       ▼
                human/policy review
                       │
                       ▼
                     merge
                       │
                       └──────────────► next iteration

Three Refactoring Mechanisms

1. Deterministic refactoring

Use deterministic tools whenever the transformation can be expressed reliably as a program transformation.

Examples:

* import changes;
* symbol renaming;
* API migrations;
* syntax transformations;
* dependency migrations;
* dead-code removal;
* formatting;
* mechanical TypeScript transformations.

OpenRewrite is particularly relevant because it provides automated source transformation through recipes. OpenRewrite documents recipe development for JavaScript and TypeScript, including recipes that operate on real JavaScript codebases. (OpenRewrite Docs)

This should be the preferred mechanism for transformations that do not require architectural judgement.

2. Local LLM refactoring

Use the local Qwen model when the transformation requires contextual reasoning.

Potential examples:

* identifying duplicated abstractions;
* simplifying overly complex functions;
* improving names;
* extracting abstractions;
* identifying repeated implementation patterns;
* improving tests;
* suggesting architectural refactorings;
* translating a detected smell into a concrete code change.

The local model should receive a tightly scoped task rather than unrestricted repository ownership.

3. Cloud-model escalation

Escalate to a cloud model when the local model cannot complete the task within its configured limits.

Possible escalation conditions:

* local model timeout;
* repeated failed attempts;
* context exceeds local model capacity;
* architectural change spans many files;
* confidence is low;
* verification repeatedly fails;
* multiple competing designs require deeper reasoning.

This creates a natural routing hierarchy:

deterministic transformation
        ↓
local Qwen
        ↓
cloud LLM
        ↓
human review

The router should prefer the cheapest mechanism capable of safely completing the task.

Bounded Refactoring

Every autonomous refactoring should have an explicit budget.

Example:

refactoring:
  max_files: 8
  max_lines_changed: 250
  max_iterations: 3
  required:
    - tests
    - typecheck
    - lint
    - build
  forbidden:
    - public_api_changes
    - dependency_major_versions
    - configuration_changes

These limits should be repository-specific rather than hard-coded into the LLM.

The purpose is to prevent a small code-smell correction from silently becoming an architectural rewrite.

Before/After Measurement

The refactoring engine should measure the repository before and after each change.

Example baseline:

{
  "smells": 47,
  "complexity": 182,
  "duplication": 13,
  "tests": 421,
  "coverage": 84.2
}

After refactoring:

{
  "smells": 45,
  "complexity": 174,
  "duplication": 11,
  "tests": 421,
  "coverage": 84.7
}

The system can then record:

smells       -2
complexity   -8
duplication  -2
tests         0
coverage     +0.5%

This gives the refactoring engine an objective feedback signal.

A change that merely produces a large diff should not be considered successful. The desired property is measurable improvement while preserving behaviour.

Initial Safety Model

The first implementation should not automatically merge arbitrary LLM-generated changes.

Use:

detect
  ↓
refactor
  ↓
verify
  ↓
pull request
  ↓
human approval
  ↓
merge

After sufficient operational history has been collected, individual classes of highly predictable transformations can be eligible for automatic merging.

For example:

deterministic transformation
  + narrow scope
  + complete tests
  + no public API change
  + all verification passes
  ↓
eligible for automatic merge

The merge policy should therefore be based on the class of transformation and evidence of reliability, rather than simply trusting the LLM.

GitHub Workflow Model

A first implementation could use scheduled and manual workflows:

on:
  schedule:
    - cron: "17 2 * * *"
  workflow_dispatch:

GitHub Actions supports scheduled workflows and manual workflow_dispatch execution. Repository events can also be used to trigger subsequent analysis. (GitHub Docs)

A future implementation could additionally use:

on:
  push:
    branches:
      - main
  pull_request:
  repository_dispatch:

repository_dispatch is particularly interesting for the Local LLMs Management architecture because an external coordinator can initiate a GitHub workflow and provide an event payload. (GitHub Docs)

Local LLM Worker Architecture

The GitHub repository should remain the source of truth.

The Mac mini can act as a local refactoring worker:

                         GitHub
                           │
                           │ task
                           ▼
                 Refactoring Coordinator
                           │
             ┌─────────────┴─────────────┐
             ▼                           ▼
       Local Qwen                    Cloud LLM
       Mac mini                      escalation
             │                           │
             └─────────────┬─────────────┘
                           ▼
                    verification
                           │
                           ▼
                         PR

This is particularly useful for reducing cloud-token expenditure: simple and medium-complexity refactorings can remain local, while difficult tasks are escalated only when necessary.

Relationship to Memo Implementation Engine

The existing Memo Implementation Engine concept can provide the routing mechanism.

A memo can describe an implementation task such as:

Implement refactoring R123.
Constraints:
- maximum 5 files
- no public API changes
- preserve existing tests
- TypeScript only
- run lint, typecheck and tests

The engine determines whether R123 should be:

* implemented deterministically;
* assigned to local Qwen;
* escalated to a cloud model;
* returned for human implementation.

This makes continuous refactoring another consumer of the same implementation-routing architecture.

Relationship to Code Smell Detective

The Code Smell Detective can become the observation and decision layer:

Code Smell Detective
        │
        ├── detect
        ├── classify
        ├── prioritize
        └── formulate refactoring
                 │
                 ▼
          Refactoring Engine
                 │
                 ├── deterministic
                 ├── local LLM
                 ├── cloud LLM
                 └── human

The Detective should not directly mutate the repository.

Instead, it should produce a structured refactoring proposal that the Refactoring Engine can execute and verify.

This separation makes the architecture easier to test and audit.

Recommended First MVP

Implement the smallest useful closed loop:

GitHub
  ↓
scheduled Action
  ↓
run Code Smell Detective
  ↓
select ONE smell
  ↓
create branch
  ↓
send bounded task to local Qwen
  ↓
run tests/typecheck/lint
  ↓
measure before/after
  ↓
create PR

Do not initially implement automatic merging.

The first goal should be to demonstrate that the system can repeatedly produce small, valid, reviewable improvements.

Future Evolution

Once the MVP is reliable, add:

1. deterministic OpenRewrite recipes;
2. local/cloud model routing;
3. refactoring confidence scores;
4. persistent refactoring history;
5. before/after quality metrics;
6. automatic rollback;
7. retry limits;
8. Jev/Council-based architectural decision support;
9. selective automatic merging;
10. repository-wide continuous refactoring campaigns.

The long-term objective is a self-improving software maintenance loop in which the repository continuously receives small, verified improvements while human developers retain control over architectural decisions.

References

* GitHub Actions — Workflows: GitHub Actions Workflows documentation
* GitHub Actions — Workflow syntax: GitHub Actions workflow syntax
* GitHub Actions — Events that trigger workflows: GitHub Actions events documentation
* OpenRewrite — Authoring recipes: OpenRewrite recipe documentation
* OpenRewrite — JavaScript/TypeScript recipe development: OpenRewrite JavaScript recipe development
* OpenRewrite — JavaScript refactoring recipe example: OpenRewrite JavaScript refactoring recipe
