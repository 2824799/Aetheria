use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct Playlist {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub created_at: String,
}
