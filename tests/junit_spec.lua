local junit = require('neotest-scala.junit')
local H = require('tests.helpers')

describe('junit', function()
  describe('collect_results', function()
    after_each(function()
      H.restore_mocks()
    end)

    it('parses single failing test with failure element', function()
      local xml = [[<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="test" tests="1" failures="1" errors="0">
  <testcase name="testFail" classname="com.example.FunSuite">
    <failure message="expected true but was false" type="AssertionError">
      org.scalatest.exceptions.TestFailedException: expected true but was false
        at com.example.FunSuite.$anonfun$testFail$1(FunSuite.scala:10)
    </failure>
  </testcase>
</testsuite>
]]
      H.mock_fn('neotest.lib.files', 'read', function()
        return xml
      end)

      local ns = {
        report_path = '/fake/path.xml',
        namespace = 'MySpec',
      }
      local results = junit.collect_results(ns)

      assert.are.same(1, #results)
      assert.are.same('testFail', results[1].name)
      assert.are.same('MySpec', results[1].namespace)
      assert.are.same('expected true but was false', results[1].error_message)
      assert.are.same('AssertionError', results[1].error_type)
      assert.is_truthy(results[1].error_stacktrace:find('TestFailedException'))
    end)

    it('parses single error test with error element', function()
      local xml = [[<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="test" tests="1" failures="0" errors="1">
  <testcase name="testError" classname="com.example.FunSuite">
    <error message="NullPointerException occurred" type="java.lang.NullPointerException">
      java.lang.NullPointerException
        at com.example.FunSuite.$anonfun$testError$1(FunSuite.scala:15)
    </error>
  </testcase>
</testsuite>
]]
      H.mock_fn('neotest.lib.files', 'read', function()
        return xml
      end)

      local ns = {
        report_path = '/fake/path.xml',
        namespace = 'ErrorSpec',
      }
      local results = junit.collect_results(ns)

      assert.are.same(1, #results)
      assert.are.same('testError', results[1].name)
      assert.are.same('ErrorSpec', results[1].namespace)
      assert.are.same('NullPointerException occurred', results[1].error_message)
      assert.are.same('java.lang.NullPointerException', results[1].error_type)
      assert.is_truthy(results[1].error_stacktrace:find('NullPointerException'))
    end)

    it('parses multiple failing tests', function()
      local xml = [[<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="test" tests="3" failures="2" errors="0">
  <testcase name="testFail1" classname="com.example.FunSuite">
    <failure message="first failure" type="AssertionError">
      first failure stacktrace
    </failure>
  </testcase>
  <testcase name="testFail2" classname="com.example.FunSuite">
    <failure message="second failure" type="AssertionError">
      second failure stacktrace
    </failure>
  </testcase>
</testsuite>
]]
      H.mock_fn('neotest.lib.files', 'read', function()
        return xml
      end)

      local ns = {
        report_path = '/fake/path.xml',
        namespace = 'MixedSpec',
      }
      local results = junit.collect_results(ns)

      assert.are.same(2, #results)

      assert.are.same('testFail1', results[1].name)
      assert.are.same('first failure', results[1].error_message)
      assert.are.same('AssertionError', results[1].error_type)

      assert.are.same('testFail2', results[2].name)
      assert.are.same('second failure', results[2].error_message)
      assert.are.same('AssertionError', results[2].error_type)
    end)

    it('unescapes XML entities in test names and messages', function()
      local xml = [[<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="test" tests="1" failures="1" errors="0">
  <testcase name="test with &quot;quotes&quot; and &apos;apostrophes&apos;" classname="com.example.FunSuite">
    <failure message="expected &lt;1&gt; but was &amp;2" type="AssertionError">
      Stacktrace with &lt;special&gt; &amp; chars
    </failure>
  </testcase>
</testsuite>
]]
      H.mock_fn('neotest.lib.files', 'read', function()
        return xml
      end)

      local ns = {
        report_path = '/fake/path.xml',
        namespace = 'EntitySpec',
      }
      local results = junit.collect_results(ns)

      assert.are.same(1, #results)
      assert.are.same('test with "quotes" and \'apostrophes\'', results[1].name)
      assert.are.same('expected <1> but was &2', results[1].error_message)
      assert.is_truthy(results[1].error_stacktrace:find('<special>'))
      assert.is_truthy(results[1].error_stacktrace:find('& chars'))
    end)

    it('removes ANSI escape sequences from stacktrace', function()
      local xml = [[<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="test" tests="1" failures="1" errors="0">
  <testcase name="testAnsi" classname="com.example.FunSuite">
    <failure message="failed with colors" type="AssertionError">
      [31morg.scalatest.exceptions.TestFailedException[0m: failed
        at [1mcom.example.FunSuite[0m.$anonfun$testAnsi$1(FunSuite.scala:20)
    </failure>
  </testcase>
</testsuite>
]]
      H.mock_fn('neotest.lib.files', 'read', function()
        return xml
      end)

      local ns = {
        report_path = '/fake/path.xml',
        namespace = 'AnsiSpec',
      }
      local results = junit.collect_results(ns)

      assert.are.same(1, #results)
      -- ANSI codes should be stripped
      assert.is_falsy(results[1].error_stacktrace:find('\27%['))
      assert.is_truthy(results[1].error_stacktrace:find('TestFailedException'))
      assert.is_truthy(results[1].error_stacktrace:find('FunSuite'))
    end)

    it('returns empty table when report file does not exist', function()
      H.mock_fn('neotest.lib.files', 'read', function()
        error('file not found')
      end)

      local ns = {
        report_path = '/nonexistent/path.xml',
        namespace = 'MissingSpec',
      }
      local results = junit.collect_results(ns)

      assert.are.same({}, results)
    end)

    it('handles test with failure but no message attribute', function()
      local xml = [[<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="test" tests="1" failures="1" errors="0">
  <testcase name="testNoMessage" classname="com.example.FunSuite">
    <failure type="AssertionError">
      Some stacktrace content here
    </failure>
  </testcase>
</testsuite>
]]
      H.mock_fn('neotest.lib.files', 'read', function()
        return xml
      end)

      local ns = {
        report_path = '/fake/path.xml',
        namespace = 'NoMsgSpec',
      }
      local results = junit.collect_results(ns)

      assert.are.same(1, #results)
      assert.are.same('testNoMessage', results[1].name)
      assert.are.same('AssertionError', results[1].error_type)
      -- error_message may be nil when no message attribute
      -- error_stacktrace should still have content
      assert.is_truthy(results[1].error_stacktrace:find('stacktrace'))
    end)

    it('handles test with error but no message attribute', function()
      local xml = [[<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="test" tests="1" failures="0" errors="1">
  <testcase name="testErrorNoMsg" classname="com.example.FunSuite">
    <error type="java.lang.RuntimeException">
      RuntimeException stacktrace
    </error>
  </testcase>
</testsuite>
]]
      H.mock_fn('neotest.lib.files', 'read', function()
        return xml
      end)

      local ns = {
        report_path = '/fake/path.xml',
        namespace = 'ErrorNoMsgSpec',
      }
      local results = junit.collect_results(ns)

      assert.are.same(1, #results)
      assert.are.same('testErrorNoMsg', results[1].name)
      assert.are.same('java.lang.RuntimeException', results[1].error_type)
      assert.is_truthy(results[1].error_stacktrace:find('RuntimeException'))
    end)
  end)
end)
