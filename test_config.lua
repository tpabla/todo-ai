return {
    dir = vim.fn.expand("~/Projects/todo-ai"), -- Path to your local plugin
    name = "todo-ai",
    lazy = false,  -- Load immediately
    priority = 1000,  -- Load early
    build = "./install.sh",
    config = function()
        require('todo-ai').setup({
            provider = 'claude',
            -- model = 'hf.co/DavidAU/Llama-3.2-9B-Uncensored-Brainstorm-Alpha-GGUF:latest',
            -- model = 'qwen3:4b',
            -- endpoint = 'http://localhost:11434',

            -- Optional settings
            auto_open_chat = true,
            highlight_todos = true,
        })
    end,
    keys = {
        { "<leader>ts", ":TodoAIScan<CR>",   desc = "Scan for AI TODOs" },
        { "<leader>ta", ":TodoAIAccept<CR>", desc = "Accept AI changes" },
        { "<leader>tr", ":TodoAIReject<CR>", desc = "Reject AI changes" },
        { "<leader>tc", ":TodoAIChat<CR>",   desc = "Open AI chat" },
    }
}
