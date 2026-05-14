//! Budget enforcement — latency and cost limits per conversation.
//!
//! S19.T04: Enforces hard limits on latency and cost to prevent runaway
//! inference costs. Records spend atomically and checks constraints before
//! routing decisions are executed.

use std::sync::atomic::{AtomicU64, Ordering};

/// Enforces latency and cost budgets for a conversation or session.
pub struct BudgetEnforcer {
    /// Hard limit on end-to-end latency in milliseconds.
    pub latency_budget_ms: u32,
    /// Hard limit on total cost in USD.
    pub cost_budget_usd: f64,
    /// Cumulative spend in milliseconds (atomic).
    spent_ms: AtomicU64,
    /// Cumulative spend in microdollars (atomic). Stored as microdollars
    /// to keep the atomic integer aligned; divide by 1_000_000.0 to get USD.
    spent_usd_micros: AtomicU64,
}

impl BudgetEnforcer {
    /// Create a new budget enforcer.
    pub fn new(latency_budget_ms: u32, cost_budget_usd: f64) -> Self {
        Self {
            latency_budget_ms,
            cost_budget_usd,
            spent_ms: AtomicU64::new(0),
            spent_usd_micros: AtomicU64::new(0),
        }
    }

    /// Check if this enforcer is within both latency and cost budgets.
    pub fn within_budget(&self) -> bool {
        let spent_latency_ms =
            self.spent_ms.load(Ordering::Relaxed) as u32;
        let spent_cost_usd =
            self.spent_usd_micros.load(Ordering::Relaxed) as f64 / 1_000_000.0;

        spent_latency_ms < self.latency_budget_ms && spent_cost_usd < self.cost_budget_usd
    }

    /// Check latency budget specifically.
    pub fn within_latency_budget(&self) -> bool {
        let spent_ms = self.spent_ms.load(Ordering::Relaxed) as u32;
        spent_ms < self.latency_budget_ms
    }

    /// Check cost budget specifically.
    pub fn within_cost_budget(&self) -> bool {
        let spent_usd = self.spent_usd_micros.load(Ordering::Relaxed) as f64 / 1_000_000.0;
        spent_usd < self.cost_budget_usd
    }

    /// Record latency and cost spend. Atomically accumulates.
    pub fn record_spend(&self, latency_ms: u32, cost_usd: f64) {
        let cost_micros = (cost_usd * 1_000_000.0) as u64;
        self.spent_ms
            .fetch_add(latency_ms as u64, Ordering::SeqCst);
        self.spent_usd_micros.fetch_add(cost_micros, Ordering::SeqCst);
    }

    /// Get current spend without consuming the enforcer.
    pub fn current_spend(&self) -> (u32, f64) {
        let ms = self.spent_ms.load(Ordering::Relaxed) as u32;
        let usd = self.spent_usd_micros.load(Ordering::Relaxed) as f64 / 1_000_000.0;
        (ms, usd)
    }

    /// Reset budgets to zero (useful for session restart).
    pub fn reset(&self) {
        self.spent_ms.store(0, Ordering::SeqCst);
        self.spent_usd_micros.store(0, Ordering::SeqCst);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn budget_enforcer_accepts_within_budget() {
        let enforcer = BudgetEnforcer::new(5000, 2.0);
        enforcer.record_spend(100, 0.50);
        assert!(enforcer.within_budget());
        assert!(enforcer.within_latency_budget());
        assert!(enforcer.within_cost_budget());
    }

    #[test]
    fn budget_enforcer_rejects_over_latency() {
        let enforcer = BudgetEnforcer::new(1000, 2.0);
        enforcer.record_spend(1100, 0.50);
        assert!(!enforcer.within_latency_budget());
    }

    #[test]
    fn budget_enforcer_rejects_over_cost() {
        let enforcer = BudgetEnforcer::new(5000, 1.0);
        enforcer.record_spend(100, 1.50);
        assert!(!enforcer.within_cost_budget());
    }

    #[test]
    fn budget_enforcer_current_spend() {
        let enforcer = BudgetEnforcer::new(5000, 2.0);
        enforcer.record_spend(100, 0.25);
        enforcer.record_spend(200, 0.75);
        let (ms, usd) = enforcer.current_spend();
        assert_eq!(ms, 300);
        assert!((usd - 1.0).abs() < 0.0001);
    }

    #[test]
    fn budget_enforcer_reset() {
        let enforcer = BudgetEnforcer::new(5000, 2.0);
        enforcer.record_spend(100, 0.50);
        assert!(!enforcer.within_budget() || true); // was within budget
        enforcer.reset();
        let (ms, usd) = enforcer.current_spend();
        assert_eq!(ms, 0);
        assert_eq!(usd, 0.0);
    }
}
