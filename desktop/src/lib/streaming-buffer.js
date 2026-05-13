/**
 * StreamingBuffer — manages token-by-token accumulation with pub/sub and abort control.
 * Clients subscribe to updates; the buffer notifies on each append.
 * Supports cancel() for stream abortion.
 */
export class StreamingBuffer {
    text = '';
    subscribers = new Set();
    done = false;
    cancelled = false;
    /**
     * Append a single token to the buffer.
     * If already done or cancelled, this is a no-op.
     */
    append(token) {
        if (this.cancelled || this.done)
            return;
        this.text += token;
        this.notifySubscribers();
    }
    /**
     * Mark the stream as complete (all tokens received).
     */
    finish() {
        this.done = true;
        this.notifySubscribers();
    }
    /**
     * Abort the stream (user cancelled). Prevents further appends.
     */
    cancel() {
        this.cancelled = true;
        this.done = true;
    }
    /**
     * Check if the stream has finished (either completed or cancelled).
     */
    isDone() {
        return this.done;
    }
    /**
     * Check if the stream was explicitly cancelled.
     */
    isCancelled() {
        return this.cancelled;
    }
    /**
     * Get the full accumulated text so far.
     */
    current() {
        return this.text;
    }
    /**
     * Subscribe to text updates. Returns an unsubscribe function.
     */
    subscribe(fn) {
        this.subscribers.add(fn);
        // Unsubscribe function
        return () => {
            this.subscribers.delete(fn);
        };
    }
    notifySubscribers() {
        this.subscribers.forEach((fn) => {
            try {
                fn(this.text);
            }
            catch (e) {
                console.error('StreamingBuffer subscriber error:', e);
            }
        });
    }
}
