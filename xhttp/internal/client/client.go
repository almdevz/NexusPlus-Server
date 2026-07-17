package client

import (
	"bufio"
	"context"
	"crypto/rand"
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"github.com/nexusconnect/nexus-xhttp/internal/protocol"
	"io"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"
)

type Config struct {
	ServerURL, BasePath, ListenAddr, SNI, HostHeader, TargetHost string
	TargetPort                                                   int
	ConnectTimeout                                               time.Duration
}
type Client struct{ cfg Config }

func New(c Config) (*Client, error) {
	if c.ServerURL == "" || c.TargetHost == "" || c.TargetPort < 1 {
		return nil, fmt.Errorf("server and target required")
	}
	if c.BasePath == "" {
		c.BasePath = "/nexus-xhttp/v1"
	}
	c.BasePath = "/" + strings.Trim(c.BasePath, "/")
	if c.ListenAddr == "" {
		c.ListenAddr = "127.0.0.1:2222"
	}
	if c.ConnectTimeout == 0 {
		c.ConnectTimeout = 15 * time.Second
	}
	return &Client{cfg: c}, nil
}
func (c *Client) ListenAndServe(ctx context.Context) error {
	ln, e := net.Listen("tcp", c.cfg.ListenAddr)
	if e != nil {
		return e
	}
	defer ln.Close()
	go func() { <-ctx.Done(); _ = ln.Close() }()
	for {
		co, e := ln.Accept()
		if e != nil {
			if ctx.Err() != nil {
				return nil
			}
			return e
		}
		go func() { defer co.Close(); _ = c.tunnel(ctx, co) }()
	}
}
func (c *Client) tunnel(ctx context.Context, local net.Conn) error {
	sess, e := c.create(ctx)
	if e != nil {
		return e
	}
	defer c.del(context.Background(), sess)
	down, e := c.openDownload(ctx, sess)
	if e != nil {
		return e
	}
	defer down.Close()
	up, e := c.openUpload(ctx, sess)
	if e != nil {
		return e
	}
	defer up.Close()
	errs := make(chan error, 2)
	go func() { _, e := io.Copy(up, local); _ = up.Close(); errs <- e }()
	go func() { _, e := io.Copy(local, down); errs <- e }()
	return <-errs
}

type session struct {
	ID, Token string
	Expires   int
}

