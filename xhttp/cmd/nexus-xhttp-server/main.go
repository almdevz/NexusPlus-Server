package main

import (
	"crypto/tls"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/nexusconnect/nexus-xhttp/internal/protocol"
	"github.com/nexusconnect/nexus-xhttp/internal/server"
)

func loadConfig(path string) (server.Config, error) {
	b, e := os.ReadFile(path)
	if e != nil {
		return server.Config{}, e
	}
	var cfg server.Config
	decErr := json.Unmarshal(b, &cfg)
	if decErr != nil {
		return cfg, decErr
	}
	return server.ValidateConfig(cfg)
}

func main() {
	cfgPath := flag.String("config", "/etc/nexus-xhttp/server.json", "config file")
	check := flag.Bool("check", false, "validate config and TLS files, then exit")
	version := flag.Bool("version", false, "print version and exit")
	flag.Parse()
	if *version {
		fmt.Printf("nexus-xhttp-server %s protocol=%d\n", protocol.ServerVersion, protocol.Version)
		return
	}
	cfg, e := loadConfig(*cfgPath)
	if e != nil {
		log.Fatal(e)
	}
	if _, e = tls.LoadX509KeyPair(cfg.TLSCert, cfg.TLSKey); e != nil {
		log.Fatalf("invalid TLS certificate/key: %v", e)
	}
	if *check {
		fmt.Printf("CONFIG_OK version=%s listen=%s:%d base_path=%s max_sessions=%d max_sessions_per_ip=%d\n", protocol.ServerVersion, cfg.ListenHost, cfg.ListenPort, cfg.BasePath, cfg.MaxSessions, cfg.MaxSessionsPerIP)
		return
	}
	s, e := server.New(cfg, log.Default())
	if e != nil {
		log.Fatal(e)
	}
	defer s.Close()
	cert, key := s.TLSFiles()
	srv := &http.Server{Addr: s.Addr(), Handler: s.Handler(), ReadHeaderTimeout: 15 * time.Second, IdleTimeout: 180 * time.Second, MaxHeaderBytes: 64 * 1024}
	log.Printf("Nexus XHTTP %s listening on %s", protocol.ServerVersion, s.Addr())
	log.Fatal(srv.ListenAndServeTLS(cert, key))
}
