package server

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"path"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/nexusconnect/nexus-xhttp/internal/protocol"
)

type Config struct {
	ListenHost              string   `json:"listen_host"`
	ListenPort              int      `json:"listen_port"`
	TLSCert                 string   `json:"tls_cert"`
	TLSKey                  string   `json:"tls_key"`
	BasePath                string   `json:"base_path"`
	AllowedTargets          []string `json:"allowed_targets"`
	FixedTarget             string   `json:"fixed_target,omitempty"`
	SessionExpiresSeconds   int      `json:"session_expires_seconds"`
	IdleTimeoutSeconds      int      `json:"idle_timeout_seconds"`
	BackendConnectTimeoutMS int      `json:"backend_connect_timeout_ms"`
	MaxSessions             int      `json:"max_sessions"`
	MaxSessionsPerIP        int      `json:"max_sessions_per_ip"`
	MaxSessionJSONBytes     int64    `json:"max_session_json_bytes"`
	MaxPostBytes            int64    `json:"max_post_bytes"`
	EnableLegacyV2          bool     `json:"enable_legacy_v2"`
}

func (c *Config) normalize() error {
	if c.ListenHost == "" {
		c.ListenHost = "0.0.0.0"
	}
	if c.ListenPort == 0 {
		c.ListenPort = 8443
	}
	if c.ListenPort < 1 || c.ListenPort > 65535 {
		return fmt.Errorf("invalid listen_port")
	}
	if c.BasePath == "" {
		c.BasePath = "/nexus-xhttp/v3"
	}
	c.BasePath = "/" + strings.Trim(c.BasePath, "/")
	if c.SessionExpiresSeconds <= 0 {
		c.SessionExpiresSeconds = 300
	}
	if c.IdleTimeoutSeconds <= 0 {
		c.IdleTimeoutSeconds = 120
	}
	if c.BackendConnectTimeoutMS <= 0 {
		c.BackendConnectTimeoutMS = 15000
	}
	if c.MaxSessions <= 0 {
		c.MaxSessions = 1000
	}
	if c.MaxSessionsPerIP <= 0 {
		c.MaxSessionsPerIP = 20
	}
	if c.MaxSessionJSONBytes <= 0 {
		c.MaxSessionJSONBytes = 65536
	}
	if c.MaxPostBytes <= 0 {
		c.MaxPostBytes = 1024 * 1024
	}
	if c.FixedTarget == "" {
		if len(c.AllowedTargets) == 0 {
			c.FixedTarget = "127.0.0.1:22"
		} else {
			c.FixedTarget = c.AllowedTargets[0]
		}
	}
	if err := validateTarget(c.FixedTarget); err != nil {
		return fmt.Errorf("invalid fixed_target: %w", err)
	}
	for _, t := range c.AllowedTargets {
		if err := validateTarget(t); err != nil {
			return fmt.Errorf("invalid allowed target %q", t)
		}
	}
	return nil
}

func validateTarget(t string) error {
	h, p, err := net.SplitHostPort(t)
	if err != nil || h == "" {
		return errors.New("host:port required")
	}
	pi, err := strconv.Atoi(p)
	if err != nil || pi < 1 || pi > 65535 {
		return errors.New("invalid port")
	}
	return nil
}

type session struct {
	id, token, remoteIP, target    string
	version                        int
	conn                           net.Conn
	created                        time.Time
	lastUnix                       atomic.Int64
	downloadSet, uploadSet, closed atomic.Bool
	closeOnce                      sync.Once
	postMu                         sync.Mutex
	nextSeq                        uint64
}

func (s *session) touch()                  { s.lastUnix.Store(time.Now().UnixNano()) }
func (s *session) lastActivity() time.Time { return time.Unix(0, s.lastUnix.Load()) }
func (s *session) close()                  { s.closeOnce.Do(func() { s.closed.Store(true); _ = s.conn.Close() }) }

type Server struct {
	cfg      Config
	mu       sync.RWMutex
	sessions map[string]*session
	perIP    map[string]int
	logger   *log.Logger
}

