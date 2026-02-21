.PHONY: test test-utils test-junit test-framework test-integration test-clean

NVIM_TEST := nvim --headless --clean -u tests/minimal_init.lua
PLENARY_OPTS := {minimal_init = 'tests/minimal_init.lua'}

# Run all tests
test:
	$(NVIM_TEST) -c "PlenaryBustedDirectory tests/ $(PLENARY_OPTS)"

# Run utility tests
test-utils:
	$(NVIM_TEST) -c "PlenaryBustedFile tests/utils_spec.lua $(PLENARY_OPTS)"

# Run JUnit test detection tests
test-junit:
	$(NVIM_TEST) -c "PlenaryBustedFile tests/junit_spec.lua $(PLENARY_OPTS)"

# Run framework-specific tests
test-framework:
	$(NVIM_TEST) -c "PlenaryBustedDirectory tests/framework/ $(PLENARY_OPTS)"

# Run integration tests
test-integration:
	$(NVIM_TEST) -c "PlenaryBustedDirectory tests/integration/ $(PLENARY_OPTS)"

# Clean up test artifacts
test-clean:
	rm -rf tests/.coverage
	rm -rf tests/*.log
