//! Final-notes exports: Markdown, plain text, DOCX and PDF (Plus Jakarta Sans,
//! the app's single font). Input is the immutable `final_notes.content`.

use serde_json::Value;

const FONT_REGULAR: &[u8] = include_bytes!("../assets/fonts/PlusJakartaSans-Regular.ttf");
const FONT_BOLD: &[u8] = include_bytes!("../assets/fonts/PlusJakartaSans-Bold.ttf");

/// (type, text, indent) of each included block.
fn blocks(content: &Value) -> Vec<(String, String, usize)> {
    content["blocks"]
        .as_array()
        .cloned()
        .unwrap_or_default()
        .into_iter()
        .map(|b| (b["type"].as_str().unwrap_or("paragraph").to_string(), b["text"].as_str().unwrap_or("").to_string(), b["indent"].as_u64().unwrap_or(0) as usize))
        .collect()
}

fn label(kind: &str) -> Option<&'static str> {
    Some(match kind {
        "definition" => "Definition",
        "keyIdea" => "Key idea",
        "formula" => "Formula",
        "example" => "Example",
        "question" => "Question",
        "examHint" => "Exam hint",
        "warning" => "Warning",
        "assignment" => "Assignment",
        "summary" => "Summary",
        "transcriptExcerpt" => "From the lecture",
        "slideRef" => "From the slides",
        _ => return None,
    })
}

pub fn markdown(title: &str, content: &Value) -> String {
    let mut out = format!("# {title}\n\n");
    for (kind, text, indent) in blocks(content) {
        let pad = "  ".repeat(indent);
        let line = match kind.as_str() {
            "h1" => format!("## {text}"),
            "h2" => format!("### {text}"),
            "h3" => format!("#### {text}"),
            "bulleted" => format!("{pad}- {text}"),
            "numbered" => format!("{pad}1. {text}"),
            "checklist" => format!("{pad}- [ ] {text}"),
            "quote" | "transcriptExcerpt" => format!("> {text}"),
            "divider" => "---".into(),
            "formula" => format!("`{text}`"),
            k => match label(k) {
                Some(l) => format!("**{l}:** {text}"),
                None => format!("{pad}{text}"),
            },
        };
        out.push_str(&line);
        out.push_str("\n\n");
    }
    out
}

pub fn text(title: &str, content: &Value) -> String {
    let mut out = format!("{title}\n{}\n\n", "=".repeat(title.chars().count().min(80)));
    for (kind, text, indent) in blocks(content) {
        let prefix = match kind.as_str() {
            "bulleted" | "checklist" => "• ",
            "numbered" => "- ",
            _ => "",
        };
        let l = label(&kind).map(|l| format!("{l}: ")).unwrap_or_default();
        out.push_str(&format!("{}{prefix}{l}{text}\n\n", "  ".repeat(indent)));
    }
    out
}

pub fn docx(title: &str, content: &Value) -> Result<Vec<u8>, String> {
    use docx_rs::{Docx, Paragraph, Run};
    let mut doc = Docx::new().add_paragraph(Paragraph::new().add_run(Run::new().add_text(title).bold().size(40)));
    for (kind, text, indent) in blocks(content) {
        let p = match kind.as_str() {
            "h1" => Paragraph::new().add_run(Run::new().add_text(&text).bold().size(32)),
            "h2" => Paragraph::new().add_run(Run::new().add_text(&text).bold().size(28)),
            "h3" => Paragraph::new().add_run(Run::new().add_text(&text).bold().size(24)),
            "bulleted" | "numbered" | "checklist" => Paragraph::new().add_run(Run::new().add_text(format!("{}• {text}", "    ".repeat(indent)))),
            k => {
                let mut p = Paragraph::new();
                if let Some(l) = label(k) {
                    p = p.add_run(Run::new().add_text(format!("{l}: ")).bold());
                }
                p.add_run(Run::new().add_text(format!("{}{text}", "    ".repeat(indent))))
            }
        };
        doc = doc.add_paragraph(p);
    }
    let mut buf = std::io::Cursor::new(Vec::new());
    doc.build().pack(&mut buf).map_err(|e| e.to_string())?;
    Ok(buf.into_inner())
}

pub fn pdf(title: &str, content: &Value) -> Result<Vec<u8>, String> {
    use genpdf::elements::{Break, Paragraph};
    use genpdf::fonts::{FontData, FontFamily};
    use genpdf::style::Style;
    use genpdf::Element;

    let regular = FontData::new(FONT_REGULAR.to_vec(), None).map_err(|e| e.to_string())?;
    let bold = FontData::new(FONT_BOLD.to_vec(), None).map_err(|e| e.to_string())?;
    let family = FontFamily { regular: regular.clone(), bold: bold.clone(), italic: regular, bold_italic: bold };
    let mut doc = genpdf::Document::new(family);
    doc.set_title(title);
    let mut decorator = genpdf::SimplePageDecorator::new();
    decorator.set_margins(18);
    doc.set_page_decorator(decorator);
    doc.set_font_size(11);
    doc.set_line_spacing(1.35);

    doc.push(Paragraph::new(title).styled(Style::new().bold().with_font_size(22)));
    doc.push(Break::new(1.0));
    for (kind, text, indent) in blocks(content) {
        let pad = "    ".repeat(indent);
        let el = match kind.as_str() {
            "h1" => Paragraph::new(text).styled(Style::new().bold().with_font_size(17)),
            "h2" => Paragraph::new(text).styled(Style::new().bold().with_font_size(14)),
            "h3" => Paragraph::new(text).styled(Style::new().bold().with_font_size(12)),
            "bulleted" | "checklist" => Paragraph::new(format!("{pad}•  {text}")).styled(Style::new()),
            "numbered" => Paragraph::new(format!("{pad}–  {text}")).styled(Style::new()),
            "divider" => Paragraph::new("—").styled(Style::new()),
            k => match label(k) {
                Some(l) => {
                    let mut p = Paragraph::default();
                    p.push_styled(format!("{pad}{l}: "), Style::new().bold());
                    p.push(text);
                    p.styled(Style::new())
                }
                None => Paragraph::new(format!("{pad}{text}")).styled(Style::new()),
            },
        };
        doc.push(el);
        doc.push(Break::new(0.5));
    }
    let mut buf = Vec::new();
    doc.render(&mut buf).map_err(|e| e.to_string())?;
    Ok(buf)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn sample() -> Value {
        json!({ "blocks": [
            { "type": "h1", "text": "Glycolysis", "indent": 0 },
            { "type": "definition", "text": "Glycolysis — splitting glucose into two pyruvate", "indent": 0 },
            { "type": "bulleted", "text": "Net 2 ATP", "indent": 1 },
        ]})
    }

    #[test]
    fn all_formats_render() {
        let md = markdown("Cellular Respiration", &sample());
        assert!(md.contains("## Glycolysis") && md.contains("**Definition:**") && md.contains("  - Net 2 ATP"));
        assert!(text("T", &sample()).contains("• Net 2 ATP"));
        assert_eq!(&docx("T", &sample()).unwrap()[..2], b"PK");
        let pdf = pdf("Cellular Respiration", &sample()).unwrap();
        assert_eq!(&pdf[..5], b"%PDF-");
    }
}
