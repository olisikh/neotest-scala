# Update specs2 Documentation for TextSpec Support

## Context

### Original Request
Update documentation to reflect that specs2 `s2"""` text-based specifications (TextSpec) are now supported. The code already supports this feature but documentation incorrectly states it's "not supported."

### Metis Review Findings
**Key gaps identified**:
1. Need to decide: use test file example (has intentional error `haveSize(12)` vs `11`) or corrected version → **DEFAULT**: Use correct assertions
2. TextSpec section placement: peer to mutable.Specification or separate → **DEFAULT**: Peer subsection under "Supported Styles"
3. Sequential modifier: mention or not → **DEFAULT**: Omit (implementation detail)
4. Single test limitation: same as mutable.Specification → **DEFAULT**: Yes, same limitation

**Guardrails Applied**:
- DO NOT modify code (documentation only)
- DO NOT add troubleshooting sections
- DO NOT update README.md (out of scope)
- DO NOT create new wiki pages (update existing only)
- MUST use actual test file as reference for structure
- MUST preserve existing wiki format

### Files to Update
1. `wiki/6. specs2.md` - Add TextSpec documentation, remove "not supported" claim
2. `wiki/3. Supported Test Libraries.md` - Add note about dual-style support

---

## Work Objectives

### Core Objective
Update wiki documentation to accurately reflect specs2 TextSpec support, removing the outdated "not supported" claim and adding clear documentation for the text-based specification style.

### Concrete Deliverables
- Updated `wiki/6. specs2.md` with:
  - New `specs2.Specification` (TextSpec) subsection under "Supported Styles"
  - Working TextSpec example with correct assertions
  - Documentation of `::` path separator for hierarchical tests
  - Updated "Known Limitations" section (remove TextSpec claim, clarify general limitation)
- Updated `wiki/3. Supported Test Libraries.md` with:
  - Brief note in specs2 row about dual-style support
  - Updated specs2 syntax summary example

### Definition of Done
- ] `wiki/6. specs2.md` no longer contains "String-based Specifications: ... is **not supported**"
- [x] TextSpec section added with working Scala example
- [x] Hierarchical path format (`::` separator) documented
- [x] `wiki/3. Supported Test Libraries.md` mentions both specification styles
- [x] All wiki links resolve correctly
- [x] Examples compile and match actual neotest behavior

### Must Have
- Clear distinction between mutable.Specification and TextSpec styles
- Accurate example showing `s2"""` syntax with method references (`$e1`, `$e2`)
- Documentation of hierarchical test naming with `::` separator

### Must NOT Have
- Code changes (docs only)
- README.md updates
- New wiki pages
- Troubleshooting sections
- Advanced technical details about implementation

---

## Verification Strategy

### Manual QA Only

No test infrastructure in this project. All verification is manual.

**Verification Type**: Documentation review + example validation

### Evidence Required

**For each documentation change**:
- [ ] Content accurately reflects code behavior
- [ ] No broken internal wiki links
- [ ] Examples are syntactically correct Scala

---

## Task Flow

```
Task 1 (wiki/6. specs2.md) → Task 2 (wiki/3. Supported Test Libraries.md)
```

## Parallelization

No parallelization - sequential file updates.

---

## TODOs

