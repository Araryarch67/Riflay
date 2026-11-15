package gobackend

import "testing"

func TestRiflaySearchUsesDeclaredSongFilter(t *testing.T) {
	for _, id := range []string{"track", "tracks", "song", "songs"} {
		t.Run(id, func(t *testing.T) {
			manifest := &ExtensionManifest{SearchBehavior: &SearchBehaviorConfig{
				Filters: []SearchFilter{{ID: "albums"}, {ID: id}},
			}}
			options := riflaySearchOptions(manifest, 23)
			if options["filter"] != id || options["limit"] != 23 {
				t.Fatalf("wrong search options: %v", options)
			}
		})
	}
}

func TestRiflaySearchOmitsUnknownFilter(t *testing.T) {
	for _, behavior := range []*SearchBehaviorConfig{nil, {}, {Filters: []SearchFilter{{ID: "all"}}}} {
		options := riflaySearchOptions(&ExtensionManifest{SearchBehavior: behavior}, 0)
		if _, exists := options["filter"]; exists {
			t.Fatalf("undeclared filter passed to extension: %v", options)
		}
		if options["limit"] != 50 {
			t.Fatalf("missing default limit: %v", options)
		}
	}
}
