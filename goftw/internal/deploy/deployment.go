package deployment

import (
	"fmt"

	"goftw/internal/bench"
	"goftw/internal/environ"
	"goftw/internal/supervisor"
)

// RunDevelopment starts the bench in development mode (bench start)
func RunDevelopment() error {
	fmt.Println("[MODE] DEVELOPMENT")
	err := bench.RunInBenchPrintIO("start")
	return err
}

// RunProduction sets up supervisor and nginx for production mode
func RunProduction() error {
	fmt.Println("[MODE] PRODUCTION")
	supervisor.SetupSupervisor(environ.GetBenchPath())
	return nil
}
