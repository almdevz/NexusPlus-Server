package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/nexusconnect/nexus-xhttp/internal/server"
)

func main() {
	cfgPath := flag.String("config", "/etc/nexus-xhttp/server.json", "config file")
	check := flag.Bool("check", false, "validate configuration and exit")
	flag.Parse()
	b, e := os.ReadFile(*cfgPath)
	if e != nil {
		log.Fatal(e)
	}
	var cfg server.Config
	if e = json.Unmarshal(b, &cfg); e != nil {
		log.Fatal(e)
	}
	s, e := server.New(cfg, log.Default())
	if e != nil {
		log.Fatal(e)
	}
	if *check {
		fmt.Println("configuration valid")
		return
	}
	cert, key := s.TLSFiles()
	srv := &http.Server{Addr: s.Addr(), Handler: s.Handler(), ReadHeaderTimeout: 15 * time.Second, IdleTimeout: 180 * time.Second}
	log.Printf("Nexus XHTTP v3 listening on %s", s.Addr())
	log.Fatal(srv.ListenAndServeTLS(cert, key))
}
