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
	PublicHost              string   `json:"public_host,omitempty"`
	TLSCert                 string   `json:"tls_cert"`
	TLSKey                  string   `json:"tls_key"`
	BasePath                string   `json:"base_path"`
	AllowedTargets          []string `json:"allowed_targets"`
	SessionExpiresSeconds   int      `json:"session_expires_seconds"`
	IdleTimeoutSeconds      int      `json:"idle_timeout_seconds"`
	BackendConnectTimeoutMS int      `json:"backend_connect_timeout_ms"`
	MaxSessions             int      `json:"max_sessions"`
	MaxSessionsPerIP        int      `json:"max_sessions_per_ip"`
	MaxSessionJSONBytes     int64    `json:"max_session_json_bytes"`
}

func ValidateConfig(in Config) (Config, error) {
	c := in
	if c.ListenHost == "" {
		c.ListenHost = "0.0.0.0"
	}
	if c.ListenPort == 0 {
		c.ListenPort = 8443
	}
	if c.ListenPort < 1 || c.ListenPort > 65535 {
		return c, fmt.Errorf("invalid listen_port")
	}
	if strings.ContainsAny(c.PublicHost, "\r\n/ ") {
		return c, fmt.Errorf("invalid public_host")
	}
	if c.BasePath == "" {
		c.BasePath = "/nexus-xhttp/v1"
	}
	c.BasePath = "/" + strings.Trim(c.BasePath, "/")
	if c.BasePath == "/" || strings.Contains(c.BasePath, "..") {
		return c, fmt.Errorf("invalid base_path")
	}
	if c.SessionExpiresSeconds <= 0 {
		c.SessionExpiresSeconds = 120
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
	if c.MaxSessionsPerIP > c.MaxSessions {
		return c, fmt.Errorf("max_sessions_per_ip exceeds max_sessions")
	}
	if c.MaxSessionJSONBytes <= 0 {
		c.MaxSessionJSONBytes = 65536
	}
	if c.MaxSessionJSONBytes > 1024*1024 {
		return c, fmt.Errorf("max_session_json_bytes too large")
	}
	if strings.TrimSpace(c.TLSCert) == "" || strings.TrimSpace(c.TLSKey) == "" {
		return c, errors.New("tls_cert and tls_key are required")
	}
	if len(c.AllowedTargets) == 0 {
		return c, errors.New("allowed_targets must not be empty")
	}
	seen := map[string]bool{}
	for _, t := range c.AllowedTargets {
		h, p, err := net.SplitHostPort(t)
		if err != nil || h == "" {
			return c, fmt.Errorf("invalid allowed target %q", t)
		}
		pi, err := strconv.Atoi(p)
		if err != nil || pi < 1 || pi > 65535 {
			return c, fmt.Errorf("invalid allowed target port %q", t)
		}
		n := net.JoinHostPort(strings.ToLower(h), strconv.Itoa(pi))
		if seen[n] {
			return c, fmt.Errorf("duplicate allowed target %q", t)
		}
		seen[n] = true
	}
	return c, nil
}

type session struct {
	id, token, remoteIP, target    string
	conn                           net.Conn
	created                        time.Time
	lastUnix                       atomic.Int64
	uploadSet, downloadSet, closed atomic.Bool
	closeOnce                      sync.Once
}

func (s *session) touch()                  { s.lastUnix.Store(time.Now().UnixNano()) }
func (s *session) lastActivity() time.Time { return time.Unix(0, s.lastUnix.Load()) }
func (s *session) close()                  { s.closeOnce.Do(func() { s.closed.Store(true); _ = s.conn.Close() }) }

type Server struct {
	cfg          Config
	mu           sync.RWMutex
	sessions     map[string]*session
	perIP        map[string]int
	pendingTotal int
	pendingIP    map[string]int
	logger       *log.Logger
	started      time.Time
	stop         chan struct{}
	stopOnce     sync.Once
}

func New(cfg Config, logger *log.Logger) (*Server, error) {
	var err error
	cfg, err = ValidateConfig(cfg)
	if err != nil {
		return nil, err
	}
	if logger == nil {
		logger = log.Default()
	}
	s := &Server{cfg: cfg, sessions: map[string]*session{}, perIP: map[string]int{}, pendingIP: map[string]int{}, logger: logger, started: time.Now(), stop: make(chan struct{})}
	go s.reaper()
	return s, nil
}
func (s *Server) Close() {
	s.stopOnce.Do(func() { close(s.stop) })
	s.mu.Lock()
	ids := make([]string, 0, len(s.sessions))
	for id := range s.sessions {
		ids = append(ids, id)
	}
	s.mu.Unlock()
	for _, id := range ids {
		s.removeAndClose(id)
	}
}
func (s *Server) Addr() string {
	return net.JoinHostPort(s.cfg.ListenHost, strconv.Itoa(s.cfg.ListenPort))
}
func (s *Server) TLSFiles() (string, string) { return s.cfg.TLSCert, s.cfg.TLSKey }
func (s *Server) Config() Config             { return s.cfg }
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc(s.cfg.BasePath+"/health", s.handleHealth)
	mux.HandleFunc(s.cfg.BasePath+"/session", s.handleCreate)
	mux.HandleFunc(s.cfg.BasePath+"/session/", s.handleSession)
	return s.headers(mux)
}
func (s *Server) headers(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set(protocol.HeaderProtocol, "1")
		next.ServeHTTP(w, r)
	})
}
func (s *Server) checkProtocol(w http.ResponseWriter, r *http.Request) bool {
	if r.Header.Get(protocol.HeaderProtocol) != "1" {
		s.writeError(w, 426, "unsupported_protocol", "X-Nexus-Protocol: 1 required")
		return false
	}
	return true
}
func remoteIP(r *http.Request) string {
	h, _, e := net.SplitHostPort(r.RemoteAddr)
	if e != nil {
		return r.RemoteAddr
	}
	return h
}
func (s *Server) allowed(target string) bool {
	for _, v := range s.cfg.AllowedTargets {
		if strings.EqualFold(v, target) {
			return true
		}
	}
	return false
}

