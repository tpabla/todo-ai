describe("config", function()
  local config

  before_each(function()
    package.loaded['todo-ai.config'] = nil
    config = require('todo-ai.config')
  end)

  it("exposes harness constants", function()
    assert.equals('pi', config.HARNESS_PI)
    assert.equals('claude_code', config.HARNESS_CLAUDE_CODE)
  end)

  it("has expected defaults", function()
    config.setup({})
    assert.equals(config.HARNESS_CLAUDE_CODE, config.get('harness'))
    assert.equals(80, config.get('pane_width'))
    assert.equals('AGENT', config.get('tag'))
    assert.is_table(config.get('pi_extra_args'))
    assert.equals(0, #config.get('pi_extra_args'))
    assert.is_table(config.get('claude_extra_args'))
    assert.is_nil(config.get('claude_model'))
  end)

  it("merges user config over defaults", function()
    config.setup({ pane_width = 120, tag = 'CUSTOM', harness = 'pi' })
    assert.equals(120, config.get('pane_width'))
    assert.equals('CUSTOM', config.get('tag'))
    assert.equals('pi', config.get('harness'))
  end)

  it("preserves defaults for unset keys", function()
    config.setup({ pane_width = 100 })
    assert.equals(100, config.get('pane_width'))
    assert.equals('AGENT', config.get('tag'))
    assert.equals('claude_code', config.get('harness'))
  end)
end)