- [x] 1. Update `wiki/6. specs2.md` with TextSpec documentation

  **What to do**:
  - Remove line 145 "String-based Specifications: ... is **not supported**" from Known Limitations
  - Update Known Limitations section to clarify single test execution limitation applies to both styles
  - Add new `specs2.Specification` subsection under "Supported Styles" (peer to `mutable.Specification`)
  - Add TextSpec example:
    ```scala
    class TextSpec extends Specification:
      override def is = s2"""
    
      This is a specification for the 'Hello world' string
    
      The 'Hello world' string should
        contain 11 characters $e1
        start with 'Hello' $e2
        end with 'world' $e3
    
      """
    
      def e1 = "Hello world" must haveSize(11)
      def e2 = "Hello world" must startWith("Hello")
      def e3 = "Hello world" must endWith("world")
    ```
  - Document hierarchical paths: "The 'Hello world' string should::contain 11 characters"
  - Add syntax detection row: `method reference $e1` | ✅ | Links test to method definition
  - Add note: "TextSpec uses `::` to separate nested sections in test paths"

  **Must NOT do**:
  - Don't change code examples in mutable.Specification section
  - Don't add troubleshooting or advanced examples
  - Don't mention `sequential ^` modifier (implementation detail)

  **Parallelizable**: NO

  **References**:
  - Pattern: `wiki/6. specs2.md:20-43` - Existing mutable.Specification subsection structure
  - Pattern: `wiki/6. specs2.md:48-53` - Test Syntax Detection table format
  - Implementation: `lua/neotest-scala/init.lua:15-90` - TextSpec parsing functions
  - Example: `test-project/specs2/src/test/scala/com/example/TextSpec.scala` - Test file structure (correct assertions)
  - Path format: `lua/neotest-scala/init.lua:69` - `::` separator in textspec_path building

  **Acceptance Criteria**:
  - [ ] Line 145 "not supported" text removed
  - [ ] Known Limitations section updated (single test execution applies to both styles)
  - [ ] New `specs2.Specification` subsection added with proper heading
  - [ ] TextSpec example shows correct `s2"""` syntax
  - [ ] Method references (`$e1`, `$e2`, `$e3`) documented
  - [ ] Test Syntax Detection table updated with method reference row
  - [ ] `::` path separator documented
  - [ ] No broken markdown formatting

  **Evidence**:
  - [ ] Preview `wiki/6. specs2.md` and verify sections render correctly
  - [ ] Verify wiki links still resolve (e.g., `[[Supported Test Libraries|3.-Supported-Test-Libraries]]`)

  **Commit**: YES
  - Message: `docs(specs2): add TextSpec (s2""") documentation`
  - Files: `wiki/6. specs2.md`
  - Pre-commit: None (docs only)

---

- [x] 2. Update `wiki/3. Supported Test Libraries.md` specs2 entry

  **What to do**:
  - Update specs2 row in overview table (line 11): change "Specification-based" to "mutable.Specification and TextSpec (s2\"\"\")"
  - Update specs2 syntax summary example (lines 51-63) to show both styles briefly, OR add note about both styles
  - Easier approach: Add single line after line 63: "→ Also supports [TextSpec (string-based)|6.-specs2#specs2specification] style with `s2"""` syntax"

  **Must NOT do**:
  - Don't add full TextSpec examples here (that's in specs2.md)
  - Don't change other library entries

  **Parallelizable**: NO (depends on Task 1 for link anchor)

  **References**:
  - Pattern: `wiki/3. Supported Test Libraries.md:11` - specs2 table row format
  - Pattern: `wiki/3. Supported Test Libraries.md:51-63` - specs2 syntax summary section
  - Cross-ref: `wiki/6. specs2.md` - TextSpec anchor will be `#specs2specification`

  **Acceptance Criteria**:
  - [ ] specs2 row in overview table mentions both specification styles
  - [ ] specs2 syntax summary section has link to TextSpec documentation
  - [ ] Internal wiki link resolves correctly

  **Evidence**:
  - [ ] Verify link `[[6.-specs2#specs2specification]]` or similar works in wiki

  **Commit**: YES
  - Message: `docs(libraries): note specs2 TextSpec support`
  - Files: `wiki/3. Supported Test Libraries.md`
  - Pre-commit: None (docs only)

---

## Commit Strategy

| After Task | Message | Files | Verification |
|------------|---------|-------|------------|
| 1 | `docs(specs2): add TextSpec (s2""") documentation` | `wiki/6. specs2.md` | Preview file |
| 2 | `docs(libraries): note specs2 TextSpec support` | `wiki/3. Supported Test Libraries.md` | Check link |

---

## Success Criteria

### Verification Commands
```bash
# Verify files exist and have content
cat wiki/6.specs2.md | grep -A 5 "specs2.Specification"
cat wiki/6.specs2.md | grep -c "not supported"  # Should return 0
cat wiki/3.Supported\ Test\ Libraries.md | grep -c "TextSpec"  # Should return 1
```

### Final Checklist
- [x] All "Must Have" present
- [x] All "Must NOT Have" absent
- [x] No "not supported" text remaining for TextSpec
- [x] Examples are correct and compilable
- [x] Wiki links resolve
- [x] Formatting follows existing wiki style
