use std::fs;
use std::path::Path;
use std::process::Command;

/// Compact project context for LLM prompts.
/// Port of context_compact.lua — detects tech stack, languages, directories, etc.

#[derive(Debug, Default)]
pub struct ProjectContext {
    pub lines: Vec<String>,
}

impl ProjectContext {
    pub fn to_string(&self) -> String {
        self.lines.join("\n")
    }
}

/// Generate a compact project context snapshot from the given root directory.
pub fn generate_compact(project_root: &str) -> ProjectContext {
    let root = Path::new(project_root);
    let mut ctx = ProjectContext::default();

    // Project basics
    let project_name = root
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "unknown".to_string());

    let branch = Command::new("git")
        .args(["branch", "--show-current"])
        .current_dir(root)
        .output()
        .ok()
        .and_then(|o| {
            if o.status.success() {
                Some(String::from_utf8_lossy(&o.stdout).trim().to_string())
            } else {
                None
            }
        })
        .unwrap_or_else(|| "none".to_string());

    ctx.lines.push(format!("Project: {project_name} | Branch: {branch}"));

    // Tech stack detection
    let stack_files: &[(&str, &str)] = &[
        ("package.json", "Node"),
        ("Cargo.toml", "Rust"),
        ("go.mod", "Go"),
        ("requirements.txt", "Python"),
        ("Gemfile", "Ruby"),
        ("pom.xml", "Java/Maven"),
        ("build.gradle", "Java/Gradle"),
        ("composer.json", "PHP"),
        ("mix.exs", "Elixir"),
    ];

    let stack: Vec<&str> = stack_files
        .iter()
        .filter(|(file, _)| root.join(file).exists())
        .map(|(_, tech)| *tech)
        .collect();

    // Language detection by file count
    let lang_exts: &[(&str, &str)] = &[
        ("lua", "*.lua"),
        ("python", "*.py"),
        ("javascript", "*.js"),
        ("typescript", "*.ts"),
        ("go", "*.go"),
        ("rust", "*.rs"),
    ];

    let langs: Vec<String> = lang_exts
        .iter()
        .filter_map(|(lang, pattern)| {
            let count = count_files_by_pattern(root, pattern);
            if count > 0 {
                Some(format!("{lang}:{count}"))
            } else {
                None
            }
        })
        .collect();

    if !stack.is_empty() || !langs.is_empty() {
        ctx.lines.push(format!(
            "Stack: {} | Files: {}",
            stack.join(","),
            langs.join(",")
        ));
    }

    // Key directories
    let check_dirs = [
        "src", "lib", "test", "tests", "spec", "docs", "api", "pkg", "cmd", "internal",
    ];
    let dirs: Vec<&str> = check_dirs
        .iter()
        .filter(|d| root.join(d).is_dir())
        .copied()
        .collect();
    if !dirs.is_empty() {
        ctx.lines.push(format!("Dirs: {}", dirs.join(", ")));
    }

    // Key config files
    let config_files = [
        "Makefile",
        "Dockerfile",
        "docker-compose.yml",
    ];
    let mut configs: Vec<String> = config_files
        .iter()
        .filter(|f| root.join(f).exists())
        .map(|f| f.to_string())
        .collect();

    // Check for .github/workflows
    let workflows_dir = root.join(".github/workflows");
    if workflows_dir.is_dir() {
        if let Ok(entries) = fs::read_dir(&workflows_dir) {
            for entry in entries.flatten() {
                if let Some(name) = entry.file_name().to_str() {
                    configs.push(name.to_string());
                }
            }
        }
    }

    if !configs.is_empty() {
        let display: Vec<&str> = configs.iter().take(5).map(|s| s.as_str()).collect();
        let suffix = if configs.len() > 5 { "..." } else { "" };
        ctx.lines
            .push(format!("Config: {}{suffix}", display.join(", ")));
    }

    // Testing framework detection
    let mut test_info = Vec::new();
    if has_files_matching(root, "*.test.js") || has_files_matching(root, "*.test.ts") {
        test_info.push("Jest/Mocha");
    }
    if has_files_matching(root, "test_*.py") {
        test_info.push("pytest");
    }
    if has_files_matching(root, "*_test.go") {
        test_info.push("go-test");
    }
    if has_files_matching(root, "*_spec.rb") {
        test_info.push("RSpec");
    }
    if !test_info.is_empty() {
        ctx.lines.push(format!("Tests: {}", test_info.join(",")));
    }

    // Package manager detection
    let pkg_mgr_files: &[(&str, &str)] = &[
        ("package-lock.json", "npm"),
        ("yarn.lock", "yarn"),
        ("pnpm-lock.yaml", "pnpm"),
        ("Pipfile.lock", "pipenv"),
        ("poetry.lock", "poetry"),
    ];
    let pkg_mgrs: Vec<&str> = pkg_mgr_files
        .iter()
        .filter(|(file, _)| root.join(file).exists())
        .map(|(_, mgr)| *mgr)
        .collect();
    if !pkg_mgrs.is_empty() {
        ctx.lines.push(format!("PkgMgr: {}", pkg_mgrs.join(",")));
    }

    // Recent changes
    if let Some(recent) = get_recent_changes(root) {
        ctx.lines.push(format!("Recent: {recent}"));
    }

    // Dependency summary
    if let Some(deps) = get_dependency_summary(root) {
        ctx.lines.push(format!("Deps: {deps}"));
    }

    ctx
}

