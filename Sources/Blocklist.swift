/// Content-blocking rules (WebKit content rule list) for analytics and logging requests.
/// They don't affect what you see; they cut background network and CPU work.
enum Blocklist {
    static let rules = #"""
[
  { "trigger": { "url-filter": "logging_client_events" }, "action": { "type": "block" } },
  { "trigger": { "url-filter": "/logging/falco" },        "action": { "type": "block" } },
  { "trigger": { "url-filter": "/ajax/bz" },              "action": { "type": "block" } },
  { "trigger": { "url-filter": "/ajax/logging/" },        "action": { "type": "block" } },
  { "trigger": { "url-filter": "/api/v1/web/logging/" },  "action": { "type": "block" } },
  { "trigger": { "url-filter": "facebook\\.com/tr" },     "action": { "type": "block" } },
  { "trigger": { "url-filter": "connect\\.facebook\\.net" }, "action": { "type": "block" } }
]
"""#
}
