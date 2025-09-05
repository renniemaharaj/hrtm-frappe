package redis

import (
	"fmt"
	"os/exec"
	"regexp"
	"time"
)

type Config struct {
	URL   string
	Debug bool
	Wait  bool
}

// parse host/port from redis://host:port
func parseHostPort(url string) (string, string) {
	re := regexp.MustCompile(`redis://([^:]+):?([0-9]*)`)
	matches := re.FindStringSubmatch(url)
	if len(matches) == 3 {
		port := matches[2]
		if port == "" {
			port = "6379"
		}
		return matches[1], port
	}
	return "", ""
}

// WaitForRedis waits for one Redis instance
func WaitForRedis(cfg Config) error {
	if !cfg.Wait {
		return nil
	}
	host, port := parseHostPort(cfg.URL)
	fmt.Printf("[WAIT] Redis at %s:%s...\n", host, port)

	for {
		cmd := exec.Command("redis-cli", "-h", host, "-p", port, "ping")
		err := cmd.Run()
		if err == nil {
			fmt.Printf("[OK] Redis %s:%s reachable.\n", host, port)
			return nil
		}
		if cfg.Debug {
			fmt.Printf("[DEBUG][REDIS %s:%s] waiting...\n", host, port)
		}
		time.Sleep(2 * time.Second)
	}
}
