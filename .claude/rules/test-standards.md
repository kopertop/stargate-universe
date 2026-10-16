---
paths:
  - "tests/**"
---

# Test Standards

- Test naming: `test_[system]_[scenario]_[expected_result]` pattern
- Every test must have a clear arrange/act/assert structure
- Unit tests must not depend on external state (filesystem, network, database)
- Integration tests must clean up after themselves
- Performance tests must specify acceptable thresholds and fail if exceeded
- Test data must be defined in the test or in dedicated fixtures, never shared mutable state
- Mock external dependencies — tests should be fast and deterministic
- Every bug fix must have a regression test that would have caught the original bug

## Examples

**Correct** (proper naming + Arrange/Act/Assert):

```javascript
function testHealthSystemTakeDamageReducesHealth() {
    // Arrange
    const health = new HealthComponent();
    health.maxHealth = 100;
    health.currentHealth = 100;

    // Act
    health.takeDamage(25);

    // Assert
    assert.strictEqual(health.currentHealth, 75);
}
```

**Incorrect**:

```javascript
function test1() {  // VIOLATION: no descriptive name
    const h = new HealthComponent();
    h.takeDamage(25);                      // VIOLATION: no arrange step
    assert.ok(h.currentHealth < 100);      // VIOLATION: imprecise assertion
}
```
