package gobackend

import (
	"encoding/json"
	"fmt"
)

// RiflayProviderCall exposes the existing upstream wrapper without reimplementing its ABI.
func RiflayProviderCall(id, method, argsJSON string) (string, error) {
	ext, err := getExtensionManager().GetExtension(id)
	if err != nil {
		return "", err
	}
	if !ext.Enabled {
		return "", fmt.Errorf("extension is disabled")
	}
	var args struct {
		Query   string `json:"query"`
		Track   string `json:"track"`
		Quality string `json:"quality"`
		Path    string `json:"path"`
		Item    string `json:"item"`
		Limit   int    `json:"limit"`
	}
	if err = json.Unmarshal([]byte(argsJSON), &args); err != nil {
		return "", err
	}
	p := newExtensionProviderWrapper(ext)
	var result interface{}
	switch method {
	case "search":
		if ext.Manifest.HasCustomSearch() {
			options, marshalErr := json.Marshal(riflaySearchOptions(ext.Manifest, args.Limit))
			if marshalErr != nil {
				return "", marshalErr
			}
			return CustomSearchWithExtensionJSON(id, args.Query, string(options))
		}
		result, err = p.SearchTracks(args.Query, args.Limit)
	case "track":
		result, err = p.GetTrack(args.Track)
	case "album":
		result, err = p.GetAlbum(args.Track)
	case "playlist":
		result, err = p.GetPlaylist(args.Track)
	case "artist":
		result, err = p.GetArtist(args.Track)
	case "stream":
		result, err = p.GetDownloadURL(args.Track, args.Quality)
	case "download":
		result, err = p.Download(args.Track, args.Quality, args.Path, args.Item, nil)
	default:
		return "", fmt.Errorf("unsupported provider operation")
	}
	if err != nil {
		return "", err
	}
	data, err := json.Marshal(result)
	return string(data), err
}

// Riflay: extensions choose their own song filter IDs. An unknown filter can
// suppress every result even when the upstream catalogue returns matching songs.
func riflaySearchOptions(manifest *ExtensionManifest, limit int) map[string]interface{} {
	if limit <= 0 {
		limit = 50
	}
	options := map[string]interface{}{"limit": limit}
	if manifest.SearchBehavior != nil {
		for _, filter := range manifest.SearchBehavior.Filters {
			switch filter.ID {
			case "track", "tracks", "song", "songs":
				options["filter"] = filter.ID
				return options
			}
		}
	}
	return options
}

// Complete a grant returned by the provider's own verification page.
func RiflayCompleteGrant(id, grant string) (string, error) {
	ext, err := getExtensionManager().GetExtension(id)
	if err != nil {
		return "", err
	}
	p := newExtensionProviderWrapper(ext)
	if err = p.lockReadyVM(); err != nil {
		return "", err
	}
	defer ext.VMMu.Unlock()
	SetExtensionSessionGrantByID(id, grant)
	value, err := ext.runtime.vm.RunString(`extension.completeGrant()`)
	if err != nil {
		return "", err
	}
	encoded, err := json.Marshal(value.Export())
	return string(encoded), err
}
