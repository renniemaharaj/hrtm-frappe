package sites

// extractAppNames extracts only the Name field from []AppInfo
func extractAppNames(apps []AppInfo) []string {
	names := make([]string, 0, len(apps))
	for _, app := range apps {
		names = append(names, app.Name)
	}
	return names
}
