package main

import (
	"context"
	"flag"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/nexusconnect/nexus-xhttp/internal/client"
)

func main() {
	server := flag.String("server", "", "https://host:port")
	base := flag.String("path", "/nexus-xhttp/v3", "base path")
	listen := flag.String("listen", "127.0.0.1:2222", "local listen")
	sni := flag.String("sni", "", "TLS SNI")
	host := flag.String("host", "", "HTTP Host")
	target := flag.String("target-host", "", "SSH target host (v2 only)")
	port := flag.Int("target-port", 22, "SSH target port (v2 only)")
	version := flag.Int("protocol", 3, "protocol version: 3 or legacy 1")
	flag.Parse()
	c, e := client.New(client.Config{ServerURL: *server, BasePath: *base, ListenAddr: *listen, SNI: *sni, HostHeader: *host, TargetHost: *target, TargetPort: *port, ProtocolVersion: *version})
	if e != nil {
		log.Fatal(e)
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	log.Fatal(c.ListenAndServe(ctx))
}