/// Encode context for LLM transport — strip markdown formatting, limit size.
pub fn encode_for_llm(context: &str) -> String {
    let mut compressed = context.to_string();
    // Remove HTML comments
    while let Some(start) = compressed.find("<!--") {
        if let Some(end) = compressed[start..].find("-->") {
            compressed.replace_range(start..start + end + 3, "");
        } else {
            break;
        }
    }
    // Remove markdown formatting
    compressed = compressed.replace('#', "");
    compressed = compressed.replace('*', "");
    compressed = compressed.replace("```", "");

    // Collapse multiple newlines
    while compressed.contains("\n\n\n") {
        compressed = compressed.replace("\n\n\n", "\n\n");
    }

    compressed = compressed.trim().to_string();

    if compressed.len() > 2000 {
        compressed.truncate(2000);
        compressed.push_str("...");
    }

    compressed
}

// --- Helpers ---

fn count_files_by_pattern(root: &Path, pattern: &str) -> usize {
    let output = Command::new("find")
        .args([
            root.to_str().unwrap_or("."),
            "-name",
            pattern,
            "-type",
            "f",
            "-not",
            "-path",
            "*/node_modules/*",
            "-not",
            "-path",
            "*/.git/*",
            "-not",
            "-path",
            "*/target/*",
            "-not",
            "-path",
            "*/vendor/*",
        ])
        .output();

    match output {
        Ok(o) if o.status.success() => {
            String::from_utf8_lossy(&o.stdout)
                .lines()
                .filter(|l| !l.is_empty())
                .count()
        }
        _ => 0,
    }
}

fn has_files_matching(root: &Path, pattern: &str) -> bool {
    let output = Command::new("find")
        .args([
            root.to_str().unwrap_or("."),
            "-name",
            pattern,
            "-type",
            "f",
            "-not",
            "-path",
            "*/node_modules/*",
            "-not",
            "-path",
            "*/.git/*",
        ])
        .output();

    match output {
        Ok(o) if o.status.success() => {
            !String::from_utf8_lossy(&o.stdout).trim().is_empty()
        }
        _ => false,
    }
}

fn get_recent_changes(root: &Path) -> Option<String> {
    let output = Command::new("git")
        .args(["diff", "--name-only", "HEAD~1"])
        .current_dir(root)
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let files_str: String = stdout.lines().take(5).collect::<Vec<_>>().join(" ");

    if files_str.is_empty() {
        None
    } else {
        Some(files_str)
    }
}

