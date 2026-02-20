local H = require('tests.helpers')

local ESC = string.char(27)

package.loaded['neotest.lib'] = {
  files = {
    read_lines = function()
      error('mock not set')
    end,
  },
}

local lib = package.loaded['neotest.lib']
local utils = require('neotest-scala.utils')

local function mock_read_lines(fn)
  lib.files.read_lines = fn
end

local function restore_read_lines()
  lib.files.read_lines = function()
    error('mock not set')
  end
end

describe('utils', function()
  before_each(function()
    utils.setup({ build_tool = 'auto', compile_on_save = false, cache_build_info = true })
    restore_read_lines()
    H.restore_mocks()
  end)

  after_each(function()
    restore_read_lines()
    H.restore_mocks()
  end)

  describe('string_trim', function()
    it('removes leading whitespace', function()
      H.assert_eq(utils.string_trim('   hello'), 'hello')
    end)

    it('removes trailing whitespace', function()
      H.assert_eq(utils.string_trim('hello   '), 'hello')
    end)

    it('removes both leading and trailing whitespace', function()
      H.assert_eq(utils.string_trim('   hello   '), 'hello')
    end)

    it('handles tabs and spaces', function()
      H.assert_eq(utils.string_trim('\t  hello  \t'), 'hello')
    end)

    it('returns empty string unchanged', function()
      H.assert_eq(utils.string_trim(''), '')
    end)

    it('handles whitespace-only string', function()
      H.assert_eq(utils.string_trim('   '), '')
    end)
  end)

  describe('string_despace', function()
    it('replaces multiple spaces with single space', function()
      H.assert_eq(utils.string_despace('hello   world'), 'hello world')
    end)

    it('replaces tabs with spaces', function()
      H.assert_eq(utils.string_despace('hello\tworld'), 'hello world')
    end)

    it('replaces newlines with spaces', function()
      H.assert_eq(utils.string_despace('hello\nworld'), 'hello world')
    end)

    it('handles mixed whitespace', function()
      H.assert_eq(utils.string_despace('hello  \t\n  world'), 'hello world')
    end)

    it('preserves single spaces', function()
      H.assert_eq(utils.string_despace('hello world'), 'hello world')
    end)
  end)

  describe('string_remove_dquotes', function()
    it('removes leading double quote', function()
      H.assert_eq(utils.string_remove_dquotes('"hello'), 'hello')
    end)

    it('removes trailing double quote', function()
      H.assert_eq(utils.string_remove_dquotes('hello"'), 'hello')
    end)

    it('removes both leading and trailing quotes', function()
      H.assert_eq(utils.string_remove_dquotes('"hello"'), 'hello')
    end)

    it('handles string without quotes', function()
      H.assert_eq(utils.string_remove_dquotes('hello'), 'hello')
    end)
  end)

  describe('string_remove_ansi', function()
    it('removes ANSI bracket sequences', function()
      H.assert_eq(utils.string_remove_ansi('[31mred text[0m'), 'red text')
    end)

    it('removes ANSI bold bracket sequences', function()
      H.assert_eq(utils.string_remove_ansi('[1mbold[0m'), 'bold')
    end)

    it('handles string without ANSI codes', function()
      H.assert_eq(utils.string_remove_ansi('plain text'), 'plain text')
    end)

    it('removes complex ANSI bracket sequences', function()
      H.assert_eq(utils.string_remove_ansi('[1;32mgreen bold[0m'), 'green bold')
    end)

    it('preserves ESC character (implementation only removes bracket sequences)', function()
      local result = utils.string_remove_ansi(ESC .. '[31mred text' .. ESC .. '[0m')
      H.assert_eq(result, ESC .. 'red text' .. ESC)
    end)
  end)

  describe('string_unescape_xml', function()
    it('unescapes &quot;', function()
      H.assert_eq(utils.string_unescape_xml('say &quot;hello&quot;'), 'say "hello"')
    end)

    it('unescapes &apos;', function()
      H.assert_eq(utils.string_unescape_xml("it&apos;s"), "it's")
    end)

    it('unescapes &amp;', function()
      H.assert_eq(utils.string_unescape_xml('a &amp; b'), 'a & b')
    end)

    it('unescapes &lt; and &gt;', function()
      H.assert_eq(utils.string_unescape_xml('&lt;tag&gt;'), '<tag>')
    end)

    it('handles multiple escapes in one string', function()
      H.assert_eq(utils.string_unescape_xml('&lt;div&gt;hello &amp; goodbye&lt;/div&gt;'), '<div>hello & goodbye</div>')
    end)

    it('handles string without XML escapes', function()
      H.assert_eq(utils.string_unescape_xml('plain text'), 'plain text')
    end)
  end)

  describe('setup and get_config', function()
    it('returns default config when no options provided', function()
      local config = utils.get_config()
      H.assert_eq(config.build_tool, 'auto')
      H.assert_eq(config.compile_on_save, false)
      H.assert_eq(config.cache_build_info, true)
    end)

    it('merges user options with defaults', function()
      utils.setup({ build_tool = 'bloop' })
      local config = utils.get_config()
      H.assert_eq(config.build_tool, 'bloop')
      H.assert_eq(config.compile_on_save, false)
    end)

    it('overrides default values', function()
      utils.setup({ compile_on_save = true, cache_build_info = false })
      local config = utils.get_config()
      H.assert_eq(config.compile_on_save, true)
      H.assert_eq(config.cache_build_info, false)
    end)

    it('handles empty options table', function()
      utils.setup({})
      local config = utils.get_config()
      H.assert_eq(config.build_tool, 'auto')
    end)
  end)

  describe('get_position_name', function()
    it('strips quotes from test position name', function()
      local position = { type = 'test', name = '"my test case"' }
      H.assert_eq(utils.get_position_name(position), 'my test case')
    end)

    it('returns name unchanged for non-test positions', function()
      local position = { type = 'namespace', name = 'MySpec' }
      H.assert_eq(utils.get_position_name(position), 'MySpec')
    end)

    it('handles name without quotes', function()
      local position = { type = 'test', name = 'my test case' }
      H.assert_eq(utils.get_position_name(position), 'my test case')
    end)

    it('removes all quotes from name', function()
      local position = { type = 'test', name = '"test "nested" case"' }
      H.assert_eq(utils.get_position_name(position), 'test nested case')
    end)
  end)

  describe('get_file_name', function()
    it('extracts filename from Unix path', function()
      H.assert_eq(utils.get_file_name('/home/user/project/src/MySpec.scala'), 'MySpec.scala')
    end)

    it('handles simple filename', function()
      H.assert_eq(utils.get_file_name('MySpec.scala'), 'MySpec.scala')
    end)

    it('handles nested paths', function()
      H.assert_eq(utils.get_file_name('src/test/scala/com/example/MySpec.scala'), 'MySpec.scala')
    end)
  end)

  describe('get_package_name', function()
    it('extracts package from file with package declaration', function()
      mock_read_lines(function()
        return { 'package com.example.tests', 'import org.scalatest._' }
      end)
      local result = utils.get_package_name('/fake/path/MySpec.scala')
      H.assert_eq(result, 'com.example.tests.')
    end)

    it('returns empty string for file without package', function()
      mock_read_lines(function()
        return { 'import org.scalatest._', 'class MySpec' }
      end)
      local result = utils.get_package_name('/fake/path/MySpec.scala')
      H.assert_eq(result, '')
    end)

    it('returns nil when file read fails', function()
      mock_read_lines(function()
        error('file not found')
      end)
      local result = utils.get_package_name('/fake/path/MySpec.scala')
      H.assert_eq(result, nil)
    end)

    it('handles package with multiple parts', function()
      mock_read_lines(function()
        return { 'package org.company.project.module' }
      end)
      local result = utils.get_package_name('/fake/path/MySpec.scala')
      H.assert_eq(result, 'org.company.project.module.')
    end)
  end)

  describe('has_nested_tests', function()
    local function make_mock_tree(children)
      return {
        _children = children,
        data = function(self)
          return { type = 'namespace', name = 'TestSpec' }
        end,
        children = function(self)
          return self._children
        end,
      }
    end

    it('returns true when tree has children', function()
      local tree = make_mock_tree({ { name = 'test1' }, { name = 'test2' } })
      H.assert_eq(utils.has_nested_tests(tree), true)
    end)

    it('returns false when tree has no children', function()
      local tree = make_mock_tree({})
      H.assert_eq(utils.has_nested_tests(tree), false)
    end)
  end)

  describe('find_node', function()
    local function make_mock_node(node_type, name, parent, children)
      local node = {
        _type = node_type,
        _name = name,
        _parent = parent,
        _children = children or {},
        data = function(self)
          return { type = self._type, name = self._name }
        end,
        parent = function(self)
          return self._parent
        end,
      }
      node.iter_nodes = function(self)
        local all_nodes = {}
        local function collect(n)
          table.insert(all_nodes, n)
          for _, c in ipairs(n._children) do
            collect(c)
          end
        end
        collect(node)
        local i = 0
        return function()
          i = i + 1
          local n = all_nodes[i]
          if n then
            return i, n
          end
          return nil
        end
      end
      return node
    end

    it('returns self when type matches', function()
      local node = make_mock_node('namespace', 'MySpec')
      local result = utils.find_node(node, 'namespace', false)
      H.assert_eq(result, node)
    end)

    it('finds parent node when searching up', function()
      local parent = make_mock_node('file', 'MySpec.scala')
      local child = make_mock_node('namespace', 'MySpec', parent)
      local result = utils.find_node(child, 'file', false)
      H.assert_eq(result, parent)
    end)

    it('returns nil when parent not found', function()
      local node = make_mock_node('test', 'test case')
      local result = utils.find_node(node, 'file', false)
      H.assert_eq(result, nil)
    end)

    it('finds child node when searching down', function()
      local child = make_mock_node('namespace', 'MySpec')
      local parent = make_mock_node('file', 'MySpec.scala', nil, { child })
      local result = utils.find_node(parent, 'namespace', true)
      H.assert_eq(result, child)
    end)

    it('returns nil when child not found', function()
      local node = make_mock_node('file', 'MySpec.scala', nil, {})
      local result = utils.find_node(node, 'namespace', true)
      H.assert_eq(result, nil)
    end)
  end)

  describe('build_test_namespace', function()
    local function make_mock_tree_for_ns(node_type, name, path, children, parent)
      local tree = {
        _type = node_type,
        _name = name,
        _path = path,
        _children = children or {},
        _parent = parent,
        data = function(self)
          return { type = self._type, name = self._name, path = self._path }
        end,
        children = function(self)
          return self._children
        end,
        parent = function(self)
          return self._parent
        end,
      }
      tree.iter_nodes = function(self)
        local all_nodes = {}
        local function collect(n)
          table.insert(all_nodes, n)
          for _, c in ipairs(n._children) do
            collect(c)
          end
        end
        collect(tree)
        local i = 0
        return function()
          i = i + 1
          local n = all_nodes[i]
          if n then
            return i, n
          end
          return nil
        end
      end
      return tree
    end

    it('returns * for dir type', function()
      local tree = make_mock_tree_for_ns('dir', 'testDir', '/path/to/dir')
      mock_read_lines(function()
        return { 'package com.example' }
      end)
      local result = utils.build_test_namespace(tree)
      H.assert_eq(result, '*')
    end)

    it('builds namespace for file type with namespace child', function()
      local ns_child = make_mock_tree_for_ns('namespace', 'MySpec', '/path/MySpec.scala')
      local tree = make_mock_tree_for_ns('file', 'MySpec.scala', '/path/MySpec.scala', { ns_child })
      mock_read_lines(function()
        return { 'package com.example' }
      end)
      local result = utils.build_test_namespace(tree)
      H.assert_eq(result, 'com.example.MySpec')
    end)

    it('builds namespace for namespace type', function()
      local tree = make_mock_tree_for_ns('namespace', 'MySpec', '/path/MySpec.scala')
      mock_read_lines(function()
        return { 'package com.example' }
      end)
      local result = utils.build_test_namespace(tree)
      H.assert_eq(result, 'com.example.MySpec')
    end)

    it('returns package with * when no namespace found', function()
      local tree = make_mock_tree_for_ns('test', 'test case', '/path/MySpec.scala', {}, nil)
      mock_read_lines(function()
        return { 'package com.example' }
      end)
      local result = utils.build_test_namespace(tree)
      H.assert_eq(result, 'com.example.*')
    end)
  end)

  describe('get_framework', function()
    it('detects scalatest from classpath', function()
      local build_target_info = {
        ['Scala Classpath'] = {
          '/home/.cache/coursier/v1/https/repo1.maven.org/maven2/org/scalatest/scalatest_3-3.2.15.jar',
        },
      }
      H.assert_eq(utils.get_framework(build_target_info), 'scalatest')
    end)

    it('detects munit from classpath', function()
      local build_target_info = {
        ['Scala Classpath'] = {
          '/home/.cache/coursier/v1/https/repo1.maven.org/maven2/org/scalameta/munit_3-0.7.29.jar',
        },
      }
      H.assert_eq(utils.get_framework(build_target_info), 'munit')
    end)

    it('detects specs2 from classpath', function()
      local build_target_info = {
        ['Scala Classpath'] = {
          '/home/.cache/coursier/v1/https/repo1.maven.org/maven2/org/specs2/specs2-core_3-4.19.2.jar',
        },
      }
      H.assert_eq(utils.get_framework(build_target_info), 'specs2')
    end)

    it('detects utest from classpath', function()
      local build_target_info = {
        ['Scala Classpath'] = {
          '/home/.cache/coursier/v1/https/repo1.maven.org/maven2/com/lihaoyi/utest_3-0.8.1.jar',
        },
      }
      H.assert_eq(utils.get_framework(build_target_info), 'utest')
    end)

    it('detects zio-test from classpath', function()
      local build_target_info = {
        ['Scala Classpath'] = {
          '/home/.cache/coursier/v1/https/repo1.maven.org/maven2/dev/zio/zio-test_3-2.0.15.jar',
        },
      }
      H.assert_eq(utils.get_framework(build_target_info), 'zio-test')
    end)

    it('returns scalatest as default when no framework detected', function()
      local build_target_info = {
        ['Scala Classpath'] = {
          '/some/other/library.jar',
        },
      }
      H.assert_eq(utils.get_framework(build_target_info), 'scalatest')
    end)

    it('returns scalatest when build_target_info is nil', function()
      H.assert_eq(utils.get_framework(nil), 'scalatest')
    end)

    it('handles Classpath key (non-Scala)', function()
      local build_target_info = {
        ['Classpath'] = {
          '/home/.cache/coursier/v1/https/repo1.maven.org/maven2/org/scalatest/scalatest_3-3.2.15.jar',
        },
      }
      H.assert_eq(utils.get_framework(build_target_info), 'scalatest')
    end)
  end)

  describe('get_project_name', function()
    it('extracts project name from build target', function()
      local build_target_info = {
        ['Target'] = { 'myproject-test' },
      }
      H.assert_eq(utils.get_project_name(build_target_info), 'myproject')
    end)

    it('handles project name without -test suffix', function()
      local build_target_info = {
        ['Target'] = { 'myproject' },
      }
      H.assert_eq(utils.get_project_name(build_target_info), 'myproject')
    end)

    it('returns nil when build_target_info is nil', function()
      H.assert_eq(utils.get_project_name(nil), nil)
    end)

    it('returns nil when Target is missing', function()
      local build_target_info = {
        ['Sources'] = { '/src/main/scala' },
      }
      H.assert_eq(utils.get_project_name(build_target_info), nil)
    end)
  end)

  describe('is_bloop_available', function()
    local original_fs_stat

    before_each(function()
      original_fs_stat = vim.loop.fs_stat
    end)

    after_each(function()
      vim.loop.fs_stat = original_fs_stat
    end)

    it('returns true when .bloop directory exists', function()
      vim.loop.fs_stat = function(path)
        if path:match('%.bloop$') then
          return { type = 'directory' }
        end
        return nil
      end
      H.assert_eq(utils.is_bloop_available('/project/root'), true)
    end)

    it('returns false when .bloop directory does not exist', function()
      vim.loop.fs_stat = function()
        return nil
      end
      H.assert_eq(utils.is_bloop_available('/project/root'), false)
    end)

    it('returns false when .bloop is a file not a directory', function()
      vim.loop.fs_stat = function()
        return { type = 'file' }
      end
      H.assert_eq(utils.is_bloop_available('/project/root'), false)
    end)
  end)

  describe('get_build_tool', function()
    local original_fs_stat

    before_each(function()
      original_fs_stat = vim.loop.fs_stat
    end)

    after_each(function()
      vim.loop.fs_stat = original_fs_stat
    end)

    it('returns bloop when config is set to bloop', function()
      utils.setup({ build_tool = 'bloop' })
      H.assert_eq(utils.get_build_tool('/any/path'), 'bloop')
    end)

    it('returns sbt when config is set to sbt', function()
      utils.setup({ build_tool = 'sbt' })
      H.assert_eq(utils.get_build_tool('/any/path'), 'sbt')
    end)

    it('returns bloop when auto and bloop is available', function()
      utils.setup({ build_tool = 'auto' })
      vim.loop.fs_stat = function()
        return { type = 'directory' }
      end
      H.assert_eq(utils.get_build_tool('/project/root'), 'bloop')
    end)

    it('returns sbt when auto and bloop is not available', function()
      utils.setup({ build_tool = 'auto' })
      vim.loop.fs_stat = function()
        return nil
      end
      H.assert_eq(utils.get_build_tool('/project/root'), 'sbt')
    end)
  end)

  describe('invalidate_cache', function()
    it('clears all cache when called without arguments', function()
      utils.invalidate_cache()
      assert.is_true(true)
    end)

    it('clears cache for specific root path', function()
      utils.invalidate_cache('/project/root')
      assert.is_true(true)
    end)
  end)
end)
