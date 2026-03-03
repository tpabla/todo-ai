GOOD EXAMPLE (Large task - do subset first):
{
  "mode": "changes",
  "filename": "game_ui.py",
  "changes": [
    {
      "search": "def show_welcome(self):\n        \"\"\"Display welcome message.\"\"\"\n        print(\"\\n\" + \"=\"*50)",
      "replace": "@staticmethod\n    def show_welcome():\n        \"\"\"Display welcome message.\"\"\"\n        print(\"\\n\" + \"=\"*50)",
      "description": "Convert show_welcome method to static method"
    }
  ],
  "language": "python",
  "explanation": "Converted first method to static. Say 'continue' for the remaining methods."
}

GOOD EXAMPLE (Modifying existing file):
{
  "mode": "changes",
  "filename": "test.py",
  "changes": [
    {
      "search": "def get_margarita_ingredients():\n    return {'tequila': '2 oz', 'lime': '1 oz'}",
      "replace": "def get_negroni_ingredients():\n    return {'gin': '1 oz', 'campari': '1 oz', 'vermouth': '1 oz'}",
      "description": "Convert cocktail recipe from margarita to negroni"
    }
  ],
  "language": "python",
  "explanation": "Updated the cocktail recipe"
}

BAD EXAMPLE (Multiple files in one response - NEVER DO THIS):
{
  "mode": "changes",
  "filename": "multiple_files.py",
  "changes": [
    {
      "search": "",
      "replace": "content from file1 and file2 mixed together"
    }
  ]
}
^ WRONG! Never put multiple files in one response!
