package server

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"github.com/nexusconnect/nexus-xhttp/internal/protocol"
	"io"
	"log"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestCreateRequiresAllowedTargetAndReturnsToken(t *testing.T) {
	ln, _ := net.Listen("tcp", "127.0.0.1:0")
	defer ln.Close()
	go func() {
		for {
			c, e := ln.Accept()
			if e != nil {
				return
			}
			go io.Copy(c, c)
		}
	}()
	cfg := Config{AllowedTargets: []string{ln.Addr().String()}, FixedTarget: ln.Addr().String(), BasePath: "/nexus-xhttp/v3", EnableLegacyV2: true}
	s, e := New(cfg, log.New(io.Discard, "", 0))
	if e != nil {
		t.Fatal(e)
	}
	ts := httptest.NewServer(s.Handler())
	defer ts.Close()
	nonce := base64.RawURLEncoding.EncodeToString(bytes.Repeat([]byte{1}, 32))
	b, _ := json.Marshal(protocol.CreateSessionRequest{Protocol: "nexus-ssh-xhttp", Version: 3, TargetHost: "127.0.0.1", TargetPort: ln.Addr().(*net.TCPAddr).Port, ClientNonce: nonce})
	req, _ := http.NewRequest("POST", ts.URL+"/nexus-xhttp/v3/session", bytes.NewReader(b))
	req.Header.Set(protocol.HeaderProtocol, "3")
	req.Header.Set("Content-Type", "application/json")
	resp, e := http.DefaultClient.Do(req)
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
	time.Sleep(10 * time.Millisecond)
}
