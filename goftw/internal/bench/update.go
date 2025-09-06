package bench

// Update runs `bench update --patch` in the bench directory.
func Update(benchDir string) error {
	return RunInBenchPrintIO("update", "--patch")
}
