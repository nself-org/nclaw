use std::sync::Arc;
use std::sync::atomic::{AtomicU32, Ordering};
use tokio::sync::mpsc;
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;
use thiserror::Error;

#[derive(Error, Debug)]
pub enum CoreError {
    #[error("runtime initialization failed: {0}")]
    RuntimeInit(String),
    #[error("task spawn failed: {0}")]
    TaskSpawn(String),
    #[error("runtime not initialized")]
    NotInitialized,
}

enum SupervisorMsg {
    TaskSpawned { id: u32, handle: JoinHandle<()> },
    TaskPanicked { id: u32 },
}

/// Multi-threaded async runtime with task supervision.
pub struct CoreRuntime {
    handle: tokio::runtime::Handle,
    supervisor_tx: mpsc::Sender<SupervisorMsg>,
    cancel_token: CancellationToken,
    task_counter: Arc<AtomicU32>,
}

impl CoreRuntime {
    /// Start a new multi-thread tokio runtime with task supervision.
    pub fn start() -> Result<Self, CoreError> {
        let rt = tokio::runtime::Runtime::new()
            .map_err(|e| CoreError::RuntimeInit(e.to_string()))?;

        let handle = rt.handle().clone();
        let (supervisor_tx, supervisor_rx) = mpsc::channel(100);
        let cancel_token = CancellationToken::new();
        let task_counter = Arc::new(AtomicU32::new(0));

        let cancel_token_supervisor = cancel_token.clone();
        let task_counter_supervisor = task_counter.clone();

        // Spawn supervisor task
        rt.spawn(Self::supervisor_loop(supervisor_rx, cancel_token_supervisor, task_counter_supervisor));

        // Keep runtime alive in a background thread
        std::thread::spawn(move || {
            rt.block_on(async {
                std::future::pending::<()>().await;
            });
        });

        Ok(CoreRuntime {
            handle,
            supervisor_tx,
            cancel_token,
            task_counter,
        })
    }

    /// Spawn a monitored task with cancellation support.
    pub fn spawn_supervised<F>(&self, future: F) -> Result<(), CoreError>
    where
        F: std::future::Future<Output = ()> + Send + 'static,
    {
        let id = self.task_counter.fetch_add(1, Ordering::SeqCst);
        let supervisor_tx = self.supervisor_tx.clone();
        let cancel_token = self.cancel_token.clone();

        let wrapped = async move {
            tokio::select! {
                _ = cancel_token.cancelled() => {
                    log::debug!("task {} cancelled", id);
                }
                _ = future => {
                    log::debug!("task {} completed", id);
                }
            }
        };

        let handle = self.handle.spawn(wrapped);
        self.supervisor_tx.try_send(SupervisorMsg::TaskSpawned { id, handle })
            .map_err(|e| CoreError::TaskSpawn(e.to_string()))?;

        Ok(())
    }

    /// Gracefully shutdown the runtime with cooperative cancellation.
    pub async fn shutdown(&self) {
        log::info!("initiating graceful shutdown");
        self.cancel_token.cancel();
        tokio::time::sleep(std::time::Duration::from_secs(1)).await;
        log::info!("shutdown complete");
    }

    async fn supervisor_loop(
        mut rx: mpsc::Receiver<SupervisorMsg>,
        cancel_token: CancellationToken,
        _task_counter: Arc<AtomicU32>,
    ) {
        while let Some(msg) = rx.recv().await {
            match msg {
                SupervisorMsg::TaskSpawned { id, .. } => {
                    log::debug!("task {} spawned under supervision", id);
                }
                SupervisorMsg::TaskPanicked { id } => {
                    log::warn!("task {} panicked, would restart", id);
                }
            }

            if cancel_token.is_cancelled() {
                log::info!("supervisor loop exiting due to cancellation");
                break;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_runtime_start() {
        let rt = CoreRuntime::start().expect("runtime should start");
        rt.shutdown().await;
    }

    #[tokio::test]
    async fn test_spawn_supervised_task() {
        let rt = CoreRuntime::start().expect("runtime should start");

        let (tx, mut rx) = tokio::sync::mpsc::channel(1);
        let future = async move {
            tx.send(42).await.ok();
        };

        rt.spawn_supervised(future).expect("spawn should succeed");

        let val = tokio::time::timeout(
            std::time::Duration::from_secs(1),
            rx.recv()
        ).await.expect("timeout").expect("recv");

        assert_eq!(val, 42);
        rt.shutdown().await;
    }

    #[tokio::test]
    async fn test_shutdown_cancellation() {
        let rt = CoreRuntime::start().expect("runtime should start");

        let (tx, mut rx) = tokio::sync::mpsc::channel(1);

        let future = async move {
            loop {
                tx.send(()).await.ok();
                tokio::time::sleep(std::time::Duration::from_millis(100)).await;
            }
        };

        rt.spawn_supervised(future).expect("spawn should succeed");
        tokio::time::sleep(std::time::Duration::from_millis(150)).await;

        rt.shutdown().await;

        let result = tokio::time::timeout(
            std::time::Duration::from_millis(500),
            rx.recv()
        ).await;

        // After shutdown, task should stop receiving
        assert!(result.is_err() || result.ok().is_none());
    }
}
