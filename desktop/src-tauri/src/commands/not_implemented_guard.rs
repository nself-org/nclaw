/// Regression tests: every Tauri command that is not yet wired to nclaw-core
/// MUST return an Err whose JSON payload contains `"error": "NotImplemented"`.
///
/// When S15-T17, S17, or S18 land and a command is wired for real, its test
/// here is converted to assert the real return shape instead. No command may
/// return hardcoded success data while the core path is unimplemented.
#[cfg(test)]
mod tests {
    use super::super::{chat, local_ai, palette, settings, topics, vault};

    fn assert_not_implemented(result: Result<impl std::fmt::Debug, String>, awaiting: &str) {
        let err = result.expect_err("command must return Err while not yet implemented");
        let v: serde_json::Value =
            serde_json::from_str(&err).expect("Err payload must be valid JSON");
        assert_eq!(
            v.get("error").and_then(|e| e.as_str()),
            Some("NotImplemented"),
            "expected error=NotImplemented, got: {}",
            err
        );
        assert_eq!(
            v.get("awaiting").and_then(|a| a.as_str()),
            Some(awaiting),
            "expected awaiting={}, got: {}",
            awaiting,
            err
        );
    }

    // ── chat ──────────────────────────────────────────────────────────────────

    #[tokio::test]
    async fn stream_chat_returns_not_implemented() {
        let result = chat::stream_chat(vec![]).await;
        assert_not_implemented(result, "S15-T17");
    }

    // ── local_ai ──────────────────────────────────────────────────────────────

    #[tokio::test]
    async fn get_tier_returns_not_implemented() {
        let result = local_ai::get_tier().await;
        assert_not_implemented(result, "S15-T17");
    }

    #[tokio::test]
    async fn get_benchmark_history_returns_not_implemented() {
        let result = local_ai::get_benchmark_history(10).await;
        assert_not_implemented(result, "S15-T17");
    }

    #[tokio::test]
    async fn list_models_returns_not_implemented() {
        let result = local_ai::list_models().await;
        assert_not_implemented(result, "S15-T17");
    }

    #[tokio::test]
    async fn run_benchmark_returns_not_implemented() {
        let result = local_ai::run_benchmark().await;
        assert_not_implemented(result, "S15-T17");
    }

    #[tokio::test]
    async fn set_tier_override_returns_not_implemented() {
        let result = local_ai::set_tier_override(Some(2)).await;
        assert_not_implemented(result, "S15-T17");
    }

    #[tokio::test]
    async fn set_allow_t4_returns_not_implemented() {
        let result = local_ai::set_allow_t4(false).await;
        assert_not_implemented(result, "S15-T17");
    }

    #[tokio::test]
    async fn set_re_bench_monthly_returns_not_implemented() {
        let result = local_ai::set_re_bench_monthly(true).await;
        assert_not_implemented(result, "S15-T17");
    }

    #[tokio::test]
    async fn delete_model_returns_not_implemented() {
        let result = local_ai::delete_model("phi-3-mini".to_string()).await;
        assert_not_implemented(result, "S15-T17");
    }

    #[tokio::test]
    async fn set_model_role_returns_not_implemented() {
        let result = local_ai::set_model_role("phi-3-mini".to_string(), "chat".to_string()).await;
        assert_not_implemented(result, "S15-T17");
    }

    #[tokio::test]
    async fn get_upgrade_config_returns_not_implemented() {
        let result = local_ai::get_upgrade_config().await;
        assert_not_implemented(result, "S15-T17");
    }

    #[tokio::test]
    async fn upgrade_to_tier_returns_not_implemented() {
        let result = local_ai::upgrade_to_tier(2).await;
        assert_not_implemented(result, "S15-T17");
    }

    #[tokio::test]
    async fn set_upgrade_prompt_disabled_returns_not_implemented() {
        let result = local_ai::set_upgrade_prompt_disabled(true).await;
        assert_not_implemented(result, "S15-T17");
    }

    #[tokio::test]
    async fn defer_upgrade_prompt_30_days_returns_not_implemented() {
        let result = local_ai::defer_upgrade_prompt_30_days().await;
        assert_not_implemented(result, "S15-T17");
    }

    // ── settings ──────────────────────────────────────────────────────────────

    #[tokio::test]
    async fn get_setting_returns_not_implemented() {
        let result = settings::get_setting("provider".to_string()).await;
        assert_not_implemented(result, "S18-vault");
    }

    #[tokio::test]
    async fn get_all_settings_returns_not_implemented() {
        let result = settings::get_all_settings().await;
        assert_not_implemented(result, "S18-vault");
    }

    #[tokio::test]
    async fn set_setting_returns_not_implemented() {
        let result =
            settings::set_setting("model".to_string(), serde_json::json!({"chat": ""})).await;
        assert_not_implemented(result, "S18-vault");
    }

    #[tokio::test]
    async fn vault_repair_device_settings_returns_not_implemented() {
        let result = settings::vault_repair_device().await;
        assert_not_implemented(result, "S18-vault");
    }

    #[tokio::test]
    async fn test_sync_connection_returns_not_implemented() {
        let result =
            settings::test_sync_connection("https://example.com".to_string(), "key".to_string())
                .await;
        assert_not_implemented(result, "S17-sync");
    }

    #[tokio::test]
    async fn test_sync_connection_empty_url_returns_error() {
        // Empty URL is a validation error, not a NotImplemented — this is deliberate.
        let result = settings::test_sync_connection("".to_string(), "".to_string()).await;
        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), "server URL is required");
    }

    // ── topics ────────────────────────────────────────────────────────────────

    #[tokio::test]
    async fn list_topics_returns_not_implemented() {
        let result = topics::list_topics().await;
        assert_not_implemented(result, "S17-DB-topics");
    }

    #[tokio::test]
    async fn move_topic_returns_not_implemented() {
        let result = topics::move_topic("t-work".to_string(), "personal".to_string()).await;
        assert_not_implemented(result, "S17-DB-topics");
    }

    #[tokio::test]
    async fn search_returns_not_implemented() {
        let result = topics::search("work".to_string()).await;
        assert_not_implemented(result, "S17-search");
    }

    // ── palette ───────────────────────────────────────────────────────────────

    #[tokio::test]
    async fn palette_search_returns_not_implemented() {
        let result = palette::palette_search("work".to_string()).await;
        assert_not_implemented(result, "S17-search");
    }

    // ── vault ─────────────────────────────────────────────────────────────────

    #[tokio::test]
    async fn vault_status_returns_not_implemented() {
        let result = vault::vault_status().await;
        assert_not_implemented(result, "S18-vault");
    }

    #[tokio::test]
    async fn vault_repair_device_returns_not_implemented() {
        let result = vault::vault_repair_device().await;
        assert_not_implemented(result, "S18-vault");
    }

    #[tokio::test]
    async fn vault_revoke_device_returns_not_implemented() {
        let result = vault::vault_revoke_device("dev-abc".to_string()).await;
        assert_not_implemented(result, "S18-vault");
    }

    #[tokio::test]
    async fn vault_sync_now_returns_not_implemented() {
        let result = vault::vault_sync_now().await;
        assert_not_implemented(result, "S18-vault");
    }
}
