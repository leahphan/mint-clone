# Rails Code Quality

## Design

- Prefer the simplest conventional Rails implementation that satisfies the current requirements.
- Prefer clarity over cleverness.
- Do not introduce abstractions, configuration, or extension points for hypothetical future requirements.
- Do not apply DRY mechanically. Small duplication is preferable to an abstraction that combines code which only happens to look similar.
- Extract shared behavior when it represents the same domain concept, occurs repeatedly, or materially improves readability or testability.
- Reuse existing helpers, partials, scopes, components, and services before creating another abstraction.

## Responsibilities

- Controllers should coordinate HTTP concerns and delegate business operations. Avoid substantial business logic in controllers.
- Models should own associations, validations, invariants, persistence-related behavior, and domain behavior intrinsic to that model.
- Use a service object when a use case coordinates multiple models, contains a multi-step workflow, manages an explicit database transaction, performs external I/O, or has significant side effects.
- Do not extract a service object merely because a model method is long. First determine whether the behavior actually belongs to the model.
- Prefer named Active Record scopes for simple reusable queries.
- Consider a query object only when query logic becomes complex enough that scopes or controllers become difficult to understand.
- Avoid model callbacks for multi-step workflows or external side effects.
- Use callbacks only for behavior tightly coupled to the record lifecycle.

## Database and Data Integrity

- Enforce important invariants in the database where practical using foreign keys, `null: false`, unique indexes, and appropriate constraints.
- Use model validations as the user-friendly application layer, but do not rely on validations as the only protection against concurrency.
- Use database transactions when multiple writes must succeed or fail together.
- When correctness relies on a database constraint under concurrency, handle the expected database exception.
- Never use floating-point types for monetary values.
- Before adding an index, inspect existing indexes and the actual query pattern.
- Preserve source/provenance information when it is important for auditability or future reconciliation.

## Performance

- Before completing a change, inspect changed code for N+1 queries, queries inside loops, repeated aggregate queries, and unnecessary association loading.
- When rendering collections that access associations, preload or eager-load appropriately.
- Prefer database aggregation such as `SUM`, `COUNT`, and grouping over loading records and calculating aggregates in Ruby when practical.
- Do not issue one balance, count, or aggregate query per row when the values can reasonably be loaded in one query.
- Avoid loading unbounded collections into memory.
- Add pagination when a user-facing collection can grow without bound.
- Do not add caching or speculative performance optimizations without a demonstrated need.
- Do not claim a performance improvement without evidence when the change is non-trivial.
- Use query logs, `EXPLAIN`, benchmarks, or measurement when appropriate.

## Testing

- Test externally meaningful behavior and business invariants, not private implementation details.
- Every bug fix should include a regression test that fails without the fix when practical.
- Cover the happy path and meaningful failure or edge cases.
- Do not generate exhaustive low-value tests.
- Prefer real application objects and database behavior over mocking our own models.
- If production correctness relies on a database constraint or transaction rollback, test that behavior.
- If production correctness relies on a race-condition recovery path, test that recovery path deterministically where possible rather than introducing flaky concurrency tests.
- Green tests do not prove the requirement was understood. Re-read the requirement before declaring the task complete.
- Tests should verify intended behavior, not merely reproduce the implementation.

## Rails Conventions

- Prefer standard Rails conventions over custom framework-like abstractions.
- Prefer RESTful routes and conventional controller actions when they fit the feature.
- Prefer Rails helpers, associations, scopes, validations, and built-in framework behavior before adding custom infrastructure.
- Avoid service objects, concerns, decorators, presenters, and query objects unless they solve a concrete readability or responsibility problem.
- Keep controllers thin, but do not move controller code into a service object solely to satisfy a stylistic rule.
- Keep models cohesive, but do not force all business logic out of models.
- Prefer explicit, readable code over metaprogramming.

## Maintainability

- Keep methods focused on one coherent responsibility.
- Use names that describe domain meaning rather than implementation details.
- Avoid boolean arguments when separate named operations would be clearer.
- Avoid deeply nested conditionals when guard clauses or extraction would make the flow clearer.
- Avoid hidden side effects.
- Prefer explicit dependencies and data flow.
- Do not change unrelated files.
- Do not perform opportunistic refactors outside the scope of the requested task unless they are necessary for correctness.
- When touching an existing abstraction, understand how it is used before changing it.

## Frontend

- Prefer existing shared partials, helpers, Tailwind tokens, and component classes before adding new ones.
- Avoid duplicating large Tailwind class strings when a repeated visual primitive already exists.
- Do not create a shared component for one-off markup unless there is a clear reuse or readability benefit.
- Preserve semantic HTML and accessibility.
- Keep forms properly labelled.
- Preserve useful focus states and keyboard navigation.
- Avoid JavaScript for behavior Rails, Turbo, or Stimulus already handles cleanly.
- Do not add React or another frontend framework unless explicitly requested.

## Security

- Use strong parameters for controller input.
- Do not interpolate untrusted values into SQL.
- Do not expose secrets, credentials, tokens, or sensitive financial data in logs.
- Treat uploaded files and external input as untrusted.
- Validate file type, size, structure, and content where appropriate.
- Prefer least-privilege access and minimal data retention.
- Run Brakeman for security-sensitive or cross-cutting changes.

## Dependencies

- Do not add a gem or JavaScript dependency without a clear reason.
- Before adding a dependency, check whether Rails, Ruby, PostgreSQL, or the existing stack already provides the needed capability.
- Prefer mature, maintained dependencies with a clear benefit.
- Avoid dependencies for trivial behavior that can be implemented clearly with the standard library.
- When adding a dependency, explain why it is warranted.

## Completion Checklist

Before saying a non-trivial task is complete:

- Re-read the original requirements.
- Inspect the complete Git diff.
- Confirm the implementation satisfies the requested behavior.
- Look for unrelated changes.
- Look for unnecessary abstraction.
- Look for duplicated logic that represents the same domain concept.
- Review database access for N+1 queries or repeated queries.
- Review data-integrity and concurrency implications where relevant.
- Review security implications where relevant.
- Check whether collections can grow without bound.
- Run the relevant tests.
- Run RuboCop.
- Run Brakeman when appropriate.
- Run broader checks when the change is cross-cutting.
- State any assumptions, limitations, or behavior that remains unverified.

## Review Mindset

- Do not assume an implementation is correct because tests pass.
- Do not invent issues merely to produce review findings.
- Prioritize correctness, data integrity, security, performance, and maintainability over stylistic preferences.
- Distinguish real risks from optional improvements.
- Prefer small, targeted fixes over large rewrites.
- When there are multiple reasonable designs, explain the tradeoff instead of treating one style as universally correct.