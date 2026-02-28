# Domain

Pure domain logic lives here. No Polysemy effects, no IO.

Modules in this directory should:
- Define domain types (newtypes, records, enums)
- Implement pure functions over those types
- Be independently testable without any effect machinery
