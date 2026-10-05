//! Cooklang NIF bindings for Elixir
//!
//! This crate provides Rustler-based NIF functions that wrap the cooklang-rs parser,
//! enabling Elixir applications to parse Cooklang recipes with full feature support.

use cooklang::error::{SourceDiag, SourceReport, Stage};
use cooklang::model::Recipe;
use cooklang::{Converter, CooklangParser, Extensions};
use serde::Serialize;
use std::collections::HashMap;

rustler::init!("Elixir.CooklangEx.Native");

// ============================================================================
// Serializable output types
// ============================================================================

#[derive(Serialize)]
struct RecipeOutput {
    metadata: HashMap<String, String>,
    ingredients: Vec<IngredientOutput>,
    cookware: Vec<CookwareOutput>,
    timers: Vec<TimerOutput>,
    sections: Vec<SectionOutput>,
    warnings: Vec<String>,
    diagnostics: Vec<DiagnosticOutput>,
}

#[derive(Serialize)]
struct IngredientOutput {
    name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    quantity: Option<QuantityOutput>,
    #[serde(skip_serializing_if = "Option::is_none")]
    note: Option<String>,
}

#[derive(Serialize)]
struct CookwareOutput {
    name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    quantity: Option<QuantityOutput>,
    #[serde(skip_serializing_if = "Option::is_none")]
    note: Option<String>,
}

#[derive(Serialize)]
struct TimerOutput {
    #[serde(skip_serializing_if = "Option::is_none")]
    name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    quantity: Option<QuantityOutput>,
}

#[derive(Serialize)]
struct QuantityOutput {
    #[serde(skip_serializing_if = "Option::is_none")]
    value: Option<ValueOutput>,
    #[serde(skip_serializing_if = "Option::is_none")]
    unit: Option<String>,
}

#[derive(Serialize)]
#[serde(untagged)]
enum ValueOutput {
    Number(f64),
    Text(String),
    Range { start: f64, end: f64 },
}

#[derive(Serialize)]
struct ParseErrorOutput {
    message: String,
    diagnostics: Vec<DiagnosticOutput>,
}

#[derive(Serialize)]
struct DiagnosticOutput {
    severity: &'static str,
    stage: &'static str,
    message: String,
    /// The lower-level error behind the diagnostic, if cooklang-rs has one.
    #[serde(skip_serializing_if = "Option::is_none")]
    cause: Option<String>,
    hints: Vec<String>,
    labels: Vec<LabelOutput>,
}

/// A labelled span of the source. `start` and `end` are byte offsets.
/// `line` and `column` are 1-based, and `column` counts characters.
#[derive(Serialize)]
struct LabelOutput {
    start: usize,
    end: usize,
    line: usize,
    column: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    message: Option<String>,
}

#[derive(Serialize)]
struct SectionOutput {
    #[serde(skip_serializing_if = "Option::is_none")]
    name: Option<String>,
    content: Vec<StepOutput>,
}

#[derive(Serialize)]
struct StepOutput {
    items: Vec<ItemOutput>,
}

#[derive(Serialize)]
#[serde(tag = "type")]
enum ItemOutput {
    #[serde(rename = "text")]
    Text { value: String },
    #[serde(rename = "ingredient")]
    Ingredient { index: usize },
    #[serde(rename = "cookware")]
    Cookware { index: usize },
    #[serde(rename = "timer")]
    Timer { index: usize },
}

// ============================================================================
// NIF Functions
// ============================================================================

/// Parse a Cooklang recipe string.
///
/// Returns `{:ok, json_string}` on success or `{:error, message}` on failure.
#[rustler::nif(schedule = "DirtyCpu")]
fn parse(input: &str, all_extensions: bool) -> Result<String, String> {
    let extensions = if all_extensions {
        Extensions::all()
    } else {
        Extensions::empty()
    };

    let parser = CooklangParser::new(extensions, Converter::default());

    match parser.parse(input).into_result() {
        Ok((recipe, report)) => {
            let output = convert_recipe(&recipe, &report, input);
            let json = serde_json::to_string(&output)
                .map_err(|e| message_error_json(format!("JSON serialization error: {}", e)))?;
            Ok(json)
        }
        Err(report) => Err(error_json(&report, input)),
    }
}

