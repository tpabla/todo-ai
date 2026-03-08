describe("config", function()
  local config

  before_each(function()
    package.loaded['todo-ai.config'] = nil
    config = require('todo-ai.config')
  end)

  it("has expected defaults", function()
    config.setup({})
    assert.equals(80, config.get('pi_width'))
    assert.equals('AGENT', config.get('tag'))
    assert.is_table(config.get('pi_extra_args'))
    assert.equals(0, #config.get('pi_extra_args'))
  end)

  it("merges user config over defaults", function()
    config.setup({ pi_width = 120, tag = 'CUSTOM' })
    assert.equals(120, config.get('pi_width'))
    assert.equals('CUSTOM', config.get('tag'))
  end)

  it("preserves defaults for unset keys", function()
    config.setup({ pi_width = 100 })
    assert.equals(100, config.get('pi_width'))
    assert.equals('AGENT', config.get('tag'))
    assert.is_table(config.get('pi_extra_args'))
  end)
end)
