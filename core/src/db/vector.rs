//! Vector search trait for nClaw embeddings.
//!
//! Backed by `pgvector` on desktop (pglite/embedded-postgres) and `sqlite-vec` on mobile.
//! Concrete implementations land in T06b (sqlite-vec) and T05b (pgvector extension).

use async_trait::async_trait;
use uuid::Uuid;

use crate::error::CoreError;

/// A single nearest-neighbour hit from a vector search.
#[derive(Debug, Clone)]
pub struct VectorHit {
    /// UUID of the owning entity (message, memory, topic_summary, …).
    pub target_id: Uuid,
    /// Cosine similarity in `[0.0, 1.0]`. `1.0` means identical vectors.
    pub similarity: f32,
    /// Embedding model that produced this hit (e.g. `"text-embedding-3-small"`).
    pub model_id: String,
}

/// Vector-search capability, separated from the main [`NclawDb`](super::dal::NclawDb) trait
/// so it can be mock-swapped independently in tests.
///
/// Implementors MUST search only within the embedding index for the given `owner_kind` and
/// `model_id`. Cross-model comparisons are undefined (different dimensional spaces).
#[async_trait]
pub trait VectorSearch: Send + Sync {
    /// Return the `k` nearest embeddings by cosine similarity.
    ///
    /// # Parameters
    /// - `owner_kind`: filter by `target_kind` column (`"message"` | `"memory"` | `"topic_summary"`).
    /// - `query_embedding`: the query vector — must match the stored dimension.
    /// - `k`: number of results to return (capped by the engine's configured max).
    ///
    /// Results are ordered by `similarity` descending (most similar first).
    async fn vector_search(
        &self,
        owner_kind: &str,
        query_embedding: &[f32],
        k: u32,
    ) -> Result<Vec<VectorHit>, CoreError>;
}