func (s *Server) reserve(ip string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.sessions)+s.pendingTotal >= s.cfg.MaxSessions {
		return false
	}
	if s.perIP[ip]+s.pendingIP[ip] >= s.cfg.MaxSessionsPerIP {
		return false
	}
	s.pendingTotal++
	s.pendingIP[ip]++
	return true
}
func (s *Server) releaseReservation(ip string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.pendingTotal > 0 {
		s.pendingTotal--
	}
	if s.pendingIP[ip] > 1 {
		s.pendingIP[ip]--
	} else {
		delete(s.pendingIP, ip)
	}
}
func (s *Server) commitReservation(ip string, sess *session) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.pendingTotal > 0 {
		s.pendingTotal--
	}
	if s.pendingIP[ip] > 1 {
		s.pendingIP[ip]--
	} else {
		delete(s.pendingIP, ip)
	}
	s.sessions[sess.id] = sess
	s.perIP[ip]++
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		s.writeError(w, 405, "method_not_allowed", "")
		return
	}
	s.mu.RLock()
	active := len(s.sessions)
	pending := s.pendingTotal
	s.mu.RUnlock()
	w.Header().Set("Content-Type", protocol.ContentTypeJSON)
	_ = json.NewEncoder(w).Encode(protocol.HealthResponse{Status: "ok", ProtocolVersion: protocol.Version, ServerVersion: protocol.ServerVersion, ActiveSessions: active, PendingSessions: pending, MaxSessions: s.cfg.MaxSessions, UptimeSeconds: int64(time.Since(s.started).Seconds())})
}

func (s *Server) handleCreate(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		s.writeError(w, 405, "method_not_allowed", "")
		return
	}
	if !s.checkProtocol(w, r) {
		return
	}
	if ct := r.Header.Get("Content-Type"); ct != "" && !strings.HasPrefix(strings.ToLower(ct), protocol.ContentTypeJSON) {
		s.writeError(w, 415, "unsupported_media_type", "")
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
	var extra any
	if err := dec.Decode(&extra); err != io.EOF {
		s.writeError(w, 400, "invalid_json", "trailing data")
		return
	}
	if req.Protocol != "nexus-ssh-xhttp" || req.Version != protocol.Version {
		s.writeError(w, 426, "unsupported_protocol", "")
		return
	}
	nonce, err := base64.RawURLEncoding.DecodeString(req.ClientNonce)
	if err != nil || len(nonce) != 32 {
		s.writeError(w, 400, "invalid_nonce", "")
		return
	}
	if req.TargetHost == "" || req.TargetPort < 1 || req.TargetPort > 65535 {
		s.writeError(w, 400, "invalid_target", "")
		return
	}
	target := net.JoinHostPort(req.TargetHost, strconv.Itoa(req.TargetPort))
	if !s.allowed(target) {
		s.writeError(w, 403, "target_not_allowed", "")
		return
	}
	ip := remoteIP(r)
	if !s.reserve(ip) {
		s.writeError(w, 429, "session_limit", "")
		return
	}
	reserved := true
	defer func() {
		if reserved {
			s.releaseReservation(ip)
		}
	}()
	d := net.Dialer{Timeout: time.Duration(s.cfg.BackendConnectTimeoutMS) * time.Millisecond}
	conn, err := d.DialContext(r.Context(), "tcp", target)
	if err != nil {
		s.writeError(w, 502, "ssh_unavailable", "")
		return
	}
	id, err := random(32)
	if err != nil {
		_ = conn.Close()
		s.writeError(w, 500, "entropy_failure", "")
		return
	}
	tok, err := random(32)
	if err != nil {
		_ = conn.Close()
		s.writeError(w, 500, "entropy_failure", "")
		return
	}
	sess := &session{id: id, token: tok, remoteIP: ip, target: target, conn: conn, created: time.Now()}
	sess.touch()
	s.commitReservation(ip, sess)
	reserved = false
	w.Header().Set("Content-Type", protocol.ContentTypeJSON)
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(protocol.CreateSessionResponse{SessionID: id, SessionToken: tok, ExpiresIn: s.cfg.SessionExpiresSeconds})
}

