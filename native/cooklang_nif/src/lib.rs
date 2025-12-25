//! Cooklang NIF bindings for Elixir
//!
//! This crate provides Rustler-based NIF functions that wrap the cooklang-rs parser,
//! enabling Elixir applications to parse Cooklang recipes with full feature support.

use cooklang::error::SourceReport;
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
            let output = convert_recipe(&recipe, &report);
            let json = serde_json::to_string(&output)
                .map_err(|e| format!("JSON serialization error: {}", e))?;
            Ok(json)
        }
        Err(report) => {
            let error_msg = report
                .errors()
                .map(|e| e.message.to_string())
                .collect::<Vec<_>>()
                .join("\n");
            Err(error_msg)
        }
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
                .map_err(|e| format!("Scaling error: {}", e))?;

            let output = convert_recipe(&scaled_recipe, &report);
            let json = serde_json::to_string(&output)
                .map_err(|e| format!("JSON serialization error: {}", e))?;
            Ok(json)
        }
        Err(report) => {
            let error_msg = report
                .errors()
                .map(|e| e.message.to_string())
                .collect::<Vec<_>>()
                .join("\n");
            Err(error_msg)
        }
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

fn convert_recipe(recipe: &Recipe, report: &SourceReport) -> RecipeOutput {
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

    RecipeOutput {
        metadata,
        ingredients,
        cookware,
        timers,
        sections,
        warnings: warning_strings,
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
