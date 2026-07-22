package protocol

const (
	VersionV2        = 1
	VersionV3        = 3
	HeaderProtocol   = "X-Nexus-Protocol"
	ContentTypeJSON  = "application/json"
	ContentTypeBytes = "application/octet-stream"
)

type CreateSessionRequest struct {
	Protocol    string `json:"protocol"`
	Version     int    `json:"version"`
	TargetHost  string `json:"target_host,omitempty"`
	TargetPort  int    `json:"target_port,omitempty"`
	ClientNonce string `json:"client_nonce"`
}

type CreateSessionResponse struct {
	SessionID    string `json:"session_id"`
	SessionToken string `json:"session_token"`
	ExpiresIn    int    `json:"expires_in"`
	Version      int    `json:"version"`
	UploadMode   string `json:"upload_mode"`
}

type ErrorResponse struct {
	Error   string `json:"error"`
	Message string `json:"message,omitempty"`
}