fn get_dependency_summary(root: &Path) -> Option<String> {
    let mut deps = Vec::new();

    // Node dependencies
    let pkg_json = root.join("package.json");
    if pkg_json.exists() {
        if let Ok(content) = fs::read_to_string(&pkg_json) {
            if let Ok(pkg) = serde_json::from_str::<serde_json::Value>(&content) {
                if let Some(dep_obj) = pkg.get("dependencies").and_then(|d| d.as_object()) {
                    let count = dep_obj.len();
                    if count > 0 {
                        deps.push(format!("npm:{count}"));
                    }
                }
            }
        }
    }

    // Python requirements
    let requirements = root.join("requirements.txt");
    if requirements.exists() {
        if let Ok(content) = fs::read_to_string(&requirements) {
            let count = content
                .lines()
                .filter(|l| !l.is_empty() && !l.starts_with('#'))
                .count();
            if count > 0 {
                deps.push(format!("py:{count}"));
            }
        }
    }

    // Rust dependencies
    let cargo_toml = root.join("Cargo.toml");
    if cargo_toml.exists() {
        if let Ok(content) = fs::read_to_string(&cargo_toml) {
            // Simple count of lines under [dependencies]
            let mut in_deps = false;
            let mut count = 0;
            for line in content.lines() {
                if line.starts_with("[dependencies]") {
                    in_deps = true;
                    continue;
                }
                if in_deps {
                    if line.starts_with('[') {
                        break;
                    }
                    if !line.trim().is_empty() {
                        count += 1;
                    }
                }
            }
            if count > 0 {
                deps.push(format!("cargo:{count}"));
            }
        }
    }

    if deps.is_empty() {
        None
    } else {
        Some(deps.join(","))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn test_generate_compact_basic() {
        let dir = std::env::temp_dir().join("todo-ai-ctx-test");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();

        // Create some files
        fs::write(dir.join("Cargo.toml"), "[package]\nname = \"test\"").unwrap();
        fs::create_dir_all(dir.join("src")).unwrap();
        fs::write(dir.join("src/main.rs"), "fn main() {}").unwrap();

        let ctx = generate_compact(dir.to_str().unwrap());
        let output = ctx.to_string();

        assert!(output.contains("Project:"));
        assert!(output.contains("Rust"));
        assert!(output.contains("Dirs: src"));

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_encode_for_llm_strips_markdown() {
        let input = "# Header\n\n```code```\n\n**bold**\n\n<!-- comment -->\n\ntext";
        let encoded = encode_for_llm(input);
        assert!(!encoded.contains('#'));
        assert!(!encoded.contains("```"));
        assert!(!encoded.contains("**"));
        assert!(!encoded.contains("<!--"));
        assert!(encoded.contains("text"));
    }

    #[test]
    fn test_encode_for_llm_truncates() {
        let long_input = "a".repeat(3000);
        let encoded = encode_for_llm(&long_input);
        assert!(encoded.len() <= 2003 + 3); // 2000 + "..."
        assert!(encoded.ends_with("..."));
    }

    #[test]
    fn test_get_dependency_summary_node() {
        let dir = std::env::temp_dir().join("todo-ai-deps-test");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();

        fs::write(
            dir.join("package.json"),
            r#"{"dependencies": {"express": "^4.0", "lodash": "^4.0"}}"#,
        )
        .unwrap();

        let summary = get_dependency_summary(&dir);
        assert!(summary.is_some());
        assert!(summary.unwrap().contains("npm:2"));

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_get_dependency_summary_python() {
        let dir = std::env::temp_dir().join("todo-ai-pydeps-test");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();

        fs::write(dir.join("requirements.txt"), "flask\nrequests\n# comment\n").unwrap();

        let summary = get_dependency_summary(&dir);
        assert!(summary.is_some());
        assert!(summary.unwrap().contains("py:2"));

        let _ = fs::remove_dir_all(&dir);
    }
}