/// Parse and scale a Cooklang recipe to a target number of servings.
///
/// The recipe must have a `servings` metadata field.
/// Returns `{:ok, json_string}` on success or `{:error, message}` on failure.
#[rustler::nif(schedule = "DirtyCpu")]
fn parse_and_scale(
    input: &str,
    target_servings: u32,
    all_extensions: bool,
) -> Result<String, String> {
    let extensions = if all_extensions {
        Extensions::all()
    } else {
        Extensions::empty()
    };

    let parser = CooklangParser::new(extensions, Converter::default());

    match parser.parse(input).into_result() {
        Ok((recipe, report)) => {
            // Clone the recipe and scale it in place
            let mut scaled_recipe = recipe.clone();
            scaled_recipe
                .scale_to_servings(target_servings, parser.converter())
                .map_err(|e| message_error_json(format!("Scaling error: {}", e)))?;

            let output = convert_recipe(&scaled_recipe, &report, input);
            let json = serde_json::to_string(&output)
                .map_err(|e| message_error_json(format!("JSON serialization error: {}", e)))?;
            Ok(json)
        }
        Err(report) => Err(error_json(&report, input)),
    }
}

/// Parse a Cooklang aisle configuration file.
///
/// Returns `{:ok, json_string}` on success or `{:error, message}` on failure.
#[rustler::nif]
fn parse_aisle_config(input: &str) -> Result<String, String> {
    match cooklang::aisle::parse(input) {
        Ok(config) => {
            let json = serde_json::to_string(&config)
                .map_err(|e| format!("JSON serialization error: {}", e))?;
            Ok(json)
        }
        Err(e) => Err(e.to_string()),
    }
}

// ============================================================================
// Conversion helpers
// ============================================================================

/// JSON for the `{:error, json}` result of a failed parse.
///
/// `diagnostics` holds the whole report, errors and warnings, in report order.
/// `message` joins the error messages only.
fn error_json(report: &SourceReport, input: &str) -> String {
    let diagnostics: Vec<DiagnosticOutput> = report
        .iter()
        .map(|diag| convert_diagnostic(diag, input))
        .collect();

    let message = report
        .errors()
        .map(|diag| diag.message.to_string())
        .collect::<Vec<_>>()
        .join("\n");

    to_json(&ParseErrorOutput {
        message,
        diagnostics,
    })
}

/// JSON for an error that has no position in the source.
fn message_error_json(message: String) -> String {
    to_json(&ParseErrorOutput {
        message,
        diagnostics: vec![],
    })
}

fn to_json(error: &ParseErrorOutput) -> String {
    serde_json::to_string(error).unwrap_or_else(|e| {
        format!(
            r#"{{"message":"JSON serialization error: {}","diagnostics":[]}}"#,
            e.to_string().replace('"', "'")
        )
    })
}

fn convert_diagnostic(diag: &SourceDiag, input: &str) -> DiagnosticOutput {
    DiagnosticOutput {
        severity: if diag.is_error() { "error" } else { "warning" },
        stage: match diag.stage {
            Stage::Parse => "parse",
            Stage::Analysis => "analysis",
        },
        message: diag.message.to_string(),
        cause: std::error::Error::source(diag).map(|cause| cause.to_string()),
        hints: diag.hints.iter().map(|h| h.to_string()).collect(),
        labels: diag
            .labels
            .iter()
            .map(|(span, message)| {
                // cooklang-rs can point inside a multi-byte character, for
                // example one byte before the `(` of a timer note after `é`.
                // Move the offsets to character boundaries, so that slicing
                // the source with them gives valid text.
                let start = floor_char_boundary(input, span.start());
                let end = ceil_char_boundary(input, span.end()).max(start);
                let (line, column) = line_and_column(input, start);
                LabelOutput {
                    start,
                    end,
                    line,
                    column,
                    message: message.as_ref().map(|m| m.to_string()),
                }
            })
            .collect(),
    }
}

