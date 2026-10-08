# Executed Session Lease Cases

- capture rejects signed-out state; leases are provider-owned and disposed
- capture rejects while an account transition is in progress
- capture rejects while storage hydration blocks account data
- same-account profile update and refresh keep an existing lease current
- legacy lease stays current when refresh fills the user ID
- lease rejects a different known user ID in provider state
- same-id same-token login invalidates lease even when cleanup fails
- dispose during login identity cleanup prevents the final prefs pass
- all five account APIs reject a stale lease before sending a request
- account A lease rejects avatar upload after provider switches to B
- response arriving after dispose cannot write auth preferences
- successful password change clears session and still completes
- dispose during logout cleanup callback prevents prefs and route cleanup
- old logout preflight cannot log out same-token reauthenticated session
- lease from a newly authenticated session survives same-account mutation
