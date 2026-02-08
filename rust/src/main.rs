mod parser;
mod prompt;
mod protocol;
mod provider;
mod scanner;
mod search_replace;
mod validator;

use protocol::{Request, Response};
use std::io::{self, BufRead, Write};

fn main() {
    let stdin = io::stdin();
    let stdout = io::stdout();

    for line in stdin.lock().lines() {
        let line = match line {
            Ok(l) => l,
            Err(_) => break,
        };

        if line.trim().is_empty() {
            continue;
        }

        let request: Request = match serde_json::from_str(&line) {
            Ok(r) => r,
            Err(e) => {
                let error_response = Response::err(0, format!("Invalid request JSON: {}", e));
                let _ = write_response(&stdout, &error_response);
                continue;
            }
        };

        let response = handle_request(&request);
        let _ = write_response(&stdout, &response);
    }
}

fn write_response(stdout: &io::Stdout, response: &Response) -> io::Result<()> {
    let json = serde_json::to_string(response).unwrap_or_else(|e| {
        format!(
            r#"{{"id":{},"error":"Serialization error: {}"}}"#,
            response.id, e
        )
    });
    let mut handle = stdout.lock();
    writeln!(handle, "{}", json)?;
    handle.flush()
}

fn handle_request(request: &Request) -> Response {
    let id = request.id;

    match request.method.as_str() {
        // --- Search/Replace operations ---
        "apply_changes" => {
            match serde_json::from_value::<protocol::ApplyChangesParams>(request.params.clone()) {
                Ok(params) => {
                    let result =
                        search_replace::apply_changes(&params.lines, &params.changes);
                    Response::ok(id, serde_json::to_value(result).unwrap())
                }
                Err(e) => Response::err(id, format!("Invalid params: {}", e)),
            }
        }

        "calculate_position" => {
            match serde_json::from_value::<protocol::CalculatePositionParams>(
                request.params.clone(),
            ) {
                Ok(params) => {
                    match search_replace::calculate_position(&params.content, &params.search_text) {
                        Some(pos) => Response::ok(id, serde_json::to_value(pos).unwrap()),
                        None => Response::err(id, "Search text not found".to_string()),
                    }
                }
                Err(e) => Response::err(id, format!("Invalid params: {}", e)),
            }
        }

        "validate_changes" => {
            match serde_json::from_value::<protocol::ValidateChangesParams>(
                request.params.clone(),
            ) {
                Ok(params) => match search_replace::validate_changes(&params.changes) {
                    Ok(()) => {
                        Response::ok(id, serde_json::json!({"valid": true}))
                    }
                    Err(e) => Response::ok(
                        id,
                        serde_json::json!({"valid": false, "error": e}),
                    ),
                },
                Err(e) => Response::err(id, format!("Invalid params: {}", e)),
            }
        }

        "track_change_regions" => {
            match serde_json::from_value::<protocol::TrackRegionsParams>(request.params.clone()) {
                Ok(params) => {
                    let regions = search_replace::track_change_regions(
                        &params.lines,
                        &params.changes,
                        &params.rejected_indices,
                    );
                    Response::ok(id, serde_json::to_value(regions).unwrap())
                }
                Err(e) => Response::err(id, format!("Invalid params: {}", e)),
            }
        }

        // --- Parser operations ---
        "parse_response" => {
            match serde_json::from_value::<protocol::ParseParams>(request.params.clone()) {
                Ok(params) => {
                    let result =
                        parser::parse(&params.response, params.hint.as_deref());
                    Response::ok(id, serde_json::to_value(result).unwrap())
                }
                Err(e) => Response::err(id, format!("Invalid params: {}", e)),
            }
        }

        // --- Validator operations ---
        "validate_response" => {
            match serde_json::from_value::<protocol::ValidateResponseParams>(
                request.params.clone(),
            ) {
                Ok(params) => {
                    let result = validator::validate_response(&params.response);
                    Response::ok(id, serde_json::to_value(result).unwrap())
                }
                Err(e) => Response::err(id, format!("Invalid params: {}", e)),
            }
        }

        // --- Scanner operations ---
        "scan_todos" => {
            match serde_json::from_value::<protocol::ScanParams>(request.params.clone()) {
                Ok(params) => {
                    let todos = scanner::find_todos(
                        &params.lines,
                        params.comment_string.as_deref(),
                    );
                    Response::ok(id, serde_json::to_value(todos).unwrap())
                }
                Err(e) => Response::err(id, format!("Invalid params: {}", e)),
            }
        }

        "scan_project" => {
            match serde_json::from_value::<protocol::ScanProjectParams>(request.params.clone()) {
                Ok(params) => {
                    let files: Vec<(String, String)> = params
                        .files
                        .into_iter()
                        .map(|f| (f.path, f.content))
                        .collect();
                    let todos = scanner::scan_project(&files);
                    Response::ok(id, serde_json::to_value(todos).unwrap())
                }
                Err(e) => Response::err(id, format!("Invalid params: {}", e)),
            }
        }

        // --- Prompt operations ---
        "build_prompt" => {
            match serde_json::from_value::<protocol::BuildPromptParams>(request.params.clone()) {
                Ok(params) => {
                    let context = params.context.unwrap_or(serde_json::json!({}));
                    let result = prompt::build_complete_prompt(&params.instruction, &context);
                    Response::ok(id, serde_json::to_value(result).unwrap())
                }
                Err(e) => Response::err(id, format!("Invalid params: {}", e)),
            }
        }

        "get_schema" => {
            let schema = prompt::get_schema_description();
            Response::ok(id, serde_json::json!({"schema": schema}))
        }

        // --- Provider operations ---
        "send_to_provider" => {
            match serde_json::from_value::<protocol::ProviderRequestParams>(
                request.params.clone(),
            ) {
                Ok(params) => {
                    let result = provider::send_request(
                        &params.provider,
                        &params.instruction,
                        &params.context,
                        params.model.as_deref(),
                        params.temperature,
                        params.max_tokens,
                        params.api_key.as_deref(),
                        params.messages.as_deref(),
                    );

                    match result {
                        Ok(content) => {
                            // Parse the response
                            let parsed = parser::parse(&content, Some(&params.provider));
                            // Validate
                            let validation = validator::validate_response(&parsed);

                            Response::ok(
                                id,
                                serde_json::json!({
                                    "raw_content": content,
                                    "parsed": parsed,
                                    "validation": validation,
                                }),
                            )
                        }
                        Err(e) => Response::err(id, e),
                    }
                }
                Err(e) => Response::err(id, format!("Invalid params: {}", e)),
            }
        }

        // --- Utility ---
        "ping" => Response::ok(id, serde_json::json!({"status": "ok", "version": env!("CARGO_PKG_VERSION")})),

        _ => Response::err(id, format!("Unknown method: {}", request.method)),
    }
}
