# Field mechanisms — deployment-specific, described by aim and dependencies

The process references several mechanisms whose *implementations* are specific to our deployment and are not included here. This file states what each aims to do and what it depends on, so you can implement equivalents for your stack. None of them are exotic; all are small scripts or conventions.

## Invariant gate suite (`gates.sh` + tests)
**Aim:** make every process rule that matters fail loudly and orchestrator-independently — laneless commits can't land, done-claims without evidence block gates, plans with ownership overlaps never reach review. **Dependencies:** git hooks (`commit-msg`, `pre-commit`), a shell runner, `formats.json` (schemas/regexes), and a `tests/` directory of negative tests — one per gate, proving the gate fires when it should (the non-vacuity requirement). In our deployment this evolved from a ~40-check assertions script; the critical addition was the negative tests, after three separate checks went silently inert.

## `formats.json` (single machine home for formats)
**Aim:** one authoritative definition of every ID pattern, status vocabulary, evidence-citation regex, and artifact schema — consumed by *both* the enforcement script and the status derivation script, so enforcement and reporting can never disagree about a format, and a format change is one edit plus one updated test. **Dependencies:** JSON, discipline that `FORMATS.md` (the human view) defers to it.

## `status.mjs` (derived status)
**Aim:** replace persistent narrative state files entirely — current position, progress, requirement-status rollups, and audit-trigger counters are computed on demand from the requirements file, the `runs/` layout, and git. **Dependencies:** `formats.json` schemas, git log/plumbing, the runs directory conventions. It exists because every hand-maintained counter in our deployment eventually lied.

## Gap registration ("no silent gaps")
**Aim:** guarantee that every known limitation, mock, or unvalidated claim exists as a structured, taxonomy-tagged record with a named successor and discharge condition — and that the registry is the *only* path (adding a gap outside the registration path is itself a gate failure). Its companion invariant reconciles code-level mocks against registered gaps, so a mock that isn't a declared gap fails the build. **Dependencies:** a registration function or single registry file, a mock-detection convention in the codebase, and one reconciliation check in the gate suite.

## Coevolution stamps
**Aim:** bind contract documents to the code state they describe: a document section carries the commit SHA it was verified against, and a check flags the pair when the code moves and the doc doesn't. The codebase-map freshness rule in P0 (front-matter `verified_against` + path globs, "fresh ⇔ no commits touching those paths since that SHA") is the same idea generalized. **Dependencies:** git, front-matter conventions, the sweep in the gate suite.

## file:line preflight
**Aim:** citations into code (`path:line` or content anchors) are verified as match / drifted / gone before they land, so contract docs never accumulate dead references. **Dependencies:** a small resolver script; preference for content anchors over line numbers.

## Handoff exam (heavyweight variant, optional)
**Aim:** verify that a fresh session actually inherits project knowledge: the outgoing session writes questions, the fresh session answers with citations, answers are graded — doubling as a documentation-drift detector (in our deployment a perfect-score exam still surfaced three stale-doc defects). We simplified this to the capped, overwritten HANDOFF.md plus derived status; the exam pattern is worth knowing for high-stakes handoffs. **Dependencies:** none beyond discipline; automatable with a grading agent.

## Milestone audits
**Aim:** a periodic adversarial pass over a completed milestone asking not "did the gates pass" but "did the work answer the actual question" — the premise-level backstop that caught our worst failure (everything green, zero real value). Triggered by the numeric audit triggers in P4 or scheduled. **Dependencies:** an auditor agent or human with access to the spec lineage, run reports, and gap registry.
