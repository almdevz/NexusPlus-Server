package protocol

const (
	Version          = 1
	ServerVersion    = "1.2.0"
	HeaderProtocol   = "X-Nexus-Protocol"
	ContentTypeJSON  = "application/json"
	ContentTypeBytes = "application/octet-stream"
)

type CreateSessionRequest struct {
	Protocol    string `json:"protocol"`
	Version     int    `json:"version"`
	TargetHost  string `json:"target_host"`
	TargetPort  int    `json:"target_port"`
	ClientNonce string `json:"client_nonce"`
}

type CreateSessionResponse struct {
	SessionID    string `json:"session_id"`
	SessionToken string `json:"session_token"`
	ExpiresIn    int    `json:"expires_in"`
}

type ErrorResponse struct {
	Error   string `json:"error"`
	Message string `json:"message,omitempty"`
}

type HealthResponse struct {
	Status          string `json:"status"`
	ProtocolVersion int    `json:"protocol_version"`
	ServerVersion   string `json:"server_version"`
	ActiveSessions  int    `json:"active_sessions"`
	PendingSessions int    `json:"pending_sessions"`
	MaxSessions     int    `json:"max_sessions"`
	UptimeSeconds   int64  `json:"uptime_seconds"`
}
