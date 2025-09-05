package deployment

import (
	"fmt"

	"goftw/internal/environ"
	internalExec "goftw/internal/exec"
	"goftw/internal/supervisor"
)

// RunDevelopment starts the bench in development mode (bench start)
func RunDevelopment() error {
	fmt.Println("[MODE] DEVELOPMENT")
	_, err := internalExec.ExecuteCommand("bench", "start")
	return err
}

// RunProduction sets up supervisor and nginx for production mode
func RunProduction() error {
	fmt.Println("[MODE] PRODUCTION")
	supervisor.SetupSupervisor(environ.GetFrappeBenchPath())
	return nil
}