func New(cfg Config, logger *log.Logger) (*Server, error) {
	if err := cfg.normalize(); err != nil {
		return nil, err
	}
	if logger == nil {
		logger = log.Default()
	}
	s := &Server{cfg: cfg, sessions: map[string]*session{}, perIP: map[string]int{}, logger: logger}
	go s.reaper()
	return s, nil
}
func (s *Server) Addr() string {
	return net.JoinHostPort(s.cfg.ListenHost, strconv.Itoa(s.cfg.ListenPort))
}
func (s *Server) TLSFiles() (string, string) { return s.cfg.TLSCert, s.cfg.TLSKey }
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc(s.cfg.BasePath+"/healthz", s.handleHealth)
	mux.HandleFunc(s.cfg.BasePath+"/session", s.handleCreate)
	mux.HandleFunc(s.cfg.BasePath+"/session/", s.handleLegacySession)
	mux.HandleFunc(s.cfg.BasePath+"/", s.handleV3)
	return s.headers(mux)
}
func (s *Server) headers(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		next.ServeHTTP(w, r)
	})
}
func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(405)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"ok": true, "protocol": "nexus-ssh-xhttp", "versions": []int{1, 3}})
}
func remoteIP(r *http.Request) string {
	h, _, e := net.SplitHostPort(r.RemoteAddr)
	if e != nil {
		return r.RemoteAddr
	}
	return h
}
func (s *Server) targetFor(req protocol.CreateSessionRequest) (string, bool) {
	if req.Version == protocol.VersionV3 {
		return s.cfg.FixedTarget, true
	}
	t := net.JoinHostPort(req.TargetHost, strconv.Itoa(req.TargetPort))
	for _, v := range s.cfg.AllowedTargets {
		if strings.EqualFold(v, t) {
			return t, true
		}
	}
	if strings.EqualFold(t, s.cfg.FixedTarget) {
		return t, true
	}
	return "", false
}
func (s *Server) handleCreate(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeError(w, 405, "method_not_allowed", "")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, s.cfg.MaxSessionJSONBytes)
	var req protocol.CreateSessionRequest
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(&req); err != nil {
		s.writeError(w, 400, "invalid_json", "")
		return
	}
	if req.Protocol != "nexus-ssh-xhttp" || (req.Version != protocol.VersionV2 && req.Version != protocol.VersionV3) {
		s.writeError(w, 426, "unsupported_protocol", "")
		return
	}
	if req.Version == protocol.VersionV2 && !s.cfg.EnableLegacyV2 {
		s.writeError(w, 426, "legacy_v2_disabled", "")
		return
	}
	if b, err := base64.RawURLEncoding.DecodeString(req.ClientNonce); err != nil || len(b) < 16 {
		s.writeError(w, 400, "invalid_nonce", "")
		return
	}
	target, ok := s.targetFor(req)
	if !ok {
		s.writeError(w, 403, "target_not_allowed", "")
		return
	}
	ip := remoteIP(r)
	s.mu.Lock()
	limited := len(s.sessions) >= s.cfg.MaxSessions || s.perIP[ip] >= s.cfg.MaxSessionsPerIP
	s.mu.Unlock()
	if limited {
		s.writeError(w, 429, "session_limit", "")
		return
	}
	d := net.Dialer{Timeout: time.Duration(s.cfg.BackendConnectTimeoutMS) * time.Millisecond}
	conn, err := d.DialContext(r.Context(), "tcp", target)
	if err != nil {
		s.writeError(w, 502, "ssh_unavailable", "")
		return
	}
	id, _ := random(32)
	tok, _ := random(32)
	x := &session{id: id, token: tok, remoteIP: ip, target: target, version: req.Version, conn: conn, created: time.Now()}
	x.touch()
	s.mu.Lock()
	s.sessions[id] = x
	s.perIP[ip]++
	s.mu.Unlock()
	mode := "sequential-post"
	if req.Version == 1 {
		mode = "chunked-upload"
	}
	w.Header().Set("Content-Type", protocol.ContentTypeJSON)
	w.Header().Set(protocol.HeaderProtocol, strconv.Itoa(req.Version))
	w.WriteHeader(201)
	_ = json.NewEncoder(w).Encode(protocol.CreateSessionResponse{SessionID: id, SessionToken: tok, ExpiresIn: s.cfg.SessionExpiresSeconds, Version: req.Version, UploadMode: mode})
}
func (s *Server) handleV3(w http.ResponseWriter, r *http.Request) {
	rel := strings.Trim(strings.TrimPrefix(r.URL.Path, s.cfg.BasePath+"/"), "/")
	parts := strings.Split(rel, "/")
	if len(parts) < 1 || parts[0] == "" {
		s.writeError(w, 404, "not_found", "")
		return
	}
	x := s.get(parts[0])
	if x == nil || x.version != 3 {
		s.writeError(w, 404, "unknown_session", "")
		return
	}
	if !bearerOK(r.Header.Get("Authorization"), x.token) {
		s.writeError(w, 401, "invalid_session_token", "")
		return
	}
	if len(parts) == 1 {
		switch r.Method {
		case http.MethodGet:
			s.download(w, r, x)
		case http.MethodDelete:
			s.removeAndClose(x.id)
			w.WriteHeader(204)
		default:
			s.writeError(w, 405, "method_not_allowed", "")
		}
		return
	}
	if len(parts) == 2 && r.Method == http.MethodPost {
		seq, err := strconv.ParseUint(parts[1], 10, 64)
		if err != nil {
			s.writeError(w, 400, "invalid_sequence", "")
			return
		}
		s.sequentialUpload(w, r, x, seq)
		return
	}
	s.writeError(w, 404, "not_found", "")
}
func (s *Server) sequentialUpload(w http.ResponseWriter, r *http.Request, x *session, seq uint64) {
	if r.ContentLength > s.cfg.MaxPostBytes {
		s.writeError(w, 413, "post_too_large", "")
		return
	}
	x.postMu.Lock()
	defer x.postMu.Unlock()
	if seq != x.nextSeq {
		s.writeError(w, 409, "out_of_order", fmt.Sprintf("expected %d", x.nextSeq))
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, s.cfg.MaxPostBytes)
	if _, err := io.Copy(activityWriter{w: x.conn, s: x}, activityReader{r: r.Body, s: x}); err != nil {
		s.writeError(w, 502, "backend_write_failed", "")
		return
	}
	x.nextSeq++
	w.Header().Set(protocol.HeaderProtocol, "3")
	w.WriteHeader(204)
}
func (s *Server) handleLegacySession(w http.ResponseWriter, r *http.Request) {
	if !s.cfg.EnableLegacyV2 {
		s.writeError(w, 404, "not_found", "")
		return
	}
	rel := strings.TrimPrefix(r.URL.Path, s.cfg.BasePath+"/session/")
	parts := strings.Split(strings.Trim(path.Clean("/"+rel), "/"), "/")
	if len(parts) < 1 || parts[0] == "" {
		s.writeError(w, 404, "unknown_session", "")
		return
	}
	x := s.get(parts[0])
	if x == nil || x.version != 1 {
		s.writeError(w, 404, "unknown_session", "")
		return
	}
	if !bearerOK(r.Header.Get("Authorization"), x.token) {
		s.writeError(w, 401, "invalid_session_token", "")
		return
	}
	if len(parts) == 1 && r.Method == http.MethodDelete {
		s.removeAndClose(x.id)
		w.WriteHeader(204)
		return
	}
	if len(parts) != 2 {
		s.writeError(w, 404, "not_found", "")
		return
	}
	switch parts[1] {
	case "download":
		s.download(w, r, x)
	case "upload":
		s.legacyUpload(w, r, x)
	default:
		s.writeError(w, 404, "not_found", "")
	}
}
func (s *Server) download(w http.ResponseWriter, r *http.Request, x *session) {
	if r.Method != http.MethodGet {
		s.writeError(w, 405, "method_not_allowed", "")
		return
	}
	if !x.downloadSet.CompareAndSwap(false, true) {
		s.writeError(w, 409, "download_exists", "")
		return
	}
	w.Header().Set("Content-Type", protocol.ContentTypeBytes)
	w.Header().Set(protocol.HeaderProtocol, strconv.Itoa(x.version))
	w.WriteHeader(200)
	if f, ok := w.(http.Flusher); ok {
		f.Flush()
	}
	_, err := io.Copy(activityWriter{w: w, s: x}, activityReader{r: x.conn, s: x})
	if err != nil && !x.closed.Load() {
		s.logger.Printf("download session=%s ended: %v", short(x.id), err)
	}
}
func (s *Server) legacyUpload(w http.ResponseWriter, r *http.Request, x *session) {
	if r.Method != http.MethodPost {
		s.writeError(w, 405, "method_not_allowed", "")
		return
	}
	if !x.downloadSet.Load() {
		s.writeError(w, 409, "download_not_ready", "")
		return
	}
	if !x.uploadSet.CompareAndSwap(false, true) {
		s.writeError(w, 409, "upload_exists", "")
		return
	}
	_, err := io.Copy(activityWriter{w: x.conn, s: x}, activityReader{r: r.Body, s: x})
	if tcp, ok := x.conn.(*net.TCPConn); ok {
		_ = tcp.CloseWrite()
	}
	if err != nil && !x.closed.Load() {
		s.logger.Printf("upload session=%s ended: %v", short(x.id), err)
	}
	w.WriteHeader(204)
}
func bearerOK(h, token string) bool {
	const p = "Bearer "
	if !strings.HasPrefix(h, p) {
		return false
	}
	got := strings.TrimSpace(strings.TrimPrefix(h, p))
	return len(got) == len(token) && subtle.ConstantTimeCompare([]byte(got), []byte(token)) == 1
}
func (s *Server) get(id string) *session { s.mu.RLock(); defer s.mu.RUnlock(); return s.sessions[id] }
func (s *Server) removeAndClose(id string) {
	s.mu.Lock()
	x := s.sessions[id]
	if x != nil {
		delete(s.sessions, id)
		s.perIP[x.remoteIP]--
		if s.perIP[x.remoteIP] <= 0 {
			delete(s.perIP, x.remoteIP)
		}
	}
	s.mu.Unlock()
	if x != nil {
		x.close()
	}
}
func (s *Server) reaper() {
	t := time.NewTicker(time.Second)
	defer t.Stop()
	for range t.C {
		now := time.Now()
		var ids []string
		s.mu.RLock()
		for id, x := range s.sessions {
			if now.Sub(x.created) > time.Duration(s.cfg.SessionExpiresSeconds)*time.Second || now.Sub(x.lastActivity()) > time.Duration(s.cfg.IdleTimeoutSeconds)*time.Second {
				ids = append(ids, id)
			}
		}
		s.mu.RUnlock()
		for _, id := range ids {
			s.removeAndClose(id)
		}
	}
}
func (s *Server) writeError(w http.ResponseWriter, status int, code, msg string) {
	w.Header().Set("Content-Type", protocol.ContentTypeJSON)
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(protocol.ErrorResponse{Error: code, Message: msg})
}
func random(n int) (string, error) {
	b := make([]byte, n)
	if _, e := rand.Read(b); e != nil {
		return "", e
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}
func short(v string) string {
	if len(v) > 8 {
		return v[:8]
	}
	return v
}

type activityReader struct {
	r io.Reader
	s *session
}

func (a activityReader) Read(p []byte) (int, error) {
	n, e := a.r.Read(p)
	if n > 0 {
		a.s.touch()
	}
	return n, e
}

type activityWriter struct {
	w io.Writer
	s *session
}

func (a activityWriter) Write(p []byte) (int, error) {
	n, e := a.w.Write(p)
	if n > 0 {
		a.s.touch()
	}
	return n, e
}
