//! The OpenAPI contract, generated from the handler annotations and DTO types
//! (`GET /v1/openapi.json`). The Flutter DTOs follow this; it never follows
//! the UI.

use utoipa::OpenApi;

use crate::routes::*;

#[derive(OpenApi)]
#[openapi(
    info(title = "OctoNotes API", version = "1", description = "octonotes-api — see backend-rs/README.md"),
    paths(
        system::me,
        home::home,
        sessions::list, sessions::create, sessions::get, sessions::update, sessions::delete,
        courses::list, courses::create, courses::update, courses::delete,
        devices::list, devices::register,
        deck::destinations,
        blocks::list, blocks::ops, blocks::history, blocks::restore,
        ink::list_pages, ink::create_page, ink::update_page, ink::delete_page,
        ink::page_strokes, ink::session_strokes, ink::stroke_ops,
        recordings::start, recordings::update, recordings::put_chunk, recordings::manifest, recordings::complete,
        recordings::audio, recordings::list, recordings::add_marker, recordings::list_markers,
        transcript::list, transcript::correct, transcript::restore, transcript::toggle, transcript::from_source,
        live::session_devices, live::join, live::set_role, live::leave, live::finish,
        crate::pricing::list,
        ai::suggest, ai::apply, ai::dismiss, ai::command, ai::insert_run, ai::history, ai::pending_suggestions, ai::relevant, ai::summarize,
        materials::upload, materials::upload_url, materials::uploaded, materials::from_studio, materials::list, materials::pages,
        materials::page_image, materials::link, materials::set_active, materials::delete,
        research::run, research::apply, research::save, research::list,
        organize::preview, organize::apply, organize::undo, organize::dismiss,
        ink_ai::recognize, ink_ai::review,
        // PHASE-PATHS
    ),
    tags(
        (name = "sessions", description = "Lecture/note sessions"),
        (name = "blocks", description = "Typewriter blocks, block-level sync"),
        (name = "ink", description = "Magic Pencil pages and strokes"),
    )
)]
pub struct ApiDoc;

pub fn spec() -> utoipa::openapi::OpenApi {
    ApiDoc::openapi()
}