func (s *Server) handleSession(w http.ResponseWriter, r *http.Request) {
	if !s.checkProtocol(w, r) {
		return
	}
	rel := strings.TrimPrefix(r.URL.Path, s.cfg.BasePath+"/session/")
	parts := strings.Split(strings.Trim(path.Clean("/"+rel), "/"), "/")
	if len(parts) < 1 || parts[0] == "" {
		s.writeError(w, 404, "unknown_session", "")
		return
	}
	sess := s.get(parts[0])
	if sess == nil {
		s.writeError(w, 404, "unknown_session", "")
		return
	}
	if !bearerOK(r.Header.Get("Authorization"), sess.token) {
		s.writeError(w, 401, "invalid_session_token", "")
		return
	}
	if len(parts) == 1 {
		if r.Method != http.MethodDelete {
			s.writeError(w, 405, "method_not_allowed", "")
			return
		}
		s.removeAndClose(sess.id)
		w.WriteHeader(204)
		return
	}
	switch parts[1] {
	case "download":
		s.download(w, r, sess)
	case "upload":
		s.upload(w, r, sess)
	default:
		s.writeError(w, 404, "not_found", "")
	}
}
func (s *Server) download(w http.ResponseWriter, r *http.Request, sess *session) {
	if r.Method != http.MethodGet {
		s.writeError(w, 405, "method_not_allowed", "")
		return
	}
	if !sess.downloadSet.CompareAndSwap(false, true) {
		s.writeError(w, 409, "download_exists", "")
		return
	}
	defer s.removeAndClose(sess.id)
	w.Header().Set("Content-Type", protocol.ContentTypeBytes)
	w.Header().Set("Transfer-Encoding", "chunked")
	w.WriteHeader(200)
	if f, ok := w.(http.Flusher); ok {
		f.Flush()
	}
	_, err := io.Copy(activityWriter{w: w, s: sess}, activityReader{r: sess.conn, s: sess})
	if err != nil && !sess.closed.Load() {
		s.logger.Printf("download session=%s ended: %v", short(sess.id), err)
	}
}
func (s *Server) upload(w http.ResponseWriter, r *http.Request, sess *session) {
	if r.Method != http.MethodPost {
		s.writeError(w, 405, "method_not_allowed", "")
		return
	}
	if !sess.downloadSet.Load() {
		s.writeError(w, 409, "download_not_ready", "")
		return
	}
	if !sess.uploadSet.CompareAndSwap(false, true) {
		s.writeError(w, 409, "upload_exists", "")
		return
	}
	_, err := io.Copy(activityWriter{w: sess.conn, s: sess}, activityReader{r: r.Body, s: sess})
	if tcp, ok := sess.conn.(*net.TCPConn); ok {
		_ = tcp.CloseWrite()
	}
	if err != nil && !sess.closed.Load() {
		s.logger.Printf("upload session=%s ended: %v", short(sess.id), err)
	}
	w.WriteHeader(204)
}
func bearerOK(h, token string) bool {
	const p = "Bearer "
	if !strings.HasPrefix(h, p) {
		return false
	}
	got := strings.TrimSpace(strings.TrimPrefix(h, p))
	if len(got) != len(token) {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(got), []byte(token)) == 1
}
func (s *Server) get(id string) *session { s.mu.RLock(); defer s.mu.RUnlock(); return s.sessions[id] }
func (s *Server) removeAndClose(id string) {
	s.mu.Lock()
	sess := s.sessions[id]
	if sess != nil {
		delete(s.sessions, id)
		s.perIP[sess.remoteIP]--
		if s.perIP[sess.remoteIP] <= 0 {
			delete(s.perIP, sess.remoteIP)
		}
	}
	s.mu.Unlock()
	if sess != nil {
		sess.close()
	}
}
func (s *Server) reaper() {
	t := time.NewTicker(time.Second)
	defer t.Stop()
	for {
		select {
		case <-s.stop:
			return
		case <-t.C:
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
