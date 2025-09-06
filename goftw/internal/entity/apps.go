package entity

// AppInfo is a normalized representation of an app from `bench list-apps`.
type AppInfo struct {
	Name    string // e.g. "frappe"
	Version string // e.g. "15.x.x-develop"
	Commit  string // e.g. "14a68b9"
	Branch  string // e.g. "develop"
	Raw     string // original line
}
