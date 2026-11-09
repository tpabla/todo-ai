describe("config", function()
  local config

  before_each(function()
    package.loaded['todo-ai.config'] = nil
    config = require('todo-ai.config')
  end)

  it("has expected defaults", function()
    config.setup({})
    assert.equals('AGENT', config.get('tag'))
    assert.equals('claude', config.get('agent'))
    assert.equals('right', config.get('split'))
    assert.is_true(vim.tbl_contains(config.get('agent_commands'), 'claude'))
    assert.equals(1000, config.get('reload_interval_ms'))
  end)

  it("merges user config over defaults", function()
    config.setup({ agent = 'pi', split = 'down', tag = 'CUSTOM' })
    assert.equals('pi', config.get('agent'))
    assert.equals('down', config.get('split'))
    assert.equals('CUSTOM', config.get('tag'))
  end)

  it("preserves defaults for unset keys", function()
    config.setup({ agent = 'pi' })
    assert.equals('right', config.get('split'))
    assert.equals('AGENT', config.get('tag'))
  end)
end)