/// The largest character boundary of `input` at or before `offset`.
fn floor_char_boundary(input: &str, offset: usize) -> usize {
    let mut offset = offset.min(input.len());
    while !input.is_char_boundary(offset) {
        offset -= 1;
    }
    offset
}

/// The smallest character boundary of `input` at or after `offset`.
fn ceil_char_boundary(input: &str, offset: usize) -> usize {
    let mut offset = offset.min(input.len());
    while !input.is_char_boundary(offset) {
        offset += 1;
    }
    offset
}

/// 1-based line and character column of a byte offset in `input`.
/// `offset` must be a character boundary.
fn line_and_column(input: &str, offset: usize) -> (usize, usize) {
    let before = &input[..offset];
    let line = before.matches('\n').count() + 1;
    let line_start = before.rfind('\n').map_or(0, |i| i + 1);
    let column = before[line_start..].chars().count() + 1;
    (line, column)
}

fn convert_recipe(recipe: &Recipe, report: &SourceReport, input: &str) -> RecipeOutput {
    let metadata: HashMap<String, String> = recipe
        .metadata
        .map
        .iter()
        .map(|(k, v)| {
            let key = k.as_str().unwrap_or("").to_string();
            let value = v.as_str().unwrap_or("").to_string();
            (key, value)
        })
        .collect();

    let ingredients: Vec<IngredientOutput> = recipe
        .ingredients
        .iter()
        .map(|ing| IngredientOutput {
            name: ing.name.clone(),
            quantity: ing.quantity.as_ref().map(convert_quantity),
            note: ing.note.clone(),
        })
        .collect();

    let cookware: Vec<CookwareOutput> = recipe
        .cookware
        .iter()
        .map(|cw| CookwareOutput {
            name: cw.name.clone(),
            quantity: cw.quantity.as_ref().map(convert_quantity),
            note: cw.note.clone(),
        })
        .collect();

    let timers: Vec<TimerOutput> = recipe
        .timers
        .iter()
        .map(|t| TimerOutput {
            name: t.name.clone(),
            quantity: t.quantity.as_ref().map(convert_quantity),
        })
        .collect();

    let sections: Vec<SectionOutput> = recipe
        .sections
        .iter()
        .map(|section| SectionOutput {
            name: section.name.clone(),
            content: section
                .content
                .iter()
                .filter_map(|item| {
                    if let cooklang::Content::Step(step) = item {
                        Some(convert_step(&step))
                    } else {
                        None
                    }
                })
                .collect(),
        })
        .collect();

    let warning_strings: Vec<String> = report.warnings().map(|w| w.message.to_string()).collect();
    let diagnostics: Vec<DiagnosticOutput> = report
        .warnings()
        .map(|w| convert_diagnostic(w, input))
        .collect();

    RecipeOutput {
        metadata,
        ingredients,
        cookware,
        timers,
        sections,
        warnings: warning_strings,
        diagnostics,
    }
}

fn convert_quantity(q: &cooklang::Quantity) -> QuantityOutput {
    let value = match q.value() {
        cooklang::Value::Number(n) => Some(ValueOutput::Number(n.value())),
        cooklang::Value::Range { start, end } => Some(ValueOutput::Range {
            start: start.value(),
            end: end.value(),
        }),
        cooklang::Value::Text(t) => Some(ValueOutput::Text(t.clone())),
    };

    QuantityOutput {
        value,
        unit: q.unit().map(|s| s.to_string()),
    }
}

fn convert_step(step: &cooklang::Step) -> StepOutput {
    let items: Vec<ItemOutput> = step
        .items
        .iter()
        .map(|item| match item {
            cooklang::Item::Text { value } => ItemOutput::Text {
                value: value.to_string(),
            },
            cooklang::Item::Ingredient { index } => ItemOutput::Ingredient { index: *index },
            cooklang::Item::Cookware { index } => ItemOutput::Cookware { index: *index },
            cooklang::Item::Timer { index } => ItemOutput::Timer { index: *index },
            cooklang::Item::InlineQuantity { index: _ } => ItemOutput::Text {
                value: String::new(),
            },
        })
        .collect();

    StepOutput { items }
}
