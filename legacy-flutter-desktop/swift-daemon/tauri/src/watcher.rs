use notify::{Config, Event, RecommendedWatcher, RecursiveMode, Watcher};
use reqwest::Client;
use serde::Serialize;
use std::path::Path;
use std::sync::mpsc;
use std::thread;

#[derive(Serialize)]
struct ContextUpdate {
    event_kind: String,
    paths: Vec<String>,
}

/// Watches a directory for file changes and posts context updates
/// to the companion server endpoint.
pub struct FileWatcher {
    server_url: String,
    auth_token: String,
    _watcher: Option<RecommendedWatcher>,
}

impl FileWatcher {
    pub fn new(server_url: String, auth_token: String) -> Self {
        Self {
            server_url,
            auth_token,
            _watcher: None,
        }
    }

    /// Begin watching `directory` recursively for file system events.
    /// Each change is posted to `{server_url}/claw/companion/context`.
    pub fn watch(&mut self, directory: &str) -> Result<(), notify::Error> {
        let (tx, rx) = mpsc::channel::<Event>();

        let mut watcher = RecommendedWatcher::new(
            move |res: Result<Event, notify::Error>| {
                if let Ok(event) = res {
                    let _ = tx.send(event);
                }
            },
            Config::default(),
        )?;

        watcher.watch(Path::new(directory), RecursiveMode::Recursive)?;

        let url = format!(
            "{}/claw/companion/context",
            self.server_url.trim_end_matches('/')
        );
        let token = self.auth_token.clone();

        thread::spawn(move || {
            let client = Client::new();
            let rt = tokio::runtime::Runtime::new().expect("failed to create tokio runtime");

            for event in rx {
                let paths: Vec<String> = event
                    .paths
                    .iter()
                    .map(|p| p.to_string_lossy().to_string())
                    .collect();

                let update = ContextUpdate {
                    event_kind: format!("{:?}", event.kind),
                    paths,
                };

                let request = client
                    .post(&url)
                    .bearer_auth(&token)
                    .json(&update);

                if let Err(e) = rt.block_on(request.send()) {
                    eprintln!("Failed to send context update: {}", e);
                }
            }
        });

        self._watcher = Some(watcher);
        Ok(())
    }
}
