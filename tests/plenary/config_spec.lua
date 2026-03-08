describe("config", function()
  local config

  before_each(function()
    package.loaded['todo-ai.config'] = nil
    config = require('todo-ai.config')
  end)

  it("has expected defaults", function()
    config.setup({})
    assert.equals('right', config.get('pi_position'))
    assert.equals(80, config.get('pi_width'))
    assert.is_nil(config.get('pi_provider'))
    assert.is_nil(config.get('pi_model'))
  end)

  it("merges user config over defaults", function()
    config.setup({ pi_provider = 'anthropic', pi_model = 'sonnet', pi_width = 120 })
    assert.equals('anthropic', config.get('pi_provider'))
    assert.equals('sonnet', config.get('pi_model'))
    assert.equals(120, config.get('pi_width'))
    assert.equals('right', config.get('pi_position'))
  end)

  it("has ai_highlight defaults", function()
    config.setup({})
    local hl = config.get('ai_highlight')
    assert.is_true(hl.enabled)
    assert.equals('#ff79c6', hl.fg)
    assert.equals('#1a1a2e', hl.bg)
    assert.is_true(hl.bold)
  end)

  it("allows overriding ai_highlight partially", function()
    config.setup({ ai_highlight = { fg = '#00ff00' } })
    local hl = config.get('ai_highlight')
    assert.equals('#00ff00', hl.fg)
    assert.equals('#1a1a2e', hl.bg)  -- default preserved
  end)
end)