func (c *Client) dialTLS() (*tls.Conn, *url.URL, error) {
	u, e := url.Parse(c.cfg.ServerURL)
	if e != nil {
		return nil, nil, e
	}
	host := u.Host
	if !strings.Contains(host, ":") {
		host = net.JoinHostPort(host, "443")
	}
	d := net.Dialer{Timeout: c.cfg.ConnectTimeout}
	raw, e := d.Dial("tcp", host)
	if e != nil {
		return nil, nil, e
	}
	sni := c.cfg.SNI
	if sni == "" {
		sni = u.Hostname()
	}
	t := tls.Client(raw, &tls.Config{ServerName: sni, MinVersion: tls.VersionTLS12, NextProtos: []string{"http/1.1"}})
	if e = t.Handshake(); e != nil {
		raw.Close()
		return nil, nil, e
	}
	return t, u, nil
}
func (c *Client) host(u *url.URL) string {
	if c.cfg.HostHeader != "" {
		return c.cfg.HostHeader
	}
	return u.Host
}
func (c *Client) create(ctx context.Context) (session, error) {
	var out session
	t, u, e := c.dialTLS()
	if e != nil {
		return out, e
	}
	defer t.Close()
	nonce := make([]byte, 32)
	_, _ = rand.Read(nonce)
	body, _ := json.Marshal(protocol.CreateSessionRequest{Protocol: "nexus-ssh-xhttp", Version: 1, TargetHost: c.cfg.TargetHost, TargetPort: c.cfg.TargetPort, ClientNonce: base64.RawURLEncoding.EncodeToString(nonce)})
	p := c.cfg.BasePath + "/session"
	fmt.Fprintf(t, "POST %s HTTP/1.1\r\nHost: %s\r\nUser-Agent: NexusConnect/1\r\nAccept: application/json\r\nContent-Type: application/json\r\nX-Nexus-Protocol: 1\r\nConnection: close\r\nContent-Length: %d\r\n\r\n", p, c.host(u), len(body))
	_, _ = t.Write(body)
	br := bufio.NewReader(t)
	resp, e := http.ReadResponse(br, &http.Request{Method: "POST"})
	if e != nil {
		return out, e
	}
	defer resp.Body.Close()
	if resp.StatusCode != 201 {
		return out, fmt.Errorf("create HTTP %d", resp.StatusCode)
	}
	var rr protocol.CreateSessionResponse
	if e = json.NewDecoder(resp.Body).Decode(&rr); e != nil {
		return out, e
	}
	return session{ID: rr.SessionID, Token: rr.SessionToken, Expires: rr.ExpiresIn}, nil
}
func (c *Client) openDownload(ctx context.Context, s session) (net.Conn, error) {
	t, u, e := c.dialTLS()
	if e != nil {
		return nil, e
	}
	p := c.cfg.BasePath + "/session/" + s.ID + "/download"
	fmt.Fprintf(t, "GET %s HTTP/1.1\r\nHost: %s\r\nAccept: application/octet-stream\r\nAuthorization: Bearer %s\r\nX-Nexus-Protocol: 1\r\nConnection: keep-alive\r\n\r\n", p, c.host(u), s.Token)
	br := bufio.NewReader(t)
	resp, e := http.ReadResponse(br, &http.Request{Method: "GET"})
	if e != nil {
		t.Close()
		return nil, e
	}
	if resp.StatusCode != 200 {
		t.Close()
		return nil, fmt.Errorf("download HTTP %d", resp.StatusCode)
	}
	return &readConn{Conn: t, r: resp.Body}, nil
}
func (c *Client) openUpload(ctx context.Context, s session) (net.Conn, error) {
	t, u, e := c.dialTLS()
	if e != nil {
		return nil, e
	}
	p := c.cfg.BasePath + "/session/" + s.ID + "/upload"
	fmt.Fprintf(t, "POST %s HTTP/1.1\r\nHost: %s\r\nContent-Type: application/octet-stream\r\nAuthorization: Bearer %s\r\nX-Nexus-Protocol: 1\r\nTransfer-Encoding: chunked\r\nExpect: 100-continue\r\nConnection: keep-alive\r\n\r\n", p, c.host(u), s.Token)
	br := bufio.NewReader(t)
	resp, e := http.ReadResponse(br, &http.Request{Method: "POST"})
	if e != nil {
		t.Close()
		return nil, e
	}
	if resp.StatusCode != 100 {
		t.Close()
		return nil, fmt.Errorf("upload expected 100 got %d", resp.StatusCode)
	}
	return &chunkWriteConn{Conn: t, bw: bufio.NewWriter(t), br: br}, nil
}
func (c *Client) del(ctx context.Context, s session) {
	t, u, e := c.dialTLS()
	if e != nil {
		return
	}
	defer t.Close()
	p := c.cfg.BasePath + "/session/" + s.ID
	fmt.Fprintf(t, "DELETE %s HTTP/1.1\r\nHost: %s\r\nAuthorization: Bearer %s\r\nX-Nexus-Protocol: 1\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", p, c.host(u), s.Token)
}

type readConn struct {
	net.Conn
	r io.ReadCloser
}

func (r *readConn) Read(p []byte) (int, error) { return r.r.Read(p) }

type chunkWriteConn struct {
	net.Conn
	bw     *bufio.Writer
	br     *bufio.Reader
	mu     sync.Mutex
	closed bool
}

func (c *chunkWriteConn) Write(p []byte) (int, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.closed {
		return 0, net.ErrClosed
	}
	if len(p) == 0 {
		return 0, nil
	}
	fmt.Fprintf(c.bw, "%x\r\n", len(p))
	if _, e := c.bw.Write(p); e != nil {
		return 0, e
	}
	if _, e := c.bw.WriteString("\r\n"); e != nil {
		return 0, e
	}
	if e := c.bw.Flush(); e != nil {
		return 0, e
	}
	return len(p), nil
}
func (c *chunkWriteConn) Close() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.closed {
		return nil
	}
	c.closed = true
	_, _ = c.bw.WriteString("0\r\n\r\n")
	_ = c.bw.Flush()
	_ = c.Conn.SetReadDeadline(time.Now().Add(5 * time.Second))
	resp, e := http.ReadResponse(c.br, &http.Request{Method: "POST"})
	if e == nil {
		_ = resp.Body.Close()
		if resp.StatusCode != 204 {
			e = fmt.Errorf("upload final HTTP %d", resp.StatusCode)
		}
	}
	_ = c.Conn.Close()
	return e
}

var _ = strconv.IntSize
