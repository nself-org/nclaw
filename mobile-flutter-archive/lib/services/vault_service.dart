/// VaultService wraps Rust core vault FFI.
///
/// Migrates from flutter_secure_storage to Rust core via OS keychain.
/// Stub: FFI calls wired on first `make codegen` run + S15.T18 mobile FFI integration.
class VaultService {
  /// Initialize vault with OS keychain backend.
  ///
  /// Calls Rust: nclaw_init_vault(namespace)
  Future<void> initialize({required String namespace}) async {
    // Stub: FFI call pending codegen
    // await api.initVault(namespace: namespace);
  }

  /// Store secret in OS keychain via Rust core.
  ///
  /// Calls Rust: nclaw_vault_set(key, secret)
  Future<void> set(String key, String secret) async {
    // Stub: FFI call pending codegen
    // await api.vaultSet(key: key, secret: secret);
  }

  /// Retrieve secret from OS keychain via Rust core.
  ///
  /// Calls Rust: nclaw_vault_get(key) → returns secret or null
  Future<String?> get(String key) async {
    // Stub: FFI call pending codegen
    // return await api.vaultGet(key: key);
    return null;
  }

  /// Delete secret from OS keychain.
  ///
  /// Calls Rust: nclaw_vault_delete(key)
  Future<void> delete(String key) async {
    // Stub: FFI call pending codegen
    // await api.vaultDelete(key: key);
  }

  /// Check if key exists in vault.
  Future<bool> contains(String key) async {
    // Stub: FFI call pending codegen
    // return await api.vaultContains(key: key);
    return false;
  }
}
