package server

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"io"
	"log"
	"net"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"

	"github.com/nexusconnect/nexus-xhttp/internal/protocol"
)

func testConfig(target string) Config {
	return Config{AllowedTargets: []string{target}, BasePath: "/nexus-xhttp/v1", TLSCert: "/tmp/cert", TLSKey: "/tmp/key", MaxSessions: 10, MaxSessionsPerIP: 10}
}

func echoListener(t *testing.T) net.Listener {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	go func() {
		for {
			c, e := ln.Accept()
			if e != nil {
				return
			}
			go func() { defer c.Close(); _, _ = io.Copy(c, c) }()
		}
	}()
	return ln
}

func createRequest(t *testing.T, base string, target *net.TCPAddr) *http.Request {
	t.Helper()
	nonce := base64.RawURLEncoding.EncodeToString(bytes.Repeat([]byte{1}, 32))
	b, _ := json.Marshal(protocol.CreateSessionRequest{Protocol: "nexus-ssh-xhttp", Version: 1, TargetHost: "127.0.0.1", TargetPort: target.Port, ClientNonce: nonce})
	req, _ := http.NewRequest("POST", base+"/nexus-xhttp/v1/session", bytes.NewReader(b))
	req.Header.Set(protocol.HeaderProtocol, "1")
	req.Header.Set("Content-Type", "application/json")
	return req
}

func TestCreateRequiresAllowedTargetAndReturnsToken(t *testing.T) {
	ln := echoListener(t)
	defer ln.Close()
	s, e := New(testConfig(ln.Addr().String()), log.New(io.Discard, "", 0))
	if e != nil {
		t.Fatal(e)
	}
	defer s.Close()
	ts := httptest.NewServer(s.Handler())
	defer ts.Close()
	resp, e := http.DefaultClient.Do(createRequest(t, ts.URL, ln.Addr().(*net.TCPAddr)))
	if e != nil {
		t.Fatal(e)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 201 {
		t.Fatalf("status %d", resp.StatusCode)
	}
	var out protocol.CreateSessionResponse
	if e = json.NewDecoder(resp.Body).Decode(&out); e != nil {
		t.Fatal(e)
	}
	if out.SessionID == "" || out.SessionToken == "" || out.ExpiresIn <= 0 {
		t.Fatal("missing fields")
	}
}

func TestHealth(t *testing.T) {
	ln := echoListener(t)
	defer ln.Close()
	s, e := New(testConfig(ln.Addr().String()), log.New(io.Discard, "", 0))
	if e != nil {
		t.Fatal(e)
	}
	defer s.Close()
	r := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/nexus-xhttp/v1/health", nil)
	s.Handler().ServeHTTP(r, req)
	if r.Code != 200 {
		t.Fatalf("status %d", r.Code)
	}
	var h protocol.HealthResponse
	if e = json.Unmarshal(r.Body.Bytes(), &h); e != nil {
		t.Fatal(e)
	}
	if h.Status != "ok" || h.ProtocolVersion != 1 || h.ServerVersion != "1.2.0" {
		t.Fatalf("bad health: %+v", h)
	}
}

func TestReservationEnforcesGlobalAndPerIPLimits(t *testing.T) {
	cfg := testConfig("127.0.0.1:22")
	cfg.MaxSessions = 2
	cfg.MaxSessionsPerIP = 1
	s, e := New(cfg, log.New(io.Discard, "", 0))
	if e != nil {
		t.Fatal(e)
	}
	defer s.Close()
	if !s.reserve("10.0.0.1") {
		t.Fatal("first reservation rejected")
	}
	if s.reserve("10.0.0.1") {
		t.Fatal("per-IP limit not enforced while pending")
	}
	if !s.reserve("10.0.0.2") {
		t.Fatal("second IP reservation rejected")
	}
	if s.reserve("10.0.0.3") {
		t.Fatal("global limit not enforced while pending")
	}
	s.releaseReservation("10.0.0.1")
	s.releaseReservation("10.0.0.2")
}

func TestConcurrentReservationsNeverExceedLimit(t *testing.T) {
	cfg := testConfig("127.0.0.1:22")
	cfg.MaxSessions = 5
	cfg.MaxSessionsPerIP = 5
	s, e := New(cfg, log.New(io.Discard, "", 0))
	if e != nil {
		t.Fatal(e)
	}
	defer s.Close()
	var wg sync.WaitGroup
	accepted := make(chan bool, 100)
	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func() { defer wg.Done(); accepted <- s.reserve("10.0.0.1") }()
	}
	wg.Wait()
	close(accepted)
	n := 0
	for ok := range accepted {
		if ok {
			n++
		}
	}
	if n != 5 {
		t.Fatalf("accepted=%d want=5", n)
	}
}

func TestRejectsShortNonce(t *testing.T) {
	ln := echoListener(t)
	defer ln.Close()
	s, e := New(testConfig(ln.Addr().String()), log.New(io.Discard, "", 0))
	if e != nil {
		t.Fatal(e)
	}
	defer s.Close()
	ts := httptest.NewServer(s.Handler())
	defer ts.Close()
	b, _ := json.Marshal(protocol.CreateSessionRequest{Protocol: "nexus-ssh-xhttp", Version: 1, TargetHost: "127.0.0.1", TargetPort: ln.Addr().(*net.TCPAddr).Port, ClientNonce: base64.RawURLEncoding.EncodeToString([]byte{1})})
	req, _ := http.NewRequest("POST", ts.URL+"/nexus-xhttp/v1/session", bytes.NewReader(b))
	req.Header.Set(protocol.HeaderProtocol, "1")
	resp, e := http.DefaultClient.Do(req)
	if e != nil {
		t.Fatal(e)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 400 {
		t.Fatalf("status %d", resp.StatusCode)
	}
}
