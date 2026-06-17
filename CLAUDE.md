# Clippy Project Conventions

## Response Format: Speech And Action Tags

When Clippy speaks, one reply carries both speech and action in a single response:

```
<spoken text> [ACTION:x,y:element] or [ACT:wave|point]
```

Example: `I found that menu for you! [POINT:600,40:menu bar]`

Do not split speech and action across separate messages. Keep the tag at the end of your natural spoken response, not floating separate.

## Architectural Decisions: Answer with Confidence

When asked to evaluate tradeoffs (bracket notation vs MCP, tool calls vs inline, pointing accuracy), give a direct answer backed by the reasoning you've traced. Do not hedge with "it depends" or "both are valid" when the user asks directly — if they ask "are you 100% sure?" they want certainty, not a reframe. Make a clear technical claim based on evidence, and if you've researched it, own the recommendation.

## Efficiency Constraints: Respect Them

When the user says "short and sweet," "keep it brief," or specifies a scope ("don't touch the rest"), follow that boundary exactly. Do not expand into a "better" implementation or add unasked generalization. Surgical means surgical — the constraint is a feature, not a failure mode to work around.

## Implementation Notes

- **Keychain vs local secrets**: Check `$HOME/.local/config/clippy-secrets.json` first (if it exists and is committed), then fall back to keychain lookups via `security find-generic-password`. Don't assume either path; test the real mechanism before claiming what works.
- **Animation states**: Verify against the character manifest in `Resources/Characters/Clippy/character.json` before returning a state string.
