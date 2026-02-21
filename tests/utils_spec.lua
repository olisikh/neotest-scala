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
end)
