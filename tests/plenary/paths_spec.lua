describe("paths", function()
  local paths

  before_each(function()
    package.loaded['todo-ai.paths'] = nil
    paths = require('todo-ai.paths')
  end)

  describe("is_ancestor", function()
    it("is true for a parent directory", function()
      assert.is_true(paths.is_ancestor('/a/b', '/a/b/c'))
    end)

    it("is true for equal paths", function()
      assert.is_true(paths.is_ancestor('/a/b', '/a/b'))
    end)

    it("is false across a component boundary", function()
      -- /a/bc is not inside /a/b even though the string is a prefix
      assert.is_false(paths.is_ancestor('/a/b', '/a/bc'))
    end)

    it("is false when the arguments are reversed", function()
      assert.is_false(paths.is_ancestor('/a/b/c', '/a/b'))
    end)
  end)

  describe("distance", function()
    it("counts components between ancestor and descendant", function()
      assert.equals(0, paths.distance('/a/b', '/a/b'))
      assert.equals(2, paths.distance('/a/b', '/a/b/c/d'))
    end)

    it("is nil for unrelated paths", function()
      assert.is_nil(paths.distance('/a/b', '/x/y'))
    end)
  end)

  describe("abs", function()
    it("resolves against the given base, not the cwd", function()
      -- The whole point: nvim's cwd must never be the base.
      assert.equals('/proj/repo/src/foo.lua',
        paths.abs('src/foo.lua', '/proj/repo'))
      assert.are_not.equals(vim.fn.getcwd() .. '/src/foo.lua',
        paths.abs('src/foo.lua', '/proj/repo'))
    end)

    it("passes absolute paths through unchanged", function()
      assert.equals('/etc/hosts', paths.abs('/etc/hosts', '/proj/repo'))
    end)
  end)

  describe("real", function()
    it("matches ancestry across a symlinked path", function()
      -- Regression: tmux reports /var/... while nvim reports /private/var/...
      -- on darwin, so string comparison alone rules the pair unrelated.
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp .. '/actual/repo-b', 'p')
      vim.fn.system({ 'ln', '-s', tmp .. '/actual', tmp .. '/link' })
      assert.is_true(paths.is_ancestor(tmp .. '/link', tmp .. '/actual/repo-b'))
      assert.equals(1, paths.distance(tmp .. '/link', tmp .. '/actual/repo-b'))
      vim.fn.delete(tmp, 'rf')
    end)
  end)

  describe("normalize", function()
    it("strips trailing slashes and expands ~", function()
      assert.equals('/a/b', paths.normalize('/a/b/'))
      assert.equals(vim.fn.expand('~') .. '/x', paths.normalize('~/x'))
    end)
  end)
end)
